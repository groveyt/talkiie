#if os(macOS)
import Carbon.HIToolbox
import Foundation

public enum EditCaptureKey {
    public static let keyCode = UInt32(kVK_ANSI_K)
    public static let modifiers = UInt32(optionKey)
    public static let label = "⌥K"
    public static let hotKeyID: UInt32 = 21
    public static let controlHotKeyID: UInt32 = 22
    public static var hotKeyIDs: Set<UInt32> { [hotKeyID, controlHotKeyID] }
}

public enum EditCaptureShortcut: String, CaseIterable, Sendable {
    case option
    case control
    case both

    public static let defaultValue = EditCaptureShortcut.option
    public static let defaultsKey = "editCaptureShortcut"

    public init(fromDefaults raw: String?) {
        self = raw.flatMap(EditCaptureShortcut.init(rawValue:)) ?? .defaultValue
    }

    public struct Binding: Equatable, Sendable {
        public let keyCode: UInt32
        public let modifiers: UInt32
        public let hotKeyID: UInt32
    }

    public var bindings: [Binding] {
        let opt = Binding(keyCode: EditCaptureKey.keyCode, modifiers: UInt32(optionKey), hotKeyID: EditCaptureKey.hotKeyID)
        let ctl = Binding(keyCode: EditCaptureKey.keyCode, modifiers: UInt32(controlKey),
                          hotKeyID: EditCaptureKey.controlHotKeyID)
        switch self {
        case .option: return [opt]
        case .control: return [ctl]
        case .both: return [opt, ctl]
        }
    }

    public var label: String {
        switch self {
        case .option: return "⌥K"
        case .control: return "⌃K"
        case .both: return "⌥K 或 ⌃K"
        }
    }

    public var title: String {
        switch self {
        case .option: return "⌥K（option 加 K）"
        case .control: return "⌃K（control 加 K）"
        case .both: return "⌥K 與 ⌃K 都可以"
        }
    }

    public var caveat: String? {
        self == .option ? nil : "註冊期間，⌃K 在文字欄位與終端機裡的「刪到行尾」會失效。"
    }
}

public enum EditCaptureSettingsKey {
    public static let enabled = "editCaptureEnabled"
    public static let retention = "editCorrectionRetention"
}

public struct InsertionRecord: Sendable {
    public let pid: Int32
    public let element: FocusedElementIdentity
    public let textElement: FocusedElementIdentity
    public let role: String?
    public let app: KnownApp
    public let startUTF16: Int
    public let insertedText: String
    public let insertedAt: Date

    public init(pid: Int32, element: FocusedElementIdentity, textElement: FocusedElementIdentity, role: String?,
                app: KnownApp, startUTF16: Int, insertedText: String, insertedAt: Date) {
        self.pid = pid
        self.element = element
        self.textElement = textElement
        self.role = role
        self.app = app
        self.startUTF16 = startUTF16
        self.insertedText = insertedText
        self.insertedAt = insertedAt
    }

    public var insertedUTF16: Int { insertedText.utf16.count }

    public static func typedText(paragraphs: [String], separator: ParagraphSeparator) -> String {
        InsertionText.paragraphs(paragraphs).joined(separator: separator == .shiftReturn ? "\n" : " ")
    }
}

public struct ReadWindow: Equatable, Sendable {
    public static let context = 200

    public let location: Int
    public let length: Int
    public let insertionOffset: Int

    public static func around(startUTF16 start: Int, insertedUTF16 inserted: Int, fieldLength: Int?,
                              context: Int = ReadWindow.context) -> ReadWindow? {
        guard start >= 0, inserted > 0 else { return nil }
        var lower = max(0, start - context)
        var upper = start + inserted + context
        if let fieldLength {
            upper = min(upper, max(0, fieldLength))
            lower = min(lower, upper)
        }
        guard upper > lower else { return nil }
        return ReadWindow(location: lower, length: upper - lower, insertionOffset: start - lower)
    }
}

public final class ReadbackPermit: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    init() {}

    func consume() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

public enum EditCaptureGate {
    public static func press(enabled: Bool) -> ReadbackPermit? {
        enabled ? ReadbackPermit() : nil
    }
}

public enum EditCaptureRefusal: String, CaseIterable, Sendable {
    case disabled
    case disabledAfterRead
    case permitUsed
    case noInsertion
    case insertionInProgress
    case accessibilityNotTrusted
    case secureInput
    case secureField
    case focusChanged
    case tooLong
    case unreadable
    case readFailed
    case fieldTooLong
    case notFound
    case saveFailed

