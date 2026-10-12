#if os(macOS)
import Foundation

public enum StartStopSettings {
    public static let tapGroups: [[TapHotkey]] = [
        [.off],
        [.doubleControl, .doubleOption, .doubleCommand],
        [.fn, .doubleFn],
        [.singleOption, .singleControl, .singleCommand],
    ]

    public static func tapMenuLabel(_ t: TapHotkey) -> String {
        switch t {
        case .doubleControl: return t.label + "（建議）"
        case .singleOption, .singleControl, .singleCommand: return t.label + "（容易誤觸）"
        default: return t.label
        }
    }

    public static let stopGroups: [[StopTrigger]] = [
        [.anyKey],
        [TapKey.option, .control, .command, .fn].map { StopTrigger.key($0, count: 1) },
        [TapKey.option, .control, .command, .fn].map { StopTrigger.key($0, count: 2) },
    ]

    public static func stopMenuLabel(_ s: StopTrigger) -> String {
        switch s {
        case .anyKey: return "按任意鍵（預設）"
        case .key(let key, let count): return (count == 2 ? "按兩下 " : "按一下 ") + key.label
        }
    }

    public static func summary(hotkey: String, tap: TapHotkey, stop: StopTrigger) -> String {
        let start = tap.menuPhrase.map { "\($0.trimmingCharacters(in: .whitespaces)) 或 \(hotkey)" } ?? hotkey
        let phrase = stop.menuPhrase
        let gap = phrase.last.map { $0.isASCII || "⌃⌥⌘".contains($0) } ?? false ? " " : ""
        return "\(start) 開始說話；說完\(phrase)\(gap)結束，Esc 取消。"
    }
}
#endif
