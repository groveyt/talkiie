import AVFoundation
import AppKit
import Carbon.HIToolbox
import NaturalInputCore
import NaturalInputEgress
import SwiftUI

@main
struct TalkiieApp: App {
    @StateObject private var model = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(model)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var icon = MenuBarIcon.shared

    var body: some View {
        switch icon.state {
        case .recording:
            Image(nsImage: Self.redDot)
        case .idle, .processing:
            Image(nsImage: icon.image)
                .accessibilityLabel(icon.state == .processing ? "Talkiie 處理中" : "Talkiie")
        }
    }

    static let redDot: NSImage = {
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            .applying(.init(paletteColors: [.systemRed]))
        let img = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "錄音中")!
            .withSymbolConfiguration(cfg)!
        img.isTemplate = false
        return img
    }()
}

struct MenuContent: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(TapHotkey.defaultsKey) private var tapHotkey: TapHotkey = .off

    static let timeFormat: Date.FormatStyle = .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)

    var body: some View {
        OnboardingMenuSection()
        FeatureNudgeMenuSection()
        Edition.MenuHeader()
        switch model.phase {
        case .idle:
            Text(MenuStatus.idleLine(hotkey: model.hotkey.label, tap: tapHotkey))
        case .recording(let since):
            Text(MenuStatus.recordingLine(elapsed: AppModel.elapsed(since: since), hotkey: model.hotkey.label,
                                          tap: tapHotkey, stop: AppModel.stopTrigger))
        case .sending:
            Text(Edition.Copy.sendingLine)
        }
        Text(Edition.Copy.destinationLine).foregroundStyle(.secondary)
        Edition.StatusSection()
        ForEach(Array(warnings.enumerated()), id: \.offset) { _, w in
            let text = w.text(time: { $0.formatted(Self.timeFormat) }, remoteUnreachable: Edition.Copy.remoteUnreachableWarning)
            switch w.opens {
            case .permissions: Button(text) { SettingsWindow.show(.permissions) }
            case .general: Button(text) { SettingsWindow.show(.general) }
            case nil: Text(text)
            }
        }

        Divider()
        RecentDictationMenu()

        Divider()
        Button("設定…") { SettingsWindow.show() }
            .keyboardShortcut(",")
        Button("回報問題…") { Edition.reportProblem() }
        Button("結束 Talkiie") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var warnings: [MenuStatus.Warning] {
        MenuStatus.warnings(permissions: model.permissions,
                            inputMonitoringMissing: FnHotkeyMonitor.isFnMode && !FnHotkeyMonitor.inputMonitoringAllowed,
                            hotkeyRegistered: model.hotkeyRegistered, hotkey: model.hotkey.label,
                            lastRemoteFailure: model.lastRemoteFailure)
    }
}

struct RecentDictationMenu: View {
    @EnvironmentObject var model: AppModel
    static let labelLimit = 28

    static func label(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > labelLimit ? String(oneLine.prefix(labelLimit)) + "…" : oneLine
    }

