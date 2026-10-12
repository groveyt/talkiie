import AppKit
import SwiftUI
import NaturalInputCore

@MainActor
final class FnHotkeyMonitor {
    static var mode: TapHotkey {
        let d = UserDefaults.standard
        return TapHotkey.resolve(stored: d.string(forKey: TapHotkey.defaultsKey),
                                 legacyFnEnabled: d.bool(forKey: TapHotkey.legacyFnDefaultsKey))
    }
    static var isFnMode: Bool { mode.needsInputMonitoring || stopTrigger.needsInputMonitoring }

    static var stopTrigger: StopTrigger {
        StopTrigger.resolve(stored: UserDefaults.standard.string(forKey: StopTrigger.defaultsKey))
    }

    static func migrateLegacySetting() {
        let d = UserDefaults.standard
        guard d.string(forKey: TapHotkey.defaultsKey) == nil else { return }
        let choice = TapHotkey.initialChoice(stored: nil,
                                             legacyFnEnabled: d.bool(forKey: TapHotkey.legacyFnDefaultsKey),
                                             alreadyConsented: ConsentStore.hasEverConsented)
        d.set(choice.rawValue, forKey: TapHotkey.defaultsKey)
    }

    private var active: TapHotkey = .off
    private var detector = FnTapDetector()
    private var doubleDetector = DoubleTapDetector()
    private var loggedInterruption = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var defaultsObserver: NSObjectProtocol?
    private let onTap: @MainActor () -> Void
    var onStopKeyTap: (@MainActor () -> Void)?

    init(onTap: @escaping @MainActor () -> Void) {
        self.onTap = onTap
        Self.migrateLegacySetting()
        apply()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    private func apply() {
        let want = Self.mode
        guard want != active else { return }
        teardown()
        active = want
        if want != .off {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .any) { [weak self] event in
                let type = event.type, flags = event.modifierFlags
                MainActor.assumeIsolated { self?.handle(type: type, flags: flags, global: true) }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
                let type = event.type, flags = event.modifierFlags
                MainActor.assumeIsolated { self?.handle(type: type, flags: flags, global: false) }
                return event
            }
        }
        if want.key == .fn {
            let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(t, forMode: .common)
            pollTimer = t
        }
        Log.record(.tapHotkey(mode: want))
        if want.needsInputMonitoring {
            Log.record(.inputMonitoringPreflight(allowed: CGPreflightListenEventAccess()))
            Self.requestInputMonitoringIfNeeded()
        }
    }

