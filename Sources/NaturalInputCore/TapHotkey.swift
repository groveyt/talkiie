public enum TapKey: String, CaseIterable, Sendable {
    case none
    case fn
    case control
    case option
    case command

    public var label: String {
        switch self {
        case .none: return "不使用"
        case .fn: return "fn（🌐）"
        case .control: return "⌃ Control"
        case .option: return "⌥ Option"
        case .command: return "⌘ Command"
        }
    }
}

public enum TapHotkey: String, CaseIterable, Sendable {
    case off
    case fn
    case doubleFn
    case singleControl
    case doubleControl
    case singleOption
    case doubleOption
    case singleCommand
    case doubleCommand

    public static let defaultsKey = "tapHotkey"
    public static let legacyFnDefaultsKey = "fnHotkeyEnabled"

    public init(key: TapKey, count: Int) {
        switch (key, count) {
        case (.none, _): self = .off
        case (.fn, 1): self = .fn
        case (.fn, 2): self = .doubleFn
        case (.control, 1): self = .singleControl
        case (.control, 2): self = .doubleControl
        case (.option, 1): self = .singleOption
        case (.option, 2): self = .doubleOption
        case (.command, 1): self = .singleCommand
        case (.command, 2): self = .doubleCommand
        default: self = .off
        }
    }

    public static func resolve(stored: String?, legacyFnEnabled: Bool) -> TapHotkey {
        if let stored { return TapHotkey(rawValue: stored) ?? .off }
        return legacyFnEnabled ? .fn : .off
    }

    public static func initialChoice(stored: String?, legacyFnEnabled: Bool, alreadyConsented: Bool) -> TapHotkey {
        if stored != nil || legacyFnEnabled { return resolve(stored: stored, legacyFnEnabled: legacyFnEnabled) }
        return alreadyConsented ? .off : .doubleControl
    }

    public func startPhrase(hotkey: String) -> String {
        guard let phrase = menuPhrase else { return hotkey }
        return "\(hotkey)（或\(phrase.trimmingCharacters(in: .whitespaces))）"
    }

    public var key: TapKey {
        switch self {
        case .off: return .none
        case .fn, .doubleFn: return .fn
        case .singleControl, .doubleControl: return .control
        case .singleOption, .doubleOption: return .option
        case .singleCommand, .doubleCommand: return .command
        }
    }

    public var count: Int {
        switch self {
        case .off, .fn, .singleControl, .singleOption, .singleCommand: return 1
        case .doubleFn, .doubleControl, .doubleOption, .doubleCommand: return 2
        }
    }

    public var label: String {
        switch self {
        case .off: return "不使用"
        case .fn: return "按一下 fn（🌐）"
        case .doubleFn: return "按兩下 fn（🌐）"
        case .singleControl: return "按一下 ⌃ Control"
        case .doubleControl: return "按兩下 ⌃ Control"
        case .singleOption: return "按一下 ⌥ Option"
        case .doubleOption: return "按兩下 ⌥ Option"
        case .singleCommand: return "按一下 ⌘ Command"
        case .doubleCommand: return "按兩下 ⌘ Command"
        }
    }

    public var menuPhrase: String? {
        switch self {
        case .off: return nil
        case .fn: return " fn"
        case .doubleFn: return "按兩下 fn"
        case .singleControl: return "按一下 ⌃"
        case .doubleControl: return "按兩下 ⌃"
        case .singleOption: return "按一下 ⌥"
        case .doubleOption: return "按兩下 ⌥"
        case .singleCommand: return "按一下 ⌘"
        case .doubleCommand: return "按兩下 ⌘"
        }
    }

    public var needsInputMonitoring: Bool { key == .fn }

    public var isDoubleTap: Bool { count == 2 }
}

public struct DoubleTapDetector: Sendable {
    public static let maxGapSeconds: Double = 0.4

    private var single = FnTapDetector()
    private var firstTapAt: Double?

    public init() {}

    public func isArmed(at now: Double) -> Bool {
        if single.isFnHeld { return true }
        guard let first = firstTapAt else { return false }
        return now - first <= Self.maxGapSeconds
    }

    public mutating func handle(_ input: FnTapDetector.Input) -> Bool {
        switch input {
        case .otherInput:
            if single.isFnHeld {
                _ = single.handle(input)
            } else {
                firstTapAt = nil
            }
            return false
        case .modifiers(let target, let others, let at):
            if !single.isFnHeld {
                if target, let first = firstTapAt, at - first > Self.maxGapSeconds { firstTapAt = nil }
                if others { firstTapAt = nil }
            }
            guard single.handle(input) else { return false }
            if firstTapAt != nil {
                firstTapAt = nil
                return true
            }
            firstTapAt = at
            return false
        }
    }
}
