#if os(macOS)
import Carbon.HIToolbox

public enum RecordingKey: Hashable, Sendable {
    case space
    case returnKey
    case escape
    case other(UInt32)
    case otherShifted(UInt32)

    public enum Intent: Equatable, Sendable {
        case confirm
        case cancel
    }

    public var keyCode: UInt32 {
        switch self {
        case .space: return UInt32(kVK_Space)
        case .returnKey: return UInt32(kVK_Return)
        case .escape: return UInt32(kVK_Escape)
        case .other(let code), .otherShifted(let code): return code
        }
    }

    public var modifiers: UInt32 {
        if case .otherShifted = self { return UInt32(shiftKey) }
        return 0
    }

    public var intent: Intent {
        switch self {
        case .space, .returnKey, .other, .otherShifted: return .confirm
        case .escape: return .cancel
        }
    }

    public static let anyKeyIDBase: UInt32 = 200
    public static let anyShiftedKeyIDBase: UInt32 = 400
    public var hotKeyID: UInt32 {
        switch self {
        case .space: return 11
        case .returnKey: return 12
        case .escape: return 13
        case .other(let code): return Self.anyKeyIDBase + code
        case .otherShifted(let code): return Self.anyShiftedKeyIDBase + code
        }
    }

    public var label: String {
        switch self {
        case .space: return "Space"
        case .returnKey: return "Return"
        case .escape: return "Esc"
        case .other, .otherShifted: return "其他鍵"
        }
    }

    public static let allCases: [RecordingKey] = [.space, .returnKey, .escape]

    public static let mainHotKeyID: UInt32 = 1

    public static func from(hotKeyID: UInt32) -> RecordingKey? {
        if hotKeyID >= anyShiftedKeyIDBase { return .otherShifted(hotKeyID - anyShiftedKeyIDBase) }
        if hotKeyID >= anyKeyIDBase { return .other(hotKeyID - anyKeyIDBase) }
        return allCases.first { $0.hotKeyID == hotKeyID }
    }

    public func policyEvent(secure: SecureInputPolicy.State) -> HotkeyPolicy.Event {
        switch intent {
        case .confirm: return .confirmKey(secure: secure)
        case .cancel: return .cancelKey
        }
    }
}
#endif
