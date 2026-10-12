import Foundation

public enum PersonalDictionaryExchange {
    public static let format = "talkiie-dictionary"
    public static let schemaVersion = 1
    public static let suggestedFileName = "Talkiie 詞庫.json"
    public static let fileExtension = "talkiiedict"
    public static let airDropFileName = "Talkiie 詞庫.\(fileExtension)"
    public static let maxBytes = 1_000_000
    public static let maxEntries = 2_000
    public static let maxFieldCharacters = 100

    public enum ImportError: Error, Equatable, Sendable {
        case tooLarge
        case notDictionary
        case newerVersion(Int)
        case unsupportedVersion(Int)
        case tooManyEntries(Int)

        public var message: String {
            switch self {
            case .tooLarge:
                return "這個檔太大（超過 1 MB），不是 Talkiie 的詞庫檔。"
            case .notDictionary:
                return "這不是 Talkiie 的詞庫檔（請選 Talkiie 匯出的 .json 或 .talkiiedict 檔）。"
            case .newerVersion(let v):
                return "這個詞庫檔是比較新的 Talkiie 匯出的（第 \(v) 版格式），請先更新 Talkiie 再匯入。"
            case .unsupportedVersion(let v):
                return "看不懂這個詞庫檔的格式（第 \(v) 版）。"
            case .tooManyEntries(let n):
                return "這個詞庫檔有 \(n) 條，超過 \(maxEntries) 條的上限，沒有匯入。"
            }
        }
    }

    public struct MergeResult: Equatable, Sendable {
        public var entries: [PersonalDictionary.Entry]
        public var added: Int
        public var updated: Int
        public var skipped: Int
        public var removed: Int = 0
        public var changesSomething: Bool { added + updated + removed > 0 }
    }