    private func teardown() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        detector = FnTapDetector()
        doubleDetector = DoubleTapDetector()
        polledFnCombined = false
        polledFnHID = false
        monitorFnSeen = false
        targetSeen = false
        fnHeldForDouble = false
        active = .off
    }

    static func requestInputMonitoringIfNeeded() {
        guard isFnMode, ConsentStore.allowsCapture, !CGPreflightListenEventAccess() else { return }
        _ = CGRequestListenEventAccess()
    }

    static let pollInterval: TimeInterval = 1.0 / 50
    private var pollTimer: Timer?
    private var polledFnCombined = false
    private var polledFnHID = false
    private var monitorFnSeen = false
    private var fnHeldForDouble = false
    private var stopDetector = FnTapDetector()
    private var stopDoubleDetector = DoubleTapDetector()
    private var stopFnHeldForDouble = false

    private func poll() {
        let combined = CGEventSource.flagsState(.combinedSessionState)
        let hid = CGEventSource.flagsState(.hidSystemState)
        let fnC = combined.contains(.maskSecondaryFn), fnH = hid.contains(.maskSecondaryFn)
        if fnC && !polledFnCombined { Self.counters.polledFnDownsCombined += 1 }
        if fnH && !polledFnHID { Self.counters.polledFnDownsHID += 1 }
        polledFnCombined = fnC
        polledFnHID = fnH
        let fn = fnC || fnH
        let others = !combined.union(hid).intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
        let now = ProcessInfo.processInfo.systemUptime

        switch active {
        case .fn:
            if detector.isFnHeld, fn, others { _ = detector.handle(.otherInput) }
            if fn != detector.isFnHeld {
                let wasHeld = detector.isFnHeld
                let tapped = detector.handle(.modifiers(fn: fn, others: others, at: now))
                if !wasHeld {
                    loggedInterruption = false
                    if now <= pendingComboUntil { _ = detector.handle(.otherInput) }
                }
                Log.record(.fnKey(down: fn, others: others, tapped: tapped))
                if tapped { onTap() }
            }
        case .doubleFn:
            if doubleDetector.isArmed(at: now), fn, others { _ = doubleDetector.handle(.otherInput) }
            if fn != fnHeldForDouble {
                fnHeldForDouble = fn
                let fired = doubleDetector.handle(.modifiers(fn: fn, others: others, at: now))
                Log.record(.fnKey(down: fn, others: others, tapped: fired))
                if fired {
                    Self.counters.doubleTaps += 1
                    Log.record(.doubleTap)
                    onTap()
                }
            }
        default:
            break
        }

        guard recording, case .key(.fn, let stopCount) = Self.stopTrigger,
              !(active.key == .fn && active.count == stopCount) else { return }
        if stopCount == 2 {
            if fn != stopFnHeldForDouble {
                stopFnHeldForDouble = fn
                if stopDoubleDetector.handle(.modifiers(fn: fn, others: others, at: now)) { onStopKeyTap?() }
            }
        } else if fn != stopDetector.isFnHeld {
            if stopDetector.handle(.modifiers(fn: fn, others: others, at: now)) { onStopKeyTap?() }
        }
    }

    private var pendingComboUntil: TimeInterval = -.infinity

    struct Counters {
        var globalEvents = 0, globalFlagsChanged = 0, localEvents = 0, localFlagsChanged = 0, fnDowns = 0
        var polledFnDownsCombined = 0, polledFnDownsHID = 0
        var targetDowns = 0, doubleTaps = 0
        var singleModifierTaps = 0
    }
    static let launchedAt = Date()
    private(set) static var counters = Counters()

    private func handle(type: NSEvent.EventType, flags: NSEvent.ModifierFlags, global: Bool) {
        if global { Self.counters.globalEvents += 1 } else { Self.counters.localEvents += 1 }
        if active.key == .control || active.key == .option || active.key == .command {
            handleModifierTap(type: type, flags: flags, global: global)
            return
        }
        guard active.key == .fn else { return }
        if type == .flagsChanged {
            if global { Self.counters.globalFlagsChanged += 1 } else { Self.counters.localFlagsChanged += 1 }
            let fn = flags.contains(.function)
            if fn && !monitorFnSeen { Self.counters.fnDowns += 1 }
            monitorFnSeen = fn
            guard !flags.intersection([.command, .option, .control, .shift]).isEmpty else { return }
        } else if !FnTapDetector.interrupts(eventType: type.rawValue) {
            return
        }
        let armed = active.isDoubleTap ? doubleDetector.isArmed(at: ProcessInfo.processInfo.systemUptime) : detector.isFnHeld
        guard armed else {
            if flags.contains(.function) {
                pendingComboUntil = ProcessInfo.processInfo.systemUptime + Self.pollInterval * 2
            }
            return
        }
        if !loggedInterruption {
            loggedInterruption = true
            Log.record(.fnTapInterrupted(eventType: type.rawValue))
        }
        if active.isDoubleTap { _ = doubleDetector.handle(.otherInput) } else { _ = detector.handle(.otherInput) }
    }

    private var targetSeen = false

    private static func targetFlag(_ mode: TapHotkey) -> NSEvent.ModifierFlags {
        switch mode.key {
        case .control: return .control
        case .option: return .option
        case .command: return .command
        case .fn, .none: return []
        }
    }

    private func handleModifierTap(type: NSEvent.EventType, flags: NSEvent.ModifierFlags, global: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if type == .flagsChanged {
            if global { Self.counters.globalFlagsChanged += 1 } else { Self.counters.localFlagsChanged += 1 }
            let target = Self.targetFlag(active)
            let down = flags.contains(target)
            let others = !flags.intersection([.command, .option, .control, .shift, .function])
                .subtracting(target).isEmpty
            if down && !targetSeen { Self.counters.targetDowns += 1 }
            targetSeen = down
            let fired: Bool
            if active.isDoubleTap {
                fired = doubleDetector.handle(.modifiers(fn: down, others: others, at: now))
            } else {
                fired = detector.handle(.modifiers(fn: down, others: others, at: now))
            }
            if fired {
                if active.isDoubleTap {
                    Self.counters.doubleTaps += 1
                    Log.record(.doubleTap)
                } else {
                    Self.counters.singleModifierTaps += 1
                    Log.record(.singleModifierTap)
                }
                onTap()
            }
            return
        }
        guard FnTapDetector.interrupts(eventType: type.rawValue) else { return }
        if active.isDoubleTap {
            guard doubleDetector.isArmed(at: now) else { return }
            _ = doubleDetector.handle(.otherInput)
        } else {
            guard detector.isFnHeld else { return }
            _ = detector.handle(.otherInput)
        }
    }

    private var recording = false
    private var stopMonitor: Any?
    private var stopLocalMonitor: Any?

    func beginRecordingStopWatch() {
        recording = true
        stopDetector = FnTapDetector()
        stopDoubleDetector = DoubleTapDetector()
        stopFnHeldForDouble = false
        if Self.stopTrigger == .anyKey {
            anyModifierStop = ModifierTapStop(excluding: active.key)
            guard stopMonitor == nil else { return }
            stopMonitor = NSEvent.addGlobalMonitorForEvents(matching: .any) { [weak self] event in
                let type = event.type, flags = event.modifierFlags
                MainActor.assumeIsolated { self?.handleAnyModifierStop(type: type, flags: flags) }
            }
            stopLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
                let type = event.type, flags = event.modifierFlags
                MainActor.assumeIsolated { self?.handleAnyModifierStop(type: type, flags: flags) }
                return event
            }
            return
        }
        guard case .key(let key, let count) = Self.stopTrigger, key != .fn, key != .none,
              !(key == active.key && count == active.count), stopMonitor == nil
        else { return }
        stopMonitor = NSEvent.addGlobalMonitorForEvents(matching: .any) { [weak self] event in
            let type = event.type, flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handleStopModifierTap(type: type, flags: flags) }
        }
        stopLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .any) { [weak self] event in
            let type = event.type, flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handleStopModifierTap(type: type, flags: flags) }
            return event
        }
    }

    func endRecordingStopWatch() {
        recording = false
        if let stopMonitor { NSEvent.removeMonitor(stopMonitor) }
        if let stopLocalMonitor { NSEvent.removeMonitor(stopLocalMonitor) }
        stopMonitor = nil
        stopLocalMonitor = nil
    }

    private var anyModifierStop = ModifierTapStop(excluding: .none)

    private func handleAnyModifierStop(type: NSEvent.EventType, flags: NSEvent.ModifierFlags) {
        guard recording, Self.stopTrigger == .anyKey else { return }
        if type == .flagsChanged {
            var held: Set<ModifierTapStop.Modifier> = []
            if flags.contains(.shift) { held.insert(.shift) }
            if flags.contains(.control) { held.insert(.control) }
            if flags.contains(.option) { held.insert(.option) }
            if flags.contains(.command) { held.insert(.command) }
            if anyModifierStop.handle(held: held, fnHeld: flags.contains(.function),
                                      at: ProcessInfo.processInfo.systemUptime) {
                onStopKeyTap?()
            }
            return
        }
        guard FnTapDetector.interrupts(eventType: type.rawValue) else { return }
        anyModifierStop.otherInput()
    }

    private func handleStopModifierTap(type: NSEvent.EventType, flags: NSEvent.ModifierFlags) {
        guard recording, case .key(let key, let count) = Self.stopTrigger, key != .fn, key != .none else { return }
        let target = Self.targetFlag(TapHotkey(key: key, count: count))
        let now = ProcessInfo.processInfo.systemUptime
        if type == .flagsChanged {
            let down = flags.contains(target)
            let others = !flags.intersection([.command, .option, .control, .shift, .function])
                .subtracting(target).isEmpty
            let fired = count == 2
                ? stopDoubleDetector.handle(.modifiers(fn: down, others: others, at: now))
                : stopDetector.handle(.modifiers(fn: down, others: others, at: now))
            if fired { onStopKeyTap?() }
            return
        }
        guard FnTapDetector.interrupts(eventType: type.rawValue) else { return }
        if count == 2 {
            guard stopDoubleDetector.isArmed(at: now) else { return }
            _ = stopDoubleDetector.handle(.otherInput)
        } else {
            guard stopDetector.isFnHeld else { return }
            _ = stopDetector.handle(.otherInput)
        }
    }
}

