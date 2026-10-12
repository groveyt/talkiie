public struct HotkeyPolicy: Sendable {

    public enum State: Equatable, Sendable {
        case idle
        case recording(startedAt: Double)
    }

    public enum Event: Equatable, Sendable {
        case hotkeyPressed(now: Double, secure: SecureInputPolicy.State)
        case secureInputObserved(SecureInputPolicy.State)
        case sleepOrLock
        case tick(now: Double, secure: SecureInputPolicy.State)
        case captureFull(secure: SecureInputPolicy.State)
        case confirmKey(secure: SecureInputPolicy.State)
        case cancelKey
    }

    public enum Action: Equatable, Sendable {
        case none
        case startRecording
        case stopRecording(RecordingStopReason)
        case refuseToStart(SecureInputPolicy.Message)
    }

    public private(set) var state: State = .idle
    public let maxSeconds: Double

    public init(maxSeconds: Double = AudioBuffer.maxSeconds) {
        precondition(maxSeconds > 0)
        self.maxSeconds = maxSeconds
    }

    public mutating func handle(_ event: Event) -> Action {
        switch (state, event) {
        case (.idle, .hotkeyPressed(let now, let secure)):
            let before = SecureInputPolicy.State(systemSecureInputEnabled: secure.systemSecureInputEnabled,
                                                 focusIsSecureTextField: secure.focusIsSecureTextField,
                                                 isRecording: false)
            if case .refuseBeforeRecording(let msg) = SecureInputPolicy.decideBeforeRecording(before) {
                return .refuseToStart(msg)
            }
            state = .recording(startedAt: now)
            return .startRecording

        case (.recording, .hotkeyPressed(_, let secure)):
            return stop(stopFor(.secondPress, secure: secure))

        case (.recording, .secureInputObserved(let secure)):
            return Self.secureBlocks(secure) ? stop(.secureInput) : .none

        case (.recording, .sleepOrLock):
            return stop(.sleepOrLock)

        case (.recording(let startedAt), .tick(let now, let secure)):
            if Self.secureBlocks(secure) { return stop(.secureInput) }
            return now - startedAt >= maxSeconds ? stop(.maxDuration) : .none

        case (.recording, .captureFull(let secure)):
            return stop(stopFor(.maxDuration, secure: secure))

        case (.recording, .confirmKey(let secure)):
            return stop(stopFor(.secondPress, secure: secure))

        case (.recording, .cancelKey):
            return stop(.cancelled)

        case (.idle, _):
            return .none
        }
    }

    private func stopFor(_ reason: RecordingStopReason, secure: SecureInputPolicy.State) -> RecordingStopReason {
        Self.secureBlocks(secure) ? .secureInput : reason
    }

    private static func secureBlocks(_ secure: SecureInputPolicy.State) -> Bool {
        let during = SecureInputPolicy.State(systemSecureInputEnabled: secure.systemSecureInputEnabled,
                                             focusIsSecureTextField: secure.focusIsSecureTextField,
                                             isRecording: true)
        if case .stopRecordingAndWipe = SecureInputPolicy.decideDuringRecording(during) { return true }
        return false
    }

    private mutating func stop(_ reason: RecordingStopReason) -> Action {
        state = .idle
        return .stopRecording(reason)
    }
}