    public var message: String {
        switch self {
        case .disabled: return "「收集我的修改」沒有打開，沒有讀取"
        case .disabledAfterRead: return "讀完之前「收集我的修改」被關掉了：這次讀到的內容沒有存"
        case .permitUsed: return "這次按鍵已經讀過一次，沒有再讀"
        case .noInsertion: return "沒有可以收下的插入（收集打開之後、整段插完的字才算），沒有讀取"
        case .insertionInProgress: return "還在插字，沒有讀取"
        case .accessibilityNotTrusted: return "沒有輔助使用權限，沒有讀取"
        case .secureInput: return "安全輸入中（例如密碼框），沒有讀取"
        case .secureField: return "密碼欄位，沒有讀取"
        case .focusChanged: return "游標不在剛才插入的那個欄位，沒有讀取"
        case .tooLong: return "這次插入太長，沒有讀取"
        case .unreadable: return "這個 app 不支援讀這個欄位的文字，沒有收下"
        case .readFailed: return "這次讀取欄位的文字失敗，沒有收下"
        case .fieldTooLong: return "這個 app 只能整個欄位一起讀，而這個欄位太長或量不到長度，沒有讀取"
        case .notFound: return "找不到剛才插入的那段（可能刪掉或改太多），沒有收下"
        case .saveFailed: return "存檔失敗，這次沒有收下"
        }
    }
}

public struct EditCorrection: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let capturedAt: Date
    public let app: String
    public let inserted: String
    public let edited: String

    public init(capturedAt: Date, app: KnownApp, inserted: String, edited: String) {
        self.schemaVersion = Self.currentSchemaVersion
        self.capturedAt = capturedAt
        self.app = app.rawValue
        self.inserted = inserted
        self.edited = edited
    }

    public var changed: Bool { inserted != edited }

    public func jsonLine() throws -> Data {
        var data = try Self.encoder.encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) -> EditCorrection? {
        try? decoder.decode(EditCorrection.self, from: line)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

public enum EditCaptureOutcome: Equatable, Sendable {
    case captured(EditCorrection, alignedPercent: Int)
    case refused(EditCaptureRefusal)
}

public enum CorrectionRetention: String, CaseIterable, Sendable {
    case days14, days180, untilDeleted

    public static let defaultValue = CorrectionRetention.days14

    public init(fromDefaults raw: String?) {
        self = raw.flatMap(CorrectionRetention.init(rawValue:)) ?? Self.defaultValue
    }

    public var keepDays: Int? {
        switch self {
        case .days14: return 14
        case .days180: return 180
        case .untilDeleted: return nil
        }
    }

    public var title: String {
        switch self {
        case .days14: return "14 天"
        case .days180: return "180 天"
        case .untilDeleted: return "直到我刪除"
        }
    }

    public func cutoff(now: Date) -> Date? {
        keepDays.map { now.addingTimeInterval(-Double($0) * 86_400) }
    }

    public enum DayAction: Equatable, Sendable {
        case keep
        case delete
        case filter(cutoff: Date)
    }

    public func action(forFile name: String, now: Date, calendar: Calendar = CorrectionLayout.calendar()) -> DayAction {
        guard let cutoff = cutoff(now: now), let dayStart = CorrectionLayout.dayStart(fileName: name, calendar: calendar),
              let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return .keep }
        if dayEnd <= cutoff { return .delete }
        if dayStart < cutoff { return .filter(cutoff: cutoff) }
        return .keep
    }

    public static func retainedLines(_ data: Data, cutoff: Date) -> Data {
        var out = Data()
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let at = EditCorrection.decode(line: Data(line))?.capturedAt
                ?? RewriteRevertRecord.decode(line: Data(line))?.capturedAt
            guard let at, at >= cutoff else { continue }
            out.append(contentsOf: line)
            out.append(0x0A)
        }
        return out
    }
}

public enum CorrectionLayout {
    public static let folderName = "corrections"
    public static let fileExtension = "jsonl"

    public static func calendar(_ timeZone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    public static func fileName(for date: Date, calendar: Calendar = CorrectionLayout.calendar()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, fileExtension)
    }

    public static func dayStart(fileName name: String, calendar: Calendar = CorrectionLayout.calendar()) -> Date? {
        let suffix = "." + fileExtension
        guard name.hasSuffix(suffix) else { return nil }
        let parts = name.dropLast(suffix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let dc = DateComponents(year: y, month: m, day: d)
        guard let date = calendar.date(from: dc),
              calendar.dateComponents([.year, .month, .day], from: date) == dc else { return nil }
        return date
    }
}
#endif
