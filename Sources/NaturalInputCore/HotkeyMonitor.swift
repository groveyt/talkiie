#if os(macOS)
import AppKit
import Carbon

@MainActor
public final class HotkeyMonitor {
    public private(set) var combo: HotkeyCombo

    private static let signature = OSType(0x505A_5359)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var recordingKeyRefs: [RecordingKey: EventHotKeyRef] = [:]
    private var editCaptureKeyRefs: [UInt32: EventHotKeyRef] = [:]

    public var onEditCaptureKey: (@MainActor () -> Void)?

    public var onRecordingKey: (@MainActor (RecordingKey) -> Void)?

    public struct RecordingKeyFailure: Equatable, Sendable {
        public let key: RecordingKey
        public let status: OSStatus
    }
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private let onEvent: @MainActor (Event) -> Void

    public enum Event: Sendable {
        case hotkeyPressed
        case sleepOrLock
    }

    public init?(combo: HotkeyCombo = .standard, onEvent: @escaping @MainActor (Event) -> Void) {
        self.onEvent = onEvent
        self.combo = combo

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, user in
            guard let user else { return noErr }
            var hkID = EventHotKeyID()
            let got = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let id = got == noErr ? hkID.id : RecordingKey.mainHotKeyID
            MainActor.assumeIsolated {
                Unmanaged<HotkeyMonitor>.fromOpaque(user).takeUnretainedValue().dispatch(hotKeyID: id)
            }
            return noErr
        }, 1, &spec, me, &handlerRef)

        let (status, ref) = Self.registerMain(combo)
        hotKeyRef = ref
        guard status == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(ws, name)
        }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked"))
    }

    private static func registerMain(_ combo: HotkeyCombo) -> (OSStatus, EventHotKeyRef?) {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers,
                                         EventHotKeyID(signature: signature, id: RecordingKey.mainHotKeyID),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return (status == noErr ? OSStatus(paramErr) : status, nil) }
        return (noErr, ref)
    }

    public var isMainRegistered: Bool { hotKeyRef != nil }

    @discardableResult
    public func rebind(to new: HotkeyCombo) -> OSStatus {
        let wasRegistered = hotKeyRef != nil
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let (status, ref) = Self.registerMain(new)
        if status == noErr {
            hotKeyRef = ref
            combo = new
            return noErr
        }
        if wasRegistered { hotKeyRef = Self.registerMain(combo).1 }
        return status
    }

    public func suspendMain() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    @discardableResult
    public func resumeMain() -> OSStatus {
        guard hotKeyRef == nil else { return noErr }
        let (status, ref) = Self.registerMain(combo)
        hotKeyRef = ref
        return status
    }

    private func dispatch(hotKeyID: UInt32) {
        if EditCaptureKey.hotKeyIDs.contains(hotKeyID) {
            guard editCaptureKeyRefs[hotKeyID] != nil else { return }
            onEditCaptureKey?()
        } else if let key = RecordingKey.from(hotKeyID: hotKeyID) {
            guard recordingKeyRefs[key] != nil else { return }
            onRecordingKey?(key)
        } else if hotKeyID == RecordingKey.mainHotKeyID {
            guard hotKeyRef != nil else { return }
            onEvent(.hotkeyPressed)
        }
    }

    public func registerRecordingKeys(stopTrigger: StopTrigger = .anyKey) -> [RecordingKeyFailure] {
        var keys: [RecordingKey] = [.escape]
        if stopTrigger == .anyKey {
            keys += [.space, .returnKey] + AnyKeyStopSet.keyCodes.map(RecordingKey.other)
                + AnyKeyStopSet.shiftedKeyCodes.map(RecordingKey.otherShifted)
        }
        var failures: [RecordingKeyFailure] = []
        for key in keys where recordingKeyRefs[key] == nil {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key.keyCode, key.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: key.hotKeyID),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                recordingKeyRefs[key] = ref
            } else {
                failures.append(RecordingKeyFailure(key: key, status: status == noErr ? OSStatus(paramErr) : status))
            }
        }
        return failures
    }

    public func unregisterRecordingKeys() {
        for ref in recordingKeyRefs.values { UnregisterEventHotKey(ref) }
        recordingKeyRefs.removeAll()
    }

    public var registeredRecordingKeys: Set<RecordingKey> { Set(recordingKeyRefs.keys) }

    @discardableResult
    public func registerEditCaptureKey(_ shortcut: EditCaptureShortcut = .defaultValue) -> OSStatus {
        let wanted = shortcut.bindings
        let wantedIDs = Set(wanted.map(\.hotKeyID))
        for (id, ref) in editCaptureKeyRefs where !wantedIDs.contains(id) {
            UnregisterEventHotKey(ref)
            editCaptureKeyRefs[id] = nil
        }
        for b in wanted where editCaptureKeyRefs[b.hotKeyID] == nil {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(b.keyCode, b.modifiers,
                                             EventHotKeyID(signature: Self.signature, id: b.hotKeyID),
                                             GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                unregisterEditCaptureKey()
                return status == noErr ? OSStatus(paramErr) : status
            }
            editCaptureKeyRefs[b.hotKeyID] = ref
        }
        return noErr
    }

    public func unregisterEditCaptureKey() {
        for ref in editCaptureKeyRefs.values { UnregisterEventHotKey(ref) }
        editCaptureKeyRefs.removeAll()
    }

    public var isEditCaptureKeyRegistered: Bool { !editCaptureKeyRefs.isEmpty }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent(.sleepOrLock) }
        }
        observers.append((center, token))
    }

    public static func currentSecureInput() -> SecureInputPolicy.State {
        SecureInputPolicy.State(systemSecureInputEnabled: IsSecureEventInputEnabled(),
                                focusIsSecureTextField: false,
                                isRecording: false)
    }

    isolated deinit {
        for (center, token) in observers { center.removeObserver(token) }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        unregisterRecordingKeys()
        unregisterEditCaptureKey()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
#endif
