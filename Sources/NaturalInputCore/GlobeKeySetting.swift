public enum GlobeKeySetting: Equatable, Sendable {
    case doNothing
    case changeInputSource
    case emoji
    case dictation
    case unknown

    public init(rawValue: Int?) {
        switch rawValue {
        case 0: self = .doNothing
        case 1: self = .changeInputSource
        case 2: self = .emoji
        case 3: self = .dictation
        default: self = .unknown
        }
    }

    public var conflictsWithFnHotkey: Bool { self != .doNothing }

    public var menuWarning: String? {
        switch self {
        case .doNothing: return nil
        case .changeInputSource: return "⚠️ 🌐 目前設為「切換輸入法」，按 fn 會同時切換輸入法"
        case .emoji: return "⚠️ 🌐 目前設為「顯示表情符號」，按 fn 會同時跳出表情符號"
        case .dictation: return "⚠️ 🌐 目前設為「開始聽寫」，按 fn 會同時開啟系統聽寫"
        case .unknown: return "⚠️ 無法確認 🌐 的設定，請確認「按下 🌐 鍵時」是「不執行任何動作」"
        }
    }
}
