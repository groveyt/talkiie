import Foundation

public enum WrittenStyleKeepWords {
    public static let defaultsKey = "writtenStyleKeepWords"
    public static let maxWords = 100
    public static let maxWordLength = 8
    public static let maxOffered = 8

    public static func words(fromDefaults value: Any?) -> [String] {
        normalized((value as? [String]) ?? [])
    }

    static func normalized(_ words: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for w in words {
            let t = w.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValid(t), seen.insert(t).inserted else { continue }
            out.append(t)
        }
        return Array(out.suffix(maxWords))
    }

    static func isValid(_ w: String) -> Bool {
        !w.isEmpty && w.count <= maxWordLength && !w.contains(where: { $0.isWhitespace })
            && w.contains(where: RewriteGuard.isContent)
    }

    public static func deletedWords(original: String, rewritten: String) -> [String] {
        let a = original.filter { !$0.isWhitespace }.map { $0 }
        let b = rewritten.filter { !$0.isWhitespace }.map { $0 }
        guard !a.isEmpty, let ops = PunctuationGuard.align(a, b, maxD: a.count + b.count) else { return [] }
        var runs: [String] = []
        var cur = ""
        func flush() { if !cur.isEmpty { runs.append(cur); cur = "" } }
        for op in ops {
            switch op {
            case .delete(let i):
                if RewriteGuard.isContent(a[i]) { cur.append(a[i]) } else { flush() }
            case .equal, .insert:
                flush()
            }
        }
        flush()
        var seen = Set<String>()
        return Array(runs.filter { $0.count <= maxWordLength && seen.insert($0).inserted }.prefix(maxOffered))
    }

    public static func adding(marked: Set<String>, offered: [String], to list: [String]) -> [String] {
        let chosen = offered.filter { marked.contains($0) }
        guard !chosen.isEmpty else { return normalized(list) }
        return normalized(list.filter { !chosen.contains($0) } + chosen)
    }

    public static func removing(_ word: String, from list: [String]) -> [String] {
        normalized(list.filter { $0 != word })
    }
}

public struct RewriteRevertRecord: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let kindValue = "rewriteReverted"

    public let schemaVersion: Int
    public let capturedAt: Date
    public let kind: String
    public let mode: String
    public let original: String
    public let rewritten: String

    public init(capturedAt: Date, mode: WrittenStyleMode, original: String, rewritten: String) {
        self.schemaVersion = Self.currentSchemaVersion
        self.capturedAt = capturedAt
        self.kind = Self.kindValue
        self.mode = mode.rawValue
        self.original = original
        self.rewritten = rewritten
    }

    public func jsonLine() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        var data = try e.encode(self)
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) -> RewriteRevertRecord? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let r = try? d.decode(RewriteRevertRecord.self, from: line), r.kind == kindValue else { return nil }
        return r
    }
}