    var body: some View {
        Menu("最近口述") {
            if model.recentDictations.isEmpty {
                Text("還沒有口述").foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.recentDictations.enumerated()), id: \.offset) { _, entry in
                    Menu((entry.original == nil && entry.rewritten == nil ? "" : "✎ ") + Self.label(entry.text)) {
                        Button("重新插入到目前游標處") { model.reinsert(entry.text) }
                        Button("複製（會放進剪貼簿）") { model.copyToClipboard(entry.text) }
                        if let alternate = entry.listAlternate {
                            Divider()
                            Text((entry.listKind == .remove ? "不排條列：" : "排成條列：") + Self.label(alternate))
                                .foregroundStyle(.secondary)
                            Button("插入另一個版本到目前游標處") { model.reinsert(alternate) }
                            Button("複製另一個版本（會放進剪貼簿）") { model.copyToClipboard(alternate) }
                        }
                        if let rewritten = entry.rewritten {
                            Divider()
                            Text("整理後的版本：" + Self.label(rewritten)).foregroundStyle(.secondary)
                            Button("插入整理後的版本到目前游標處") { model.reinsert(rewritten) }
                            Button("複製整理後的版本（會放進剪貼簿）") { model.copyToClipboard(rewritten) }
                        }
                        if let original = entry.original {
                            Divider()
                            Text("已換成整理後的版本，原文：" + Self.label(original)).foregroundStyle(.secondary)
                            Button("插入原文到目前游標處") { model.insertOriginal(entry) }
                            Button("複製原文（會放進剪貼簿）") { model.copyToClipboard(original) }
                        }
                    }
                }
                Divider()
                Button("清空最近口述") { model.clearHistory() }
            }
            Divider()
            Text("只在記憶體，結束 Talkiie 即清除").foregroundStyle(.secondary)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { Edition.willFinishLaunching() }
        #if DEBUG
        if CommandLine.arguments.contains("--help") {
            InsertSelfTestLine.emit(.help)
            exit(0)
        }
        #endif
    }

    @MainActor
    static func startAfterConsent() {
        ConsentWindow.shared.onAccepted = {
            Edition.consentGranted()
            let m = AppModel.shared
            m.refreshPermissions()
            if OnboardingController.shared.presentAfterConsent() { return }
            if m.permissions.microphone == .notDetermined { m.perform(.requestMicrophone) }
            if !m.permissions.accessibilityTrusted { m.perform(.promptAccessibility) }
            FnHotkeyMonitor.requestInputMonitoringIfNeeded()
        }
        if ConsentStore.allowsCapture {
            Edition.consentGranted()
            OnboardingController.shared.launchedConsented()
        } else {
            ConsentWindow.shared.presentIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.clearHistory() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task.detached(priority: .utility) { WhisperTokenCounter.prewarm() }
        MainActor.assumeIsolated { EditCorrectionStore.shared.prune(EditCaptureSettings.retention) }
        MainActor.assumeIsolated { UsageStatsRecorder.launchMaintenance() }
        #if DEBUG
        #if RESEARCH_CAPTURE
        ResearchCapture.shared.launchMaintenance()
        #endif
        let selftest = CommandLine.arguments.contains { $0.hasSuffix("-selftest") || $0 == "--hud-selftest-hold" }
        if selftest { MainActor.assumeIsolated { UsageStatsRecorder.enabled = false } }
        #else
        let selftest = false
        #endif
        if !selftest {
            MainActor.assumeIsolated {
                StartChimePlayer.shared.prepare()
                Edition.launched(consented: ConsentStore.hasEverConsented)
                OnboardingController.shared.evaluateAtLaunch(consentedBefore: ConsentStore.hasEverConsented)
                Self.startAfterConsent()
            }
        }
        #if DEBUG
        #if RESEARCH_CAPTURE
        let researchSelfTest = CommandLine.arguments.contains("--research-selftest")
        #else
        let researchSelfTest = false
        #endif
        if researchSelfTest {
            #if RESEARCH_CAPTURE
            Task { @MainActor in await ResearchSelfTest.run() }
            #endif
        } else if CommandLine.arguments.contains("--insert-selftest") {
            Task { @MainActor in await InsertSelfTest.run() }
        } else if CommandLine.arguments.contains("--stream-selftest") {
            Task { @MainActor in await StreamSelfTest.run() }
        } else if CommandLine.arguments.contains("--transcribe-selftest") {
            Task { @MainActor in await TranscribeSelfTest.run() }
        } else if CommandLine.arguments.contains("--hud-selftest") {
            Task { @MainActor in await HUDSelfTest.run() }
        } else if CommandLine.arguments.contains("--fallback-selftest") {
            Task { @MainActor in await FallbackSelfTest.run() }
        } else if CommandLine.arguments.contains("--list-toggle-selftest") {
            Task { @MainActor in await ListToggleSelfTest.run() }
        } else if CommandLine.arguments.contains("--whats-new-selftest") {
            Task { @MainActor in await WhatsNewSnapshots.run() }
        } else if CommandLine.arguments.contains("--settings-snapshots") {
            Task { @MainActor in await SettingsSnapshots.run() }
        } else if CommandLine.arguments.contains("--settings-selftest") {
            Task { @MainActor in await SettingsSelfTest.run() }
        } else if CommandLine.arguments.contains("--onboarding-selftest") {
            Task { @MainActor in await OnboardingSelfTest.run() }
        } else if CommandLine.arguments.contains("--menubar-selftest") {
            Task { @MainActor in
                if let check = await MenuBarSelfTest.run(AppModel.shared) {
                    MenuBarSelfTestLine.emit(.failed(check: check))
                    exit(22)
                }
                MenuBarSelfTestLine.emit(.passed(frames: MenuBarSelfTest.expectedFrames))
                exit(0)
            }
        } else if PlusThemeShots.handle(CommandLine.arguments) {
        }
        #endif
    }
}

#if DEBUG
@MainActor
enum HUDSelfTest {
    static let successTexts = [
        "你好，這是測試。",
        "這是一段比較長的轉錄文字，用來確認 HUD 在長句時會換行而不是橫跨整個螢幕，"
            + "也確認 NSHostingView 在內容尺寸改變時不會再撞到約束更新的例外。\n"
            + "這是第二段：排版後的段落以換行分隔，HUD 與最近口述都顯示分段後的文字。",
        "",
    ]

    static let deliveryOutcomes: [TranscriptDelivery.Outcome] =
        [.inserted(.enforced), .inserted(.unverified)]
        + InsertionPolicy.Refusal.allCases.map { .refused($0) }
        + [.aborted(sentUnits: 0, reason: .secureInput),
           .aborted(sentUnits: 16, reason: .focusAppChanged),
           .aborted(sentUnits: 16, reason: .focusElementChanged),
           .aborted(sentUnits: 32, reason: .cursorMoved),
           .aborted(sentUnits: 0, reason: .postFailed),
           .busy]

    static func contentIsDistinct() -> Bool {
        let failures = deliveryOutcomes.map(DeliveryContent.init).filter { !$0.succeeded }
        let keys = failures.map { $0.title + "|" + ($0.detail ?? "") }
        return Set(keys).count == keys.count && failures.allSatisfy { $0.caption.contains("最近口述") }
            && DeliveryContent(.inserted(.enforced)).title == "已插入"
            && !DeliveryContent(.refused(.accessibilityNotTrusted)).canReinsert
            && !DeliveryContent(.aborted(sentUnits: 5, reason: .cursorMoved)).canReinsert
            && DeliveryContent(.aborted(sentUnits: 0, reason: .cursorMoved)).canReinsert
            && DeliveryContent(.busy).canReinsert
    }