extension FnHotkeyMonitor {
    static func globeKeySetting() -> GlobeKeySetting {
        let domain = "com.apple.HIToolbox" as CFString
        CFPreferencesAppSynchronize(domain)
        let v = CFPreferencesCopyAppValue("AppleFnUsageType" as CFString, domain) as? Int
        return GlobeKeySetting(rawValue: v)
    }

    static var inputMonitoringAllowed: Bool { CGPreflightListenEventAccess() }

    static var inputMonitoringMissing: Bool { isFnMode && !inputMonitoringAllowed }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openKeyboardSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct FnHotkeySettingsSection: View {
    @AppStorage(TapHotkey.defaultsKey) private var mode: TapHotkey = .off
    @ObservedObject private var refresh = SettingsRefresh.shared

    var body: some View {
        let _ = refresh.generation
        Picker("按鍵", selection: $mode) {
            ForEach(Array(StartStopSettings.tapGroups.enumerated()), id: \.offset) { i, group in
                if i > 0 { Divider() }
                ForEach(group, id: \.self) { Text(StartStopSettings.tapMenuLabel($0)).tag($0) }
            }
        }
        if mode.needsInputMonitoring, !FnHotkeyMonitor.inputMonitoringAllowed {
            SettingsHelp(text: "fn 需要「輸入監控」權限（Talkiie 只看 fn 有沒有按下，不看你打的字）。允許之後要重新打開 Talkiie。",
                         warn: true)
            HStack {
                Spacer()
                Button("打開「輸入監控」設定…") { FnHotkeyMonitor.openInputMonitoringSettings() }
            }
        }
        if mode.key == .fn, let warning = FnHotkeyMonitor.globeKeySetting().menuWarning {
            SettingsHelp(text: warning, warn: true)
            HStack {
                Spacer()
                Button("打開鍵盤設定…") { FnHotkeyMonitor.openKeyboardSettings() }
            }
        }
        switch mode {
        case .singleOption, .singleControl, .singleCommand:
            SettingsHelp(text: "按一下比按兩下更容易誤觸（打字時順手碰到就會開始）。", warn: true)
        case .doubleOption, .doubleControl, .doubleCommand:
            SettingsHelp(text: "若系統「聽寫」也設成按兩下同一個鍵，兩邊會一起觸發。")
        default:
            EmptyView()
        }
    }
}

struct StopTriggerSettingsSection: View {
    @AppStorage(StopTrigger.defaultsKey) private var storedTrigger = StopTrigger.defaultValue.rawValue
    @ObservedObject private var refresh = SettingsRefresh.shared

