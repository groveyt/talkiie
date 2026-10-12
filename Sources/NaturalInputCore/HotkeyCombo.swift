#if os(macOS)
import Carbon.HIToolbox
import Foundation

public struct HotkeyCombo: Codable, Equatable, Hashable, Sendable {
    public struct Mods: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Mods(rawValue: 1)
        public static let option = Mods(rawValue: 2)
        public static let shift = Mods(rawValue: 4)
        public static let command = Mods(rawValue: 8)
    }

    public let keyCode: UInt32
    public let mods: Mods

    public init(keyCode: UInt32, mods: Mods) {
        self.keyCode = keyCode
        self.mods = mods
    }

    public static let standard = HotkeyCombo(keyCode: UInt32(kVK_ANSI_J), mods: [.option])

    public enum Problem: Equatable, Sendable {
        case recordingKey
        case systemShortcut(String)
        case unsupportedKey
        case needsModifier
        case editCaptureKey
        case commandOnly
        case controlOnly

        public var message: String {
            switch self {
            case .recordingKey:
                return "Space、Return、Esc 在錄音中用來結束或取消，不能當開始的熱鍵。"
            case .systemShortcut(let combo):
                return "\(combo) 是系統或常用 app 的快捷鍵，請換一個。"
            case .unsupportedKey:
                return "請用字母或數字鍵。"
            case .needsModifier:
                return "請同時按住 ⌥、⌃ 或 ⌘ 其中之一（只按 ⇧ 會打出大寫字）。"
            case .editCaptureKey:
                return "\(EditCaptureKey.label) 是「收集我的修改」用的，請換一個。"
            case .commandOnly:
                return "⌘ 加一個字母幾乎都是 app 的快捷鍵（拷貝、貼上、結束…），請再按住 ⌥ 或 ⌃。"
            case .controlOnly:
                return "⌃ 加一個字母在文字欄位裡是移動游標的鍵，請再按住 ⌥ 或 ⌘。"
            }
        }
    }

    public var problem: Problem? {
        if let name = Self.systemShortcutName(self) { return .systemShortcut(name) }
        if Self.recordingKeyCodes.contains(keyCode) { return .recordingKey }
        if Self.keyNames[keyCode] == nil { return .unsupportedKey }
        let core = mods.intersection([.command, .option, .control])
        if core.isEmpty { return .needsModifier }
        if keyCode == EditCaptureKey.keyCode && carbonModifiers == EditCaptureKey.modifiers { return .editCaptureKey }
        if core == .command { return .commandOnly }
        if core == .control && !mods.contains(.shift) { return .controlOnly }
        return nil
    }

    public var key: String? { Self.keyNames[keyCode] ?? Self.otherKeyNames[keyCode] }

    public var label: String {
        var out = ""
        if mods.contains(.control) { out += "⌃" }
        if mods.contains(.option) { out += "⌥" }
        if mods.contains(.shift) { out += "⇧" }
        if mods.contains(.command) { out += "⌘" }
        return out + (key ?? "?")
    }

    public var spoken: String {
        var out: [String] = []
        if mods.contains(.control) { out.append("Control") }
        if mods.contains(.option) { out.append("Option") }
        if mods.contains(.shift) { out.append("Shift") }
        if mods.contains(.command) { out.append("Command") }
        out.append(key ?? "?")
        return out.joined(separator: " ")
    }

    public var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if mods.contains(.command) { m |= UInt32(cmdKey) }
        if mods.contains(.shift) { m |= UInt32(shiftKey) }
        if mods.contains(.option) { m |= UInt32(optionKey) }
        if mods.contains(.control) { m |= UInt32(controlKey) }
        return m
    }

    public static let defaultsKey = "mainHotkey"

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decode(_ data: Data?) -> HotkeyCombo {
        guard let data, let c = try? JSONDecoder().decode(HotkeyCombo.self, from: data), c.problem == nil else {
            return standard
        }
        return c
    }

    public static func load(_ d: UserDefaults = .standard) -> HotkeyCombo {
        decode(d.data(forKey: defaultsKey))
    }

    public func save(_ d: UserDefaults = .standard) {
        if self == Self.standard {
            d.removeObject(forKey: Self.defaultsKey)
        } else if let data = encoded() {
            d.set(data, forKey: Self.defaultsKey)
        }
    }

    static let recordingKeyCodes: Set<UInt32> = Set(RecordingKey.allCases.map(\.keyCode) + [UInt32(kVK_ANSI_KeypadEnter)])

    static func systemShortcutName(_ c: HotkeyCombo) -> String? {
        let m = c.mods
        let k = c.keyCode
        let list: [(UInt32, Mods)] = [
            (UInt32(kVK_Tab), [.command]), (UInt32(kVK_Tab), [.command, .shift]),
            (UInt32(kVK_ANSI_Grave), [.command]),
            (UInt32(kVK_Space), [.command]), (UInt32(kVK_Space), [.command, .option]),
            (UInt32(kVK_Space), [.control]), (UInt32(kVK_Space), [.control, .option]),
            (UInt32(kVK_Space), [.control, .command]),
            (UInt32(kVK_ANSI_Q), [.command]), (UInt32(kVK_ANSI_W), [.command]),
            (UInt32(kVK_ANSI_H), [.command]), (UInt32(kVK_ANSI_M), [.command]),
            (UInt32(kVK_ANSI_Q), [.control, .command]),
            (UInt32(kVK_ANSI_F), [.control, .command]),
            (UInt32(kVK_ANSI_D), [.option, .command]),
            (UInt32(kVK_Escape), [.option, .command]),
            (UInt32(kVK_ANSI_3), [.shift, .command]), (UInt32(kVK_ANSI_4), [.shift, .command]),
            (UInt32(kVK_ANSI_5), [.shift, .command]),
        ]
        if list.contains(where: { $0.0 == k && $0.1 == m }) { return c.label }
        if m == [.control], let name = keyNames[k], Int(name) != nil { return c.label }
        return nil
    }

    public static let keyNames: [UInt32: String] = [
        0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F", 0x05: "G",
        0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L", 0x2E: "M", 0x2D: "N",
        0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R", 0x01: "S", 0x11: "T", 0x20: "U",
        0x09: "V", 0x0D: "W", 0x07: "X", 0x10: "Y", 0x06: "Z",
        0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5", 0x16: "6",
        0x1A: "7", 0x1C: "8", 0x19: "9",
    ]

    static let otherKeyNames: [UInt32: String] = [
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return", UInt32(kVK_Escape): "Esc",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_ANSI_Grave): "`", UInt32(kVK_ANSI_KeypadEnter): "Enter",
    ]
}
#endif
