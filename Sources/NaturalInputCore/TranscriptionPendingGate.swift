public enum TranscriptionPendingGate {

    public enum Decision: Equatable, Sendable {
        case proceed
        case refuse(message: String)
    }

    public static func decide(recorderState: HotkeyPolicy.State, awaitingTranscript: Bool, message: String) -> Decision {
        guard recorderState == .idle, awaitingTranscript else { return .proceed }
        return .refuse(message: message)
    }
}