    private var trigger: StopTrigger { StopTrigger.resolve(stored: storedTrigger) }

    var body: some View {
        let _ = refresh.generation
        Picker("結束方式", selection: Binding(get: { trigger.rawValue }, set: { storedTrigger = $0 })) {
            ForEach(Array(StartStopSettings.stopGroups.enumerated()), id: \.offset) { i, group in
                if i > 0 { Divider() }
                ForEach(group, id: \.rawValue) { Text(StartStopSettings.stopMenuLabel($0)).tag($0.rawValue) }
            }
        }
        switch trigger {
        case .anyKey:
            SettingsHelp(text: "錄音中按任何鍵就結束並打字；Esc 取消，⌘Tab 這類組合鍵不算。")
        case .key(let key, _):
            if key == .fn {
                if !FnHotkeyMonitor.inputMonitoringAllowed {
                    SettingsHelp(text: "fn 需要「輸入監控」權限（Talkiie 只看 fn 有沒有按下，不看你打的字）。允許之後要重新打開 Talkiie。",
                                 warn: true)
                    HStack {
                        Spacer()
                        Button("打開「輸入監控」設定…") { FnHotkeyMonitor.openInputMonitoringSettings() }
                    }
                }
                if FnHotkeyMonitor.mode.key != .fn {
                    SettingsHelp(text: "fn 只有在開始也用 fn 時才偵測得到（fn 的按鍵事件會被系統吃掉），現在這個設定不會生效。",
                                 warn: true)
                }
            } else {
                SettingsHelp(text: "只有這個鍵、快捷鍵與 Esc 會結束；其他鍵照常打字。")
            }
        }
    }
}