    static func fallbackRoutingBehaves() -> Bool {
        let panel: [TranscriptDelivery.Outcome] = [.refused(.noFocus), .refused(.notEditable),
                                                    .aborted(sentUnits: 0, reason: .focusAppChanged)]
        let notPanel: [TranscriptDelivery.Outcome] = [.refused(.passwordField), .refused(.systemSecureInput),
                                                       .refused(.accessibilityNotTrusted), .refused(.composing),
                                                       .aborted(sentUnits: 16, reason: .focusAppChanged),
                                                       .busy, .inserted(.enforced)]
        return panel.allSatisfy { AppModel.fallbackPanelReason($0) != nil }
            && notPanel.allSatisfy { AppModel.fallbackPanelReason($0) == nil }
    }

    static func round(_ m: AppModel, text: String, outcome: TranscriptDelivery.Outcome,
                      pause: (Double) async -> Void, fast: Bool = false) async {
        m.recordingStarted()
        await pause(fast ? 0.3 : 0.6)
        m.recordingStopped(.secondPress)
        await pause(fast ? 0.1 : 0.3)
        m.transmissionStarted()
        await pause(fast ? 0.2 : 0.6)
        m.debugFinishRound(text, simulated: outcome)
        await pause(fast ? 0.6 : 1.0)
    }

    static func run() async {
        SelfTestEnvironment.exitIfUnusable(.hud)
        func exit(_ code: Int32) -> Never {
            if code != 0 { SelfTestEnvironment.exitIfUnusable(.hud, during: true) }
            Darwin.exit(code)
        }
        let m = AppModel.shared
        let hud = RecordingHUD.capsule
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--hud-selftest"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
            CapsuleStyleSnapshots.render(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
            CapsuleStyleSnapshots.renderRoundNotices(to: URL(fileURLWithPath: args[i + 1], isDirectory: true))
        }
        func capsuleParked() async -> Bool {
            await pause(0.1)
            return !(RecordingHUD.showingCapsule && RecordingHUD.isVisible) && !hud.debugTickerRunning
                && hud.levels.allSatisfy { $0 == 0 } && OrbNSView.debugRunningTimers == 0
        }
        if let i = CommandLine.arguments.firstIndex(of: "--hud-selftest-hold"),
           i + 1 < CommandLine.arguments.count, let secs = Double(CommandLine.arguments[i + 1]) {
            m.recordingStarted()
            await feedLevels(seconds: secs)
            m.recordingStopped(.secondPress)
            m.transmissionStarted()
            m.transcriptionFailed(Edition.transcriptionFailureMessage)
            await pause(0.8)
        }

        guard rmsWindowsBehave() else { exit(10) }
        guard levelMappingBehaves() else { exit(11) }
        guard orbBehaves() else { exit(13) }
        guard textPipelineBehaves() else { exit(14) }
        guard await orbStopsWhenHidden() else { exit(23) }
        guard consentGuardBlocksStart(m) else { exit(24) }
        guard await editCaptureStaysClosed(m) else { exit(26) }
        guard StartChimePlayer.shared.debugAllPresetsLoad() else { exit(25) }
        guard hotkeyRebindBehaves(m) else { exit(27) }
        guard await themeTrialPreviewBehaves() else { exit(30) }
        if Edition.plusUnlocked {
            guard await auroraGlowBehaves(m) else { exit(31) }
            guard await glassSurfaceBehaves(m) else { exit(32) }
        } else {
            guard await lockedThemeFallsBackToCapsule(m) else { exit(33) }
        }

        if let check = await MenuBarSelfTest.run(m) {
            MenuBarSelfTestLine.emit(.failed(check: check))
            exit(22)
        }
        MenuBarSelfTestLine.emit(.passed(frames: MenuBarSelfTest.expectedFrames))

        m.recordingStarted()
        guard RecordingHUD.showingCapsule, RecordingHUD.isVisible, hud.mode == .listening,
              hud.levels.allSatisfy({ $0 == 0 }) else { exit(12) }
        guard waveformRollsLeft(hud) else { exit(12) }
        await feedLevels(seconds: 1.2)
        guard hud.levels.contains(where: { $0 > 0.2 }) else { exit(15) }
        m.recordingStopped(.cancelled)
        await pause(0.5)
        m.recordingStarted()
        await feedLevels(seconds: 0.3)
        RecordingHUD.hide()
        guard await capsuleParked() else { exit(21) }
        m.recordingStopped(.cancelled)
        await pause(0.5)

        for reason in RecordingStopReason.allCases {
            m.recordingStarted()
            await feedLevels(seconds: 0.8)
            m.recordingStopped(reason)
            if !reason.sendsAudio {
                guard await capsuleParked() else { exit(21) }
                hud.push(rms: [0.3])
                m.recordingStarted()
                hud.tick()
                guard hud.debugTickerRunning, hud.levels.allSatisfy({ $0 == 0 }) else { exit(21) }
                m.recordingStopped(.cancelled)
                guard await capsuleParked() else { exit(21) }
            }
            if reason.sendsAudio {
                await pause(0.3)
                m.transmissionStarted()
                m.transcriptionFailed(Edition.transcriptionFailureMessage + "\n"
                    + AudioLevelSummary(samples: [Float](repeating: 0.3, count: 16_000)).text)
            }
            await pause(0.8)
        }
        for text in successTexts {
            hud.debugClearHistory()
            await round(m, text: text, outcome: .inserted(.enforced), pause: pause)
            guard m.phase == .idle else { exit(3) }
            if text.isEmpty { continue }
            guard hud.modeHistory == [.listening, .thinking(transmitting: false), .thinking(transmitting: true), .success]
            else { exit(16) }
            guard hud.modeHistory.allSatisfy({ mode in
                let listening = mode == .listening
                return listening || CapsuleStyle.allCases.allSatisfy { !$0.showsButtons(listening: listening, hovering: true) }
            }) else { exit(29) }
            await pause(RecordingHUD.successHoldSeconds + Motion.fast + 0.4)
            guard !RecordingHUD.isVisible else { exit(16) }
        }
        guard contentIsDistinct() else { exit(4) }
        for (i, outcome) in deliveryOutcomes.enumerated() {
            await round(m, text: "第 \(i + 1) 種插字結果的預覽文字。", outcome: outcome, pause: pause, fast: true)
            guard m.phase == .idle else { exit(3) }
        }
        let expected = min(DictationHistory.defaultLimit,
                           successTexts.filter { !$0.isEmpty }.count + deliveryOutcomes.count)
        guard m.history.count == expected,
              m.recentDictations.first?.text == "第 \(deliveryOutcomes.count) 種插字結果的預覽文字。" else { exit(5) }
        guard fallbackRoutingBehaves(), FallbackPanel.isShowing, FallbackPanel.debugPanel?.isKeyWindow == false
        else { exit(28) }
        m.clearHistory()
        guard m.history.isEmpty else { exit(5) }
        guard !FallbackPanel.isShowing else { exit(28) }

        let keysAvailable = m.debugRegisteredRecordingKeys != nil
        if !keysAvailable { HUDSelfTestLine.emit(.keysSkippedHotkeyUnavailable) }
        func began() -> Bool {
            guard m.debugBeginSimulatedRecording(), case .recording = m.phase, hud.mode == .listening else { return false }
            return !keysAvailable || Set(RecordingKey.allCases).isSubset(of: m.debugRegisteredRecordingKeys ?? [])
        }
        func stoppedCleanly() -> Bool {
            m.debugRecorderIsIdle && m.phase == .idle && (!keysAvailable || m.debugRegisteredRecordingKeys == [])
                && MenuBarIcon.shared.state == .idle && !MenuBarIcon.shared.isAnimating
        }
        for press in [{ RecordingHUD.onButton?(.cancel) }, { m.debugFeedRecordingKey(.escape) }] {
            guard began() else { exit(17) }
            await feedLevels(seconds: 0.6)
            hud.debugClearHistory()
            press()
            guard stoppedCleanly(), !RecordingHUD.showingCapsule, hud.modeHistory.isEmpty else { exit(17) }
            guard await capsuleParked() else { exit(21) }
            await pause(0.8)
        }
        for press in [{ RecordingHUD.onButton?(.confirm) }, { m.debugFeedRecordingKey(.space) }] {
            guard began() else { exit(18) }
            await feedLevels(seconds: 0.6)
            hud.debugClearHistory()
            press()
            guard stoppedCleanly(), hud.modeHistory.first == .thinking(transmitting: false) else { exit(18) }
            await pause(0.8)
        }
        guard began() else { exit(19) }
        await feedLevels(seconds: 0.3)
        m.debugAbortRecording()
        guard stoppedCleanly() else { exit(19) }
        guard await capsuleParked() else { exit(21) }
        await pause(0.5)

        guard await realClickKeepsFocus(m) else { exit(20) }
        await pause(0.3)
        guard MenuBarIcon.shared.state == .idle, !MenuBarIcon.shared.isAnimating,
              MenuBarIcon.shared.image === MenuBarIcon.shared.idle else { exit(22) }
        guard EditReadback.liveReadCount == 0 else { exit(26) }
        HUDSelfTestLine.emit(.passed)
        exit(0)
    }

