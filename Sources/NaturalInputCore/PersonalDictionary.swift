import Foundation

public struct PersonalDictionary: Sendable {
    public struct Entry: Codable, Equatable, Hashable, Sendable {
        public enum Origin: String, Codable, Sendable {
            case manual
            case learned
        }

        public var heard: String
        public var replacement: String
        public var origin: Origin
        public var promptOnly: Bool

        public init(heard: String, replacement: String, origin: Origin = .manual, promptOnly: Bool = false) {
            self.heard = heard
            self.replacement = replacement
            self.origin = origin
            self.promptOnly = promptOnly
        }
    }

    public enum Problem: Error, Equatable, Sendable {
        case emptyHeard
        case emptyReplacement
        case cjkTooShort
        case unchanged
        case tooLong

        public var message: String {
            switch self {
            case .emptyHeard: return "「聽成」不能是空的"
            case .emptyReplacement: return "「改成」不能是空的"
            case .cjkTooShort: return "中文至少要 2 個字，單字替換容易誤傷其他句子"
            case .unchanged: return "「聽成」和「改成」一樣"
            case .tooLong: return "太長了：一個詞最多 \(PersonalDictionaryExchange.maxFieldCharacters) 個字"
            }
        }
    }

    public struct Applied: Equatable, Sendable {
        public var text: String
        public var exact: Int
        public var fuzzy: Int
        public var spelling: Int = 0
        public var total: Int { exact + fuzzy + spelling }
    }

    public static let defaultsKey = "personalDictionary"

    public static let fuzzyDefaultsKey = "personalDictionaryFuzzy"
    public static let fuzzyDefault = true
    public static func fuzzyEnabled(fromDefaults value: Any?) -> Bool { (value as? Bool) ?? fuzzyDefault }

    public static let fuzzyThreshold = 0.65
    public static let fuzzyLengths = 2...4

    public static let empty = PersonalDictionary(entries: [])

    public let entries: [Entry]
    private let rulesByFirst: [Character: [Rule]]
    private let fuzzyTargets: [[Character]]
    private let lexicon: BopomofoLexicon?
    private let spelling: SpellingVariants

    public init(entries: [Entry], phonetic: BopomofoLexicon? = nil) {
        self.entries = entries
        var seen = Set<[Character]>()
        var rules: [Rule] = []
        var targetSeen = Set<[Character]>()
        var targets: [[Character]] = []
        for e in entries {
            guard Self.isUsable(e) else { continue }
            let target = Array(Self.normalizedKey(e.replacement))
            if Self.fuzzyLengths.contains(target.count), target.allSatisfy(Self.isHan), targetSeen.insert(target).inserted {
                targets.append(target)
            }
            if e.promptOnly { continue }
            let key = Array(Self.normalizedKey(e.heard))
            guard seen.insert(key).inserted else { continue }
            rules.append(Rule(key: key, replacement: Self.trimmed(e.replacement)))
        }
        let ordered = rules.enumerated().sorted {
            $0.element.key.count != $1.element.key.count
                ? $0.element.key.count > $1.element.key.count : $0.offset < $1.offset
        }.map(\.element)
        rulesByFirst = Dictionary(grouping: ordered, by: { $0.key[0] })
        lexicon = phonetic
        fuzzyTargets = phonetic == nil ? [] : targets.enumerated().sorted {
            $0.element.count != $1.element.count ? $0.element.count > $1.element.count : $0.offset < $1.offset
        }.map(\.element)
        spelling = SpellingVariants(terms: entries.filter { $0.origin == .manual && Self.isUsable($0) }.map { Self.trimmed($0.replacement) })
    }

    public var isEmpty: Bool { rulesByFirst.isEmpty && fuzzyTargets.isEmpty && spelling.isEmpty }

    public var hasUsableEntries: Bool {
        entries.contains(where: Self.isUsable)
    }

    public var fuzzyMatchingActive: Bool { !fuzzyTargets.isEmpty }

    public struct PromptCandidates: Equatable, Sendable {
        public var manual: [String]
        public var learned: [String]
        public var gated: Int
        public var gatedKeys: Set<String> = []
    }

