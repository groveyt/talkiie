import Foundation

public enum DeliveryFallback {

    public enum Presentation: Equatable, Sendable {
        case none
        case textPanel
        case notice
    }

    public static func presentation(refusal: InsertionPolicy.Refusal) -> Presentation {
        switch refusal {
        case .noFocus, .notEditable:
            return .textPanel
        case .targetAppChanged, .targetElementChanged:
            return .textPanel
        case .accessibilityNotTrusted, .passwordField, .systemSecureInput, .composing:
            return .notice
        }
    }

    public static func presentation(abortedAfter sentUnits: Int, reason: InsertionAbortReason) -> Presentation {
        guard sentUnits == 0 else { return .notice }
        switch reason {
        case .focusAppChanged, .focusElementChanged:
            return .textPanel
        case .secureInput, .cursorMoved, .postFailed:
            return .notice
        }
    }
}

public enum FallbackPaste {

    public enum Refusal: Equatable, Sendable, CaseIterable {
        case accessibilityNotTrusted
        case systemSecureInput
        case passwordField
        case composing
        case noFocus
        case ownWindow
        case insertionInProgress
        case focusChanged

        public var message: String {
            switch self {
            case .accessibilityNotTrusted:
                return InsertionPolicy.Refusal.accessibilityNotTrusted.message
            case .systemSecureInput:
                return InsertionPolicy.Refusal.systemSecureInput.message
            case .passwordField:
                return InsertionPolicy.Refusal.passwordField.message
            case .composing:
                return InsertionPolicy.Refusal.composing.message
            case .noFocus:
                return "還是找不到輸入游標：請先點一下要貼上的地方，再按「貼上」"
            case .ownWindow:
                return "游標在 Talkiie 自己的視窗裡：請先點一下要貼上的地方，再按「貼上」"
            case .insertionInProgress:
                return "上一段還在插入中，請稍候再按「貼上」"
            case .focusChanged:
                return "按下「貼上」之後游標換到了別的 app，為避免貼錯地方，這次沒有貼上。文字還在這裡"
            }
        }
    }

    public enum Decision: Equatable, Sendable {
        case paste(pid: Int32)
        case refuse(Refusal)
    }

    public static func confirm(first: Decision, recheck: Decision) -> Decision {
        guard case .paste(let pid) = first else { return first }
        switch recheck {
        case .refuse: return recheck
        case .paste(let now): return now == pid ? .paste(pid: pid) : .refuse(.focusChanged)
        }
    }

    public static func decide(accessibilityTrusted: Bool, systemSecureInputEnabled: Bool,
                              focus: FocusSnapshot?, ownPID: Int32,
                              insertionInProgress: Bool) -> Decision {
        guard accessibilityTrusted else { return .refuse(.accessibilityNotTrusted) }
        let secure = SecureInputPolicy.decideBeforeInsertion(.init(
            systemSecureInputEnabled: systemSecureInputEnabled,
            focusIsSecureTextField: focus?.isSecureField ?? false,
            isRecording: false))
        switch secure.message {
        case .passwordField?: return .refuse(.passwordField)
        case .systemSecureInput?: return .refuse(.systemSecureInput)
        case nil: break
        }
        guard !insertionInProgress else { return .refuse(.insertionInProgress) }
        guard let focus else { return .refuse(.noFocus) }
        guard focus.pid != ownPID else { return .refuse(.ownWindow) }
        guard focus.markedText != .composing else { return .refuse(.composing) }
        return .paste(pid: focus.pid)
    }
}