    static func hotkeyRebindBehaves(_ m: AppModel) -> Bool {
        let original = m.hotkey
        let savedData = UserDefaults.standard.data(forKey: HotkeyCombo.defaultsKey)
        defer {
            if m.hotkey != original { _ = m.setHotkey(original) }
            if let savedData { UserDefaults.standard.set(savedData, forKey: HotkeyCombo.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: HotkeyCombo.defaultsKey) }
        }
        let optionK = HotkeyCombo(keyCode: EditCaptureKey.keyCode, mods: [.option])
        guard m.setHotkey(optionK) != nil, m.hotkey == original else { return false }
        guard m.hotkeyRegistered else { return true }
        let fresh = HotkeyCombo(keyCode: UInt32(kVK_ANSI_9), mods: [.control, .option, .shift])
        guard m.setHotkey(fresh) == nil, m.hotkey == fresh, m.hotkeyRegistered,
              AppModel.hotkeyLabel == "⌃⌥⇧9",
              AppModel.recordingKeyCaption(failed: [.space])?.contains("⌃⌥⇧9") == true,
              Edition.Copy.points(hotkey: AppModel.hotkeyLabel)[0].contains("⌃⌥⇧9"),
              HotkeyCombo.load() == fresh else { return false }
        let taken = HotkeyCombo(keyCode: UInt32(kVK_ANSI_8), mods: [.control, .option, .shift])
        var blocker: EventHotKeyRef?
        guard RegisterEventHotKey(taken.keyCode, taken.carbonModifiers, EventHotKeyID(signature: 0x5445_5354, id: 99),
                                  GetApplicationEventTarget(), 0, &blocker) == noErr, let blocker else { return false }
        defer { UnregisterEventHotKey(blocker) }
        guard let message = m.setHotkey(taken), message.contains("⌃⌥⇧9"),
              m.hotkey == fresh, m.hotkeyRegistered, m.debugMainHotkeyRegistered == true,
              HotkeyCombo.load() == fresh else { return false }
        return m.setHotkey(original) == nil && m.hotkey == original && m.hotkeyRegistered
    }

