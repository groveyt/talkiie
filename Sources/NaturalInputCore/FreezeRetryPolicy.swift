public enum FreezeRetryPolicy {
    public static let maxRetries = 4

    public static func shouldRetry(_ initial: FocusSnapshot) -> Bool {
        initial.editability == .notEditable && (initial.role == "AXWebArea" || initial.role == "AXGroup")
    }

    public enum Step: Equatable, Sendable {
        case acceptAndStop
        case acceptAndContinue
        case rejectKeepInitial
    }

    public static func evaluate(initial: FocusSnapshot, next: FocusSnapshot, nextIsWithinInitial: Bool) -> Step {
        guard next.pid == initial.pid, nextIsWithinInitial else { return .rejectKeepInitial }
        return next.editability == .notEditable ? .acceptAndContinue : .acceptAndStop
    }
}
