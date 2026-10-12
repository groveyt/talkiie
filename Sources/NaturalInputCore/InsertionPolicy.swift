import Foundation

public enum InsertionPolicy {

    public struct State: Equatable, Sendable {
        public let accessibilityTrusted: Bool
        public let systemSecureInputEnabled: Bool
        public let focus: FocusSnapshot?
        public let frozenTarget: FrozenTarget?

        public init(accessibilityTrusted: Bool, systemSecureInputEnabled: Bool,
                    focus: FocusSnapshot?, frozenTarget: FrozenTarget?) {
            self.accessibilityTrusted = accessibilityTrusted
            self.systemSecureInputEnabled = systemSecureInputEnabled
            self.focus = focus
            self.frozenTarget = frozenTarget
        }
    }

    public enum Refusal: Equatable, Sendable, CaseIterable {
        case accessibilityNotTrusted
        case noFocus
        case notEditable
        case passwordField
        case systemSecureInput
        case composing
        case targetAppChanged
        case targetElementChanged

        public var message: String {
            switch self {
            case .accessibilityNotTrusted:
                return "尚未開啟「輔助使用」權限，無法把文字插入游標處"
            case .noFocus:
                return "找不到輸入游標，請先點一下要輸入的地方"
            case .notEditable:
                return "目前的焦點不是可輸入文字的欄位"
            case .passwordField:
                return SecureInputPolicy.Message.passwordField.text
            case .systemSecureInput:
                return SecureInputPolicy.Message.systemSecureInput.text
            case .composing:
                return "輸入法正在組字，請先完成或取消組字再插入"
            case .targetAppChanged:
                return "你已切換到其他 app，為避免打錯地方，這次沒有插入"
            case .targetElementChanged:
                return "焦點已移到同一個 app 的其他欄位，為避免打錯地方，這次沒有插入"
            }
        }
    }

    public enum Decision: Equatable, Sendable {
        case insert
        case refuse(Refusal)
    }

    public enum TargetRule: Equatable, Sendable {
        case currentFocus
        case frozenTargetOnly
    }

    public static let targetRule: TargetRule = .currentFocus

    public enum Resolution: Equatable, Sendable {
        case insert(into: FrozenTarget)
        case refuse(Refusal)
    }

    public static func decide(_ s: State, rule: TargetRule = targetRule) -> Decision {
        switch resolve(s, rule: rule) {
        case .insert: return .insert
        case .refuse(let reason): return .refuse(reason)
        }
    }

    public static func resolve(_ s: State, rule: TargetRule = targetRule) -> Resolution {
        guard s.accessibilityTrusted else { return .refuse(.accessibilityNotTrusted) }

        let secure = SecureInputPolicy.decideBeforeInsertion(.init(
            systemSecureInputEnabled: s.systemSecureInputEnabled,
            focusIsSecureTextField: s.focus?.isSecureField ?? false,
            isRecording: false))
        switch secure.message {
        case .passwordField?: return .refuse(.passwordField)
        case .systemSecureInput?: return .refuse(.systemSecureInput)
        case nil: break
        }

        guard let focus = s.focus else { return .refuse(.noFocus) }
        if rule == .frozenTargetOnly {
            guard let frozen = s.frozenTarget else { return .refuse(.noFocus) }
            guard focus.pid == frozen.pid, focus.bundleID == frozen.bundleID else {
                return .refuse(.targetAppChanged)
            }
            guard focus.element == frozen.element else { return .refuse(.targetElementChanged) }
        }
        guard focus.editability != .notEditable else { return .refuse(.notEditable) }
        guard focus.markedText != .composing else { return .refuse(.composing) }
        return .insert(into: FrozenTarget(focus))
    }
}