    static func lockedThemeFallsBackToCapsule(_ m: AppModel) async -> Bool {
        let savedStored = UserDefaults.standard.string(forKey: HUDTheme.defaultsKey)
        defer {
            if let savedStored { UserDefaults.standard.set(savedStored, forKey: HUDTheme.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: HUDTheme.defaultsKey) }
            RecordingHUD.hide()
        }
        UserDefaults.standard.set(HUDTheme.aurora.rawValue, forKey: HUDTheme.defaultsKey)
        m.recordingStarted()
        try? await Task.sleep(for: .seconds(0.2))
        let fellBack = RecordingHUD.showingCapsule && !RecordingHUD.glowVisible
        m.recordingStopped(.cancelled)
        try? await Task.sleep(for: .seconds(0.2))
        return fellBack
    }

    static func consentGuardBlocksStart(_ m: AppModel) -> Bool {
        let saved = ConsentStore.debugOverride
        ConsentWindow.debugSuppressWindow = true
        defer { ConsentStore.debugOverride = saved; ConsentWindow.debugSuppressWindow = false }
        for stale in [Int?.none, Int?.some(0), Int?.some(Edition.consentVersion + 1)] {
            ConsentStore.debugOverride = .some(stale)
            let before = ConsentWindow.shared.debugRequests
            let chimesBefore = StartChimePlayer.shared.debugPlays
            m.debugPressHotkey()
            guard m.phase == .idle, m.debugRecorderIsIdle, MenuBarIcon.shared.state == .idle,
                  ConsentWindow.shared.debugRequests == before + 1,
                  StartChimePlayer.shared.debugPlays == chimesBefore else { return false }
        }
        return true
    }

    static func editCaptureStaysClosed(_ m: AppModel) async -> Bool {
        let savedToggle = EditCaptureSettings.debugOverride
        let savedConsent = ConsentStore.debugOverride
        defer {
            EditCaptureSettings.debugOverride = savedToggle
            ConsentStore.debugOverride = savedConsent
            EditCaptureSettings.shared.debugRefresh()
            m.syncEditCaptureKey()
        }
        ConsentStore.debugOverride = .some(Edition.consentVersion)
        let controller = EditCaptureController.shared

        EditCaptureSettings.debugOverride = false
        m.syncEditCaptureKey()
        guard EditReadback.liveReadCount == 0, m.debugEditCaptureKeyRegistered != true, !m.editCaptureKeyRegistered,
              controller.makeTrace() == nil, controller.lastInsertion == nil,
              m.debugPressEditCaptureKey() == .disabled else { return false }
        try? await Task.sleep(for: .seconds(0.3))
        guard EditReadback.liveReadCount == 0 else { return false }

        EditCaptureSettings.debugOverride = true
        m.syncEditCaptureKey()
        guard m.editCaptureKeyRegistered == (m.debugEditCaptureKeyRegistered == true),
              controller.makeTrace() != nil, EditReadback.liveReadCount == 0 else { return false }
        controller.forget()
        guard m.debugPressEditCaptureKey() == nil else { return false }
        try? await Task.sleep(for: .seconds(0.5))
        RecordingHUD.hide()
        return EditReadback.liveReadCount == 0
    }

    static func feedLevels(seconds: Double) async {
        let steps = Int(seconds * AudioCapture.levelHz)
        for i in 0..<max(1, steps) {
            let t = Double(i) / AudioCapture.levelHz
            let rms = Float(0.02 + 0.2 * abs(sin(t * 5.3)) * abs(sin(t * 1.7)))
            RecordingHUD.capsule.push(rms: [rms])
            try? await Task.sleep(for: .seconds(1 / AudioCapture.levelHz))
        }
    }

    static func rmsWindowsBehave() -> Bool {
        let alt = (0..<4800).map { $0 % 2 == 0 ? Float(0.6) : Float(0.8) }
        let w = AudioCapture.rmsWindows(alt, windowSize: 1600)
        let want = Float(0.5).squareRoot()
        guard w.count == 3, w.allSatisfy({ abs($0 - want) < 1e-4 }) else { return false }
        guard AudioCapture.rmsWindows([Float](repeating: 0.1, count: 1600 + 900), windowSize: 1600).count == 2,
              AudioCapture.rmsWindows([Float](repeating: 0.1, count: 1600 + 100), windowSize: 1600).count == 1,
              AudioCapture.rmsWindows([], windowSize: 1600).isEmpty,
              AudioCapture.rmsWindows([Float](repeating: 0, count: 3200), windowSize: 1600) == [0, 0]
        else { return false }
        return true
    }

    static func levelMappingBehaves() -> Bool {
        CapsuleModel.normalized(0) == 0 && CapsuleModel.normalized(.nan) == 0
            && CapsuleModel.normalized(0.001) == 0
            && CapsuleModel.normalized(1) == 1
            && CapsuleModel.normalized(0.05) > 0.3 && CapsuleModel.normalized(0.05) < 0.8
    }

