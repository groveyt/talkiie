#if os(macOS)
import Carbon.HIToolbox

public enum StopTrigger: Equatable, Sendable, RawRepresentable {
    case anyKey
    case key(TapKey, count: Int)

    public static let defaultsKey = "stopTrigger"
    public static let defaultValue = StopTrigger.anyKey

    public init?(rawValue: String) {
        if rawValue == "anyKey" { self = .anyKey; return }
        let parts = rawValue.split(separator: ":").map(String.init)
        guard parts.count == 3, parts[0] == "key",
              let key = TapKey(rawValue: parts[1]), key != .none,
              let count = Int(parts[2]), count == 1 || count == 2
        else { return nil }
        self = .key(key, count: count)
    }

    public var rawValue: String {
        switch self {
        case .anyKey: return "anyKey"
        case .key(let key, let count): return "key:\(key.rawValue):\(count)"
        }
    }

    public static func resolve(stored: String?) -> StopTrigger {
        guard let stored, let value = StopTrigger(rawValue: stored) else { return .anyKey }
        return value
    }

    public var needsInputMonitoring: Bool {
        if case .key(.fn, _) = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .anyKey: return "任意鍵（預設）"
        case .key: return "指定的鍵"
        }
    }

    public var menuPhrase: String {
        switch self {
        case .anyKey: return "按任意鍵"
        case .key(let key, let count):
            let symbol: String
            switch key {
            case .fn: symbol = "fn"
            case .control: symbol = "⌃"
            case .option: symbol = "⌥"
            case .command: symbol = "⌘"
            case .none: symbol = ""
            }
            return count == 2 ? "按兩下 \(symbol)" : "按\(symbol)"
        }
    }
}

public enum AnyKeyStopSet {
    public static let keyCodes: [UInt32] = {
        var codes: [UInt32] = [
            UInt32(kVK_ANSI_A), UInt32(kVK_ANSI_B), UInt32(kVK_ANSI_C), UInt32(kVK_ANSI_D),
            UInt32(kVK_ANSI_E), UInt32(kVK_ANSI_F), UInt32(kVK_ANSI_G), UInt32(kVK_ANSI_H),
            UInt32(kVK_ANSI_I), UInt32(kVK_ANSI_J), UInt32(kVK_ANSI_K), UInt32(kVK_ANSI_L),
            UInt32(kVK_ANSI_M), UInt32(kVK_ANSI_N), UInt32(kVK_ANSI_O), UInt32(kVK_ANSI_P),
            UInt32(kVK_ANSI_Q), UInt32(kVK_ANSI_R), UInt32(kVK_ANSI_S), UInt32(kVK_ANSI_T),
            UInt32(kVK_ANSI_U), UInt32(kVK_ANSI_V), UInt32(kVK_ANSI_W), UInt32(kVK_ANSI_X),
            UInt32(kVK_ANSI_Y), UInt32(kVK_ANSI_Z),
            UInt32(kVK_ANSI_0), UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6), UInt32(kVK_ANSI_7),
            UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
            UInt32(kVK_Tab), UInt32(kVK_Delete), UInt32(kVK_ForwardDelete),
            UInt32(kVK_LeftArrow), UInt32(kVK_RightArrow), UInt32(kVK_UpArrow), UInt32(kVK_DownArrow),
            UInt32(kVK_ANSI_Minus), UInt32(kVK_ANSI_Equal), UInt32(kVK_ANSI_LeftBracket),
            UInt32(kVK_ANSI_RightBracket), UInt32(kVK_ANSI_Backslash), UInt32(kVK_ANSI_Semicolon),
            UInt32(kVK_ANSI_Quote), UInt32(kVK_ANSI_Comma), UInt32(kVK_ANSI_Period),
            UInt32(kVK_ANSI_Slash), UInt32(kVK_ANSI_Grave),
            UInt32(kVK_F1), UInt32(kVK_F2), UInt32(kVK_F3), UInt32(kVK_F4), UInt32(kVK_F5),
            UInt32(kVK_F6), UInt32(kVK_F7), UInt32(kVK_F8), UInt32(kVK_F9), UInt32(kVK_F10),
            UInt32(kVK_F11), UInt32(kVK_F12),
        ]
        codes.removeAll { $0 == UInt32(kVK_Space) || $0 == UInt32(kVK_Return) || $0 == UInt32(kVK_Escape) }
        return codes
    }()

    public static let shiftedKeyCodes: [UInt32] = keyCodes + [UInt32(kVK_Space), UInt32(kVK_Return)]
}

public struct ModifierTapStop: Sendable {
    public enum Modifier: Hashable, Sendable, CaseIterable { case shift, control, option, command }

    public let watched: Set<Modifier>
    private var target: Modifier?
    private var detector = FnTapDetector()

    public init(excluding startKey: TapKey) {
        var all = Set(Modifier.allCases)
        switch startKey {
        case .control: all.remove(.control)
        case .option: all.remove(.option)
        case .command: all.remove(.command)
        case .none, .fn: break
        }
        watched = all
    }

    public mutating func handle(held: Set<Modifier>, fnHeld: Bool, at: Double) -> Bool {
        if target == nil {
            guard held.count == 1, !fnHeld, let only = held.first, watched.contains(only) else { return false }
            target = only
        }
        guard let t = target else { return false }
        let others = fnHeld || !held.subtracting([t]).isEmpty
        let fired = detector.handle(.modifiers(fn: held.contains(t), others: others, at: at))
        if !detector.isFnHeld { target = nil }
        return fired
    }

    public mutating func otherInput() { _ = detector.handle(.otherInput) }
}
#endif