    public static func export(_ entries: [PersonalDictionary.Entry]) -> Data {
        let file = File(format: format, schemaVersion: schemaVersion,
                        entries: entries.filter(PersonalDictionary.isUsable).map(Row.init))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(file)) ?? Data("{\"entries\":[],\"format\":\"\(format)\",\"schemaVersion\":\(schemaVersion)}".utf8)
    }

    public static func readImportFile(atPath path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: maxBytes + 1) ?? Data()
    }

    public static func decode(_ data: Data) -> Result<[PersonalDictionary.Entry], ImportError> {
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let top = object as? [String: Any],
              top["format"] as? String == format else { return .failure(.notDictionary) }
        guard let number = top["schemaVersion"] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let version = top["schemaVersion"] as? Int else { return .failure(.notDictionary) }
        if version > schemaVersion { return .failure(.newerVersion(version)) }
        if version != schemaVersion { return .failure(.unsupportedVersion(version)) }
        guard let rows = top["entries"] as? [Any] else { return .failure(.notDictionary) }
        guard rows.count <= maxEntries else { return .failure(.tooManyEntries(rows.count)) }
        var out: [PersonalDictionary.Entry] = []
        for item in rows {
            guard let row = item as? [String: Any], let replacement = row["replacement"] as? String else {
                out.append(PersonalDictionary.Entry(heard: "", replacement: "", origin: .manual, promptOnly: true))
                continue
            }
            let heard = row["heard"] as? String ?? ""
            let origin = (row["origin"] as? String).flatMap(PersonalDictionary.Entry.Origin.init(rawValue:)) ?? .manual
            let promptOnly = (row["promptOnly"] as? Bool ?? false) || PersonalDictionary.trimmed(heard).isEmpty
            out.append(PersonalDictionary.Entry(heard: heard, replacement: replacement, origin: origin, promptOnly: promptOnly))
        }
        return .success(out)
    }

    public static func isImportable(_ e: PersonalDictionary.Entry) -> Bool {
        PersonalDictionary.isUsable(e) && e.heard.count <= maxFieldCharacters && e.replacement.count <= maxFieldCharacters
    }

    public static func merge(_ imported: [PersonalDictionary.Entry], into existing: [PersonalDictionary.Entry]) -> MergeResult {
        var skipped = 0
        var lastIndex: [String: Int] = [:]
        for (i, e) in imported.enumerated() where isImportable(e) {
            lastIndex[identity(e)] = i
        }
        var next = existing
        var added = 0, updated = 0
        for (i, raw) in imported.enumerated() {
            guard isImportable(raw), lastIndex[identity(raw)] == i else { skipped += 1; continue }
            let e = cleaned(raw)
            if let k = next.firstIndex(where: { identity($0) == identity(e) }) {
                if sameContent(next[k], e) { skipped += 1; continue }
                next.remove(at: k)
                updated += 1
            } else {
                added += 1
            }
            next.append(e)
        }
        var learnedCount = next.filter { $0.origin == .learned }.count
        var removed = 0
        while learnedCount > PersonalDictionary.maxLearnedEntries, let k = next.firstIndex(where: { $0.origin == .learned }) {
            next.remove(at: k)
            learnedCount -= 1
            removed += 1
        }
        return MergeResult(entries: next, added: added, updated: updated, skipped: skipped, removed: removed)
    }

    static func identity(_ e: PersonalDictionary.Entry) -> String {
        PersonalDictionary.isTermOnly(e)
            ? "t:" + PersonalDictionary.normalizedKey(e.replacement)
            : "h:" + PersonalDictionary.normalizedKey(e.heard)
    }

    static func sameContent(_ a: PersonalDictionary.Entry, _ b: PersonalDictionary.Entry) -> Bool {
        let a = cleaned(a), b = cleaned(b)
        return PersonalDictionary.normalizedKey(a.heard) == PersonalDictionary.normalizedKey(b.heard)
            && a.replacement == b.replacement && a.origin == b.origin && a.promptOnly == b.promptOnly
    }

    static func cleaned(_ e: PersonalDictionary.Entry) -> PersonalDictionary.Entry {
        let heard = PersonalDictionary.trimmed(e.heard)
        return PersonalDictionary.Entry(heard: heard, replacement: PersonalDictionary.trimmed(e.replacement),
                                        origin: e.origin, promptOnly: e.promptOnly || heard.isEmpty)
    }

    public static func adding(heard: String, replacement: String, replacing old: PersonalDictionary.Entry? = nil,
                              to entries: [PersonalDictionary.Entry]) -> Result<[PersonalDictionary.Entry], PersonalDictionary.Problem> {
        var base = entries
        if let old, let k = base.firstIndex(of: old) { base.remove(at: k) }
        if PersonalDictionary.trimmed(heard).isEmpty {
            let terms = PersonalDictionary.terms(from: replacement)
            guard !terms.isEmpty else { return .failure(.emptyReplacement) }
            if let p = terms.lazy.compactMap({ t in t.replacement.count > maxFieldCharacters ? PersonalDictionary.Problem.tooLong : nil }).first {
                return .failure(p)
            }
            return .success(merge(terms, into: base).entries)
        }
        if let p = PersonalDictionary.problem(heard: heard, replacement: replacement) { return .failure(p) }
        let keepPromptOnly = old.map {
            $0.promptOnly && !PersonalDictionary.isTermOnly($0)
                && PersonalDictionary.normalizedKey($0.heard) == PersonalDictionary.normalizedKey(heard)
        } ?? false
        let entry = PersonalDictionary.Entry(heard: PersonalDictionary.trimmed(heard), replacement: PersonalDictionary.trimmed(replacement),
                                             promptOnly: keepPromptOnly)
        guard entry.heard.count <= maxFieldCharacters, entry.replacement.count <= maxFieldCharacters else { return .failure(.tooLong) }
        let key = identity(entry)
        var next = base.filter { identity($0) != key }
        next.append(entry)
        return .success(next)
    }

    private struct File: Encodable {
        let format: String
        let schemaVersion: Int
        let entries: [Row]
    }

    private struct Row: Encodable {
        let heard: String
        let replacement: String
        let origin: String
        let promptOnly: Bool
        init(_ e: PersonalDictionary.Entry) {
            let c = PersonalDictionaryExchange.cleaned(e)
            heard = c.heard
            replacement = c.replacement
            origin = c.origin.rawValue
            promptOnly = c.promptOnly
        }
    }
}