    static func waveformRollsLeft(_ hud: CapsuleModel) -> Bool {
        let n = CapsuleModel.barCount
        hud.push(rms: [1])
        hud.tick()
        guard hud.levels[n - 1] == 1, hud.levels[n - 2] == 0 else { return false }
        hud.push(rms: [0.05])
        hud.tick()
        guard hud.levels[n - 1] == CapsuleModel.normalized(0.05), hud.levels[n - 2] == 1 else { return false }
        hud.tick()
        return hud.levels[n - 1] > 0 && hud.levels[n - 1] < CapsuleModel.normalized(0.05) && hud.levels[n - 3] == 1
    }

    static func orbBehaves() -> Bool {
        let size = Double(OrbView.size)
        let still = OrbGeometry.frame(.listening(level: 0), size: size, time: OrbGeometry.staticTime)
        guard !still.isEmpty,
              still == OrbGeometry.frame(.listening(level: 0), size: size, time: OrbGeometry.staticTime),
              OrbGeometry.voiceShape(level: 1).wob > OrbGeometry.voiceShape(level: 0).wob else { return false }
        let scan = OrbGeometry.frame(.transcribing, size: size, time: 1).map(\.alpha)
        return (scan.max() ?? 0) > 0.8 && (scan.min() ?? 1) < 0.5
    }

    static func orbStopsWhenHidden() async -> Bool {
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        let before = OrbNSView.debugRunningTimers
        let panel = CapsulePanel(contentRect: NSRect(x: 0, y: 0, width: 36, height: 36),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let orb = OrbNSView(frame: panel.contentLayoutRect)
        panel.contentView = orb
        orb.animating = true
        guard OrbNSView.debugRunningTimers == before else { return false }
        panel.orderFrontRegardless()
        await pause(0.1)
        guard OrbNSView.debugRunningTimers == before + 1 else { return false }
        panel.orderOut(nil)
        await pause(0.1)
        guard OrbNSView.debugRunningTimers == before, orb.animating else { return false }
        panel.orderFrontRegardless()
        await pause(0.3)
        let resumed = OrbNSView.debugRunningTimers == before + 1
        orb.animating = false
        panel.orderOut(nil)
        return resumed && OrbNSView.debugRunningTimers == before
    }

    static func textPipelineBehaves() -> Bool {
        let converted = TraditionalChinese.convert("第一段说完了。\n第二段开始")
        guard converted == "第一段說完了。\n第二段開始",
              TranscriptDelivery.paragraphs(converted) == ["第一段說完了。", "第二段開始"],
              TranscriptDelivery.paragraphs("一段") == ["一段"] else { return false }
        guard TaiwanPhrases.isAvailable,
              TraditionalChinese.convert("启动服务器上的软件看着") == "啟動服務器上的軟件看著" else { return false }
        let list = TraditionalChinese.convert(TranscriptFormatter.format(
            [TranscriptSegment(text: "有两件事，第一点是速度，第二点是用词", start: 0, end: 2)]))
        guard TranscriptDelivery.paragraphs(list) == ["有兩件事：", "1. 速度", "2. 用詞"] else { return false }
        guard AppModel.recordingKeyCaption(failed: []) == nil,
              let esc = AppModel.recordingKeyCaption(failed: [.escape]), esc.contains("Esc"), esc.contains("✕"),
              let space = AppModel.recordingKeyCaption(failed: [.space]), space.contains("Space"), space.contains("✓")
        else { return false }
        return InsertSelfTest.decode("第一段\\n第二段 OK") == "第一段\n第二段 OK"
            && InsertSelfTest.decode("沒有分隔") == "沒有分隔"
    }

    static func realClickKeepsFocus(_ m: AppModel) async -> Bool {
        guard Permissions.accessibilityTrusted() else {
            HUDSelfTestLine.emit(.clickSkippedNoAccessibility)
            return true
        }
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        guard session?["CGSSessionScreenIsLocked"] as? Bool != true else {
            HUDSelfTestLine.emit(.clickSkippedScreenLocked)
            return true
        }
        m.debugLastClickFrozen = nil
        guard m.debugBeginSimulatedRecording() else { return false }
        try? await Task.sleep(for: .seconds(0.6))
        let frontBefore = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let activeBefore = NSApp.isActive
        let focusBefore = TranscriptDelivery.freezeTarget(stage: .selftest)
        let clicks = m.debugCapsuleClicks
        guard let p = RecordingHUD.buttonCenterCG(.confirm) else { m.debugAbortRecording(); return false }
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                .post(tap: .cghidEventTap)
            try? await Task.sleep(for: .seconds(0.05))
        }
        try? await Task.sleep(for: .seconds(0.8))
        let reached = m.debugCapsuleClicks == clicks + 1
        if !m.debugRecorderIsIdle { m.debugAbortRecording() }
        let kept = NSWorkspace.shared.frontmostApplication?.processIdentifier == frontBefore
            && (activeBefore || !NSApp.isActive) && !RecordingHUD.panelIsKey
        let sameField = reached ? focusBefore.map { m.debugLastClickFrozen == $0 } : nil
        HUDSelfTestLine.emit(.click(reachedButton: reached, focusKept: kept, sameField: sameField))
        return reached && kept && sameField != false
    }
}
#endif

#if DEBUG
@MainActor
enum CapsuleStyleSnapshots {
    private static let states: [(name: String, mode: CapsuleModel.Mode)] = [
        ("listening", .listening),
        ("thinking-settling", .thinking(transmitting: false)),
        ("thinking-sending", .thinking(transmitting: true)),
        ("success", .success),
    ]