    public var promptCandidates: PromptCandidates {
        var seen = Set<String>()
        var manual: [String] = []
        for e in entries where e.origin == .manual && Self.isUsable(e) {
            let term = Self.trimmed(e.replacement)
            if seen.insert(LearnedTermGate.foldedKey(term)).inserted { manual.append(term) }
        }
        let known = entries.filter(Self.isUsable).map { Self.trimmed($0.replacement) }
        var learned: [String] = []
        var gated = 0
        var gatedKeys = Set<String>()
        for e in entries.reversed() where e.origin == .learned && Self.isUsable(e) {
            let term = Self.trimmed(e.replacement)
            let key = LearnedTermGate.foldedKey(term)
            guard !seen.contains(key) else { continue }
            if LearnedTermGate.rejection(term, knownTerms: known) != nil { gated += 1; seen.insert(key); gatedKeys.insert(key); continue }
            seen.insert(key)
            learned.append(term)
        }
        return PromptCandidates(manual: manual, learned: learned, gated: gated, gatedKeys: gatedKeys)
    }

    public var promptTerms: [String] {
        let c = promptCandidates
        return c.manual + c.learned
    }

    public static func isUsable(_ e: Entry) -> Bool {
        isTermOnly(e) ? !trimmed(e.replacement).isEmpty : problem(heard: e.heard, replacement: e.replacement) == nil
    }

    public static func isTermOnly(_ e: Entry) -> Bool { e.promptOnly && trimmed(e.heard).isEmpty }

    public static func terms(from text: String) -> [Entry] {
        let separators: Set<Character> = ["、", "，", ",", "；", ";", "\n", "\r"]
        var seen = Set<String>()
        var out: [Entry] = []
        for piece in text.split(whereSeparator: { separators.contains($0) }) {
            let term = trimmed(String(piece))
            guard !term.isEmpty, seen.insert(normalizedKey(term)).inserted else { continue }
            out.append(Entry(heard: "", replacement: term, origin: .manual, promptOnly: true))
        }
        return out
    }

    public static func problem(heard: String, replacement: String) -> Problem? {
        let key = normalizedKey(heard)
        if key.isEmpty { return .emptyHeard }
        let value = trimmed(replacement)
        if value.isEmpty { return .emptyReplacement }
        if key.contains(where: isCJK), key.count < 2 { return .cjkTooShort }
        if key == normalizedKey(value) { return .unchanged }
        return nil
    }

    public func apply(_ text: String) -> (text: String, replacements: Int) {
        let r = applyReporting(text)
        return (r.text, r.total)
    }

    public func applyReporting(_ text: String, fuzzyThreshold: Double = PersonalDictionary.fuzzyThreshold) -> Applied {
        guard !isEmpty, !text.isEmpty else { return Applied(text: text, exact: 0, fuzzy: 0) }
        let base = applyRulesAndFuzzy(text, fuzzyThreshold: fuzzyThreshold)
        let (unified, spelled) = spelling.apply(base.text)
        return spelled == 0 ? base : Applied(text: unified, exact: base.exact, fuzzy: base.fuzzy, spelling: spelled)
    }

    private func applyRulesAndFuzzy(_ text: String, fuzzyThreshold: Double) -> Applied {
        let original = Array(text)
        let hant = Array(TraditionalChinese.convert(text))
        let source = hant.count == original.count ? original : hant
        var out = ""
        var exact = 0, fuzzy = 0
        var i = 0
        while i < hant.count {
            if let rule = match(in: hant, at: i) {
                out += rule.replacement
                exact += 1
                i += rule.key.count
            } else if let target = fuzzyMatch(in: hant, at: i, threshold: fuzzyThreshold) {
                out += String(target)
                fuzzy += 1
                i += target.count
            } else {
                out.append(source[i])
                i += 1
            }
        }
        return exact + fuzzy == 0 ? Applied(text: text, exact: 0, fuzzy: 0) : Applied(text: out, exact: exact, fuzzy: fuzzy)
    }

    public func apply(to segments: [TranscriptSegment]) -> (segments: [TranscriptSegment], replacements: Int) {
        let r = applyReporting(to: segments)
        return (r.segments, r.exact + r.fuzzy + r.spelling)
    }

    public func applyReporting(to segments: [TranscriptSegment], fuzzyThreshold: Double = PersonalDictionary.fuzzyThreshold)
        -> (segments: [TranscriptSegment], exact: Int, fuzzy: Int, spelling: Int) {
        guard !isEmpty else { return (segments, 0, 0, 0) }
        var exact = 0, fuzzy = 0, spelled = 0
        let out = segments.map { s -> TranscriptSegment in
            let r = applyReporting(s.text, fuzzyThreshold: fuzzyThreshold)
            exact += r.exact
            fuzzy += r.fuzzy
            spelled += r.spelling
            return TranscriptSegment(text: r.text, start: s.start, end: s.end)
        }
        return (out, exact, fuzzy, spelled)
    }