    static func render(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let savedStyle = UserDefaults.standard.string(forKey: CapsuleStyle.defaultsKey)
        defer {
            if let savedStyle { UserDefaults.standard.set(savedStyle, forKey: CapsuleStyle.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: CapsuleStyle.defaultsKey) }
        }
        for style in CapsuleStyle.allCases {
            UserDefaults.standard.set(style.rawValue, forKey: CapsuleStyle.defaultsKey)
            for (name, mode) in states {
                let model = CapsuleModel()
                model.set(mode: mode, caption: nil)
                if mode == .listening {
                    model.push(rms: [0.3])
                    model.tick()
                }
                save(CapsuleView(model: model) { _ in }, "capsule-\(style.rawValue)-\(name).png", in: dir)
                if style == .minimal, mode == .listening {
                    model.hovering = true
                    save(CapsuleView(model: model) { _ in }, "capsule-\(style.rawValue)-\(name)-hover.png", in: dir)
                }
            }
        }
    }

    static func renderRoundNotices(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        save(DeliveryPill(content: DeliveryContent(.inserted(.enforced)), text: "範例口述文字。") { _ in },
             "delivery-inserted.png", in: dir)
        save(NoticePill(message: RoundNotices.emptyTranscript(level: nil)), "notice-empty-heard.png", in: dir)
        let quiet = AudioLevelSummary(samples: [Float](repeating: 0, count: 16_000))
        save(NoticePill(message: RoundNotices.emptyTranscript(level: quiet)), "notice-empty-silent.png", in: dir)
        let model = CapsuleModel()
        model.set(mode: .thinking(transmitting: true), caption: RoundNotices.stillWorkingCaption)
        save(CapsuleView(model: model) { _ in }, "thinking-still-working.png", in: dir)
    }

    static func save<V: View>(_ view: V, _ name: String, in dir: URL) {
        let controller = NSHostingController(rootView: view.fixedSize())
        let size = controller.sizeThatFits(in: NSSize(width: 4000, height: 4000))
        guard size.width > 0, size.height > 0 else { return }
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        guard let rep = controller.view.bitmapImageRepForCachingDisplay(in: controller.view.bounds) else { return }
        controller.view.cacheDisplay(in: controller.view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: png)
    }
}
#endif

#if DEBUG
@MainActor
enum MenuBarSelfTest {
    static let expectedFrames = 140

    static func run(_ m: AppModel) async -> Int? {
        let icon = MenuBarIcon.shared
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        func atIdle() -> Bool {
            m.menuBarState == .idle && icon.state == .idle && !icon.isAnimating && icon.image === icon.idle
        }
        func enterProcessing() {
            m.recordingStarted()
            m.recordingStopped(.secondPress)
        }
        guard let c = icon.carousel, c.frames.count == expectedFrames, c.durations.count == expectedFrames,
              c.durations.allSatisfy({ $0 > 0 }),
              c.frames.allSatisfy({ $0.size == MenuBarIcon.pointSize && $0.isTemplate }),
              Set(c.frames.map(ObjectIdentifier.init)).count == expectedFrames,
              icon.idle.isTemplate, icon.idle.size == MenuBarIcon.pointSize
        else { return 1 }
        guard atIdle() else { return 2 }
        m.recordingStarted()
        guard m.menuBarState == .recording, icon.state == .recording, !icon.isAnimating else { return 3 }
        let starts = icon.debugStarts
        m.recordingStopped(.secondPress)
        guard icon.state == .processing, icon.isAnimating, icon.frameIndex == 0,
              icon.image === c.frames[0], icon.debugStarts == starts + 1 else { return 4 }
        await pause(c.durations[0] / 2)
        guard icon.frameIndex == 0 else { return 5 }
        await pause(c.durations[0] / 2 + 0.5)
        guard icon.frameIndex > 0, icon.image === c.frames[icon.frameIndex] else { return 5 }
        m.transmissionStarted()
        m.debugFinishRound("選單列自我測試。", simulated: .inserted(.enforced))
        guard m.phase == .idle, icon.state == .processing, icon.isAnimating,
              icon.debugStarts == starts + 1 else { return 6 }
        await pause(0.2)
        guard atIdle() else { return 6 }
        enterProcessing()
        guard icon.isAnimating else { return 7 }
        m.transmissionStarted()
        m.transcriptionFailed(Edition.transcriptionFailureMessage)
        guard atIdle() else { return 7 }
        m.recordingStarted()
        m.recordingStopped(.cancelled)
        guard atIdle() else { return 8 }
        enterProcessing()
        m.debugFinishRound("", simulated: .inserted(.enforced))
        guard atIdle() else { return 9 }
        let systemReduceMotion = icon.reduceMotion
        icon.reduceMotion = { true }
        enterProcessing()
        let still = icon.state == .processing && !icon.isAnimating && icon.image === icon.idle
        m.transcriptionFailed(Edition.transcriptionFailureMessage)
        icon.reduceMotion = systemReduceMotion
        guard still, atIdle() else { return 10 }
        m.clearHistory()
        RecordingHUD.hide()
        return nil
    }
}
#endif

#if DEBUG
@MainActor
enum TranscribeSelfTest {
    static func run() async {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let wav = value(after: "--transcribe-selftest"), value(after: "--egress-log-dir") != nil else {
            SelfTestLine.emit(.usage); exit(2)
        }
        guard var samples = readMono16k(URL(fileURLWithPath: wav)) else {
            SelfTestLine.emit(.unreadableFixture); exit(2)
        }
        let outcome = await AppModel.shared.selfTestTranscribe(samples)
        AudioPipeline.zeroize(&samples)
        switch outcome {
        case .text(let text) where !text.isEmpty:
            SelfTestLine.emit(.transcript(characters: text.count)); exit(0)
        case .text:
            SelfTestLine.emit(.emptyTranscript); exit(1)
        case .failed(let message):
            SelfTestLine.emit(message == Edition.transcriptionFailureMessage ? .remoteUnreachable : .unexpectedFailure)
            exit(1)
        }
    }

    static func readMono16k(_ url: URL) -> [Float]? {
        guard let file = try? AVAudioFile(forReading: url),
              file.processingFormat.sampleRate == Double(Edition.transcriberSampleRate),
              file.processingFormat.channelCount == 1,
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buf)) != nil,
              let ch = buf.floatChannelData?[0]
        else { return nil }
        return Array(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)))
    }
}
#endif

#if DEBUG
@MainActor
enum StreamSelfTest {
    static let blockFrames = 1024

    static func run() async {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard let wav = value(after: "--stream-selftest"), value(after: "--egress-log-dir") != nil else {
            SelfTestLine.emit(.usage); exit(2)
        }
        guard var samples = TranscribeSelfTest.readMono16k(URL(fileURLWithPath: wav)) else {
            SelfTestLine.emit(.unreadableFixture); exit(2)
        }
        let runs = max(1, Int(value(after: "--stream-selftest-runs") ?? "1") ?? 1)
        let clock = ContinuousClock()
        func millis(_ d: Duration) -> Int { Int((d / .milliseconds(1)).rounded()) }
        var allOK = true
        for r in 1...runs {
            let t0 = clock.now
            let single = await AppModel.shared.selfTestTranscribe(samples)
            let singleMillis = millis(clock.now - t0)

            let round = AppModel.shared.selfTestStreamingRound()
            var tail: StreamingTranscription.ChunkReport?
            round.onChunkFinished = { if $0.isTail { tail = $0 } }
            let pipeline = AudioPipeline(inputSampleRate: Double(AudioBuffer.sampleRate), maxSeconds: AudioBuffer.maxSeconds)
            let window = Int(Double(AudioBuffer.sampleRate) / AudioCapture.levelHz)
            var cuts = 0, forced = 0, i = 0
            let start = clock.now
            while i < samples.count {
                let n = min(blockFrames, samples.count - i)
                try? await clock.sleep(until: start + .seconds(Double(i + n) / Double(AudioBuffer.sampleRate)))
                var block = Array(samples[i..<(i + n)])
                let levels = AudioCapture.rmsWindows(block, windowSize: window)
                pipeline.ingest(mono: block)
                AudioPipeline.zeroize(&block)
                if let cut = round.ingested(levels: levels, pipeline: pipeline) {
                    cuts += 1
                    if cut.reason == .forced { forced += 1 }
                }
                i += n
            }
            let stoppedAt = clock.now
            let summary = round.stop(pipeline: pipeline)
            let streamed = await round.outcome()
            let streamMillis = millis(clock.now - stoppedAt)

            func chars(_ o: TranscriptionOutcome?) -> Int? {
                if case .text(let t)? = o, !t.isEmpty { return TraditionalChinese.convert(t).count }
                return nil
            }
            let same: Bool = { if case .text(let a) = single, case .text(let b)? = streamed { return a == b }; return false }()
            SelfTestLine.emit(.streamRun(run: r, singleMillis: singleMillis, singleCharacters: chars(single),
                                         streamMillis: streamMillis, streamCharacters: chars(streamed),
                                         chunks: summary.chunksSent, cutsDuringRecording: cuts, forcedCuts: forced,
                                         tailSent: summary.tailSent, sameText: same,
                                         tailPrepMillis: tail?.timing?.prepMillis, tailNetworkMillis: tail?.timing?.networkMillis,
                                         tailParseMillis: tail?.timing?.parseMillis, tailQueuedMillis: tail?.queuedMillis))
            if chars(single) == nil || chars(streamed) == nil { allOK = false }
        }
        AudioPipeline.zeroize(&samples)
        exit(allOK ? 0 : 1)
    }
}
#endif

#if DEBUG
@MainActor
enum InsertSelfTest {
    static let settleSeconds: Double = 0.5

    static func decode(_ arg: String) -> String {
        arg.replacingOccurrences(of: "\\n", with: TranscriptionOutcome.paragraphSeparator)
    }

    static func run() async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--insert-selftest"), i + 1 < args.count, !args[i + 1].isEmpty else {
            InsertSelfTestLine.emit(.usage); exit(2)
        }
        if let c = args.firstIndex(of: "--click"), c + 1 < args.count {
            let parts = args[c + 1].split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let p = CGPoint(x: parts[0], y: parts[1])
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                        .post(tap: .cghidEventTap)
                }
                try? await Task.sleep(for: .seconds(0.8))
            }
        }
        let outcome = await AppModel.shared.deliverNewTranscript(decode(args[i + 1]),
                                                                  to: TranscriptDelivery.freezeTarget(stage: .selftest))
        InsertSelfTestLine.emit(.outcome(outcome))
        guard case .inserted = outcome else { exit(1) }
        try? await Task.sleep(for: .seconds(settleSeconds))
        exit(0)
    }
}
#endif