    private func match(in text: [Character], at i: Int) -> Rule? {
        guard let candidates = rulesByFirst[text[i]] else { return nil }
        for rule in candidates {
            let end = i + rule.key.count
            guard end <= text.count, text[i..<end].elementsEqual(rule.key) else { continue }
            if rule.wordStart, i > 0, Self.isWordCharacter(text[i - 1]) { continue }
            if rule.wordEnd, end < text.count, Self.isWordCharacter(text[end]) { continue }
            return rule
        }
        return nil
    }

    private func fuzzyMatch(in text: [Character], at i: Int, threshold: Double) -> [Character]? {
        guard let lexicon, !fuzzyTargets.isEmpty, Self.isHan(text[i]) else { return nil }
        var best: (target: [Character], distance: Double)?
        for target in fuzzyTargets {
            let end = i + target.count
            guard end <= text.count else { continue }
            let span = text[i..<end]
            if span.elementsEqual(target) { return nil }
            guard span.allSatisfy(Self.isHan), !lexicon.isWord(String(span)) else { continue }
            if i > 0, lexicon.isWord(String([text[i - 1], text[i]])) { continue }
            if end < text.count, lexicon.isWord(String([text[end - 1], text[end]])) { continue }
            guard let d = lexicon.distance(span, target), d <= threshold else { continue }
            if best == nil || d < best!.distance { best = (target, d) }
        }
        return best?.target
    }

    public static let maxLearnedEntries = 200
    public static func merging(learned: [Entry], into entries: [Entry]) -> (entries: [Entry], added: Int, refreshed: Int) {
        var next = entries
        var added = 0, refreshed = 0
        for entry in learned where entry.origin == .learned && problem(heard: entry.heard, replacement: entry.replacement) == nil {
            let known = next.filter { $0 != entry }.map { trimmed($0.replacement) }
            guard LearnedTermGate.rejection(entry.replacement, knownTerms: known) == nil else { continue }
            let key = normalizedKey(entry.heard)
            if let k = next.firstIndex(where: { normalizedKey($0.heard) == key }) {
                guard next[k].origin == .learned else { continue }
                next.remove(at: k)
                refreshed += 1
            } else {
                added += 1
            }
            next.append(entry)
        }
        var learnedCount = next.filter { $0.origin == .learned }.count
        while learnedCount > maxLearnedEntries, let k = next.firstIndex(where: { $0.origin == .learned }) {
            next.remove(at: k)
            learnedCount -= 1
        }
        return (next, added, refreshed)
    }

    public static func decode(_ plist: Any?) -> [Entry] {
        guard let rows = plist as? [[String: String]] else { return [] }
        return rows.compactMap { row in
            guard let h = row["heard"], let r = row["replacement"] else { return nil }
            return Entry(heard: h, replacement: r,
                         origin: row["origin"].flatMap(Entry.Origin.init(rawValue:)) ?? .manual,
                         promptOnly: row["promptOnly"] == "true")
        }
    }

    public static func encode(_ entries: [Entry]) -> [[String: String]] {
        entries.map { e in
            var row = ["heard": e.heard, "replacement": e.replacement]
            if e.origin != .manual { row["origin"] = e.origin.rawValue }
            if e.promptOnly { row["promptOnly"] = "true" }
            return row
        }
    }

    private struct Rule: Sendable {
        let key: [Character]
        let replacement: String
        let wordStart: Bool
        let wordEnd: Bool
        init(key: [Character], replacement: String) {
            self.key = key
            self.replacement = replacement
            wordStart = PersonalDictionary.isWordCharacter(key[0])
            wordEnd = PersonalDictionary.isWordCharacter(key[key.count - 1])
        }
    }

    static func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    public static func normalizedKey(_ s: String) -> String { TraditionalChinese.convert(trimmed(s)) }

    static func isCJK(_ c: Character) -> Bool {
        c.unicodeScalars.contains { u in
            if u.properties.isIdeographic { return true }
            switch u.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF,
                 0x1100...0x11FF, 0x3130...0x318F, 0xAC00...0xD7AF:
                return true
            default:
                return false
            }
        }
    }

    static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.count == 1 && c.unicodeScalars.first!.properties.isIdeographic
    }

    static func isWordCharacter(_ c: Character) -> Bool {
        (c.isLetter || c.isNumber) && !isCJK(c)
    }
}
