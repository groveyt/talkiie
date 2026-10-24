import Foundation

public struct TranscriptionPrompt: Equatable, Sendable {
    public static let empty = TranscriptionPrompt(terms: [])

    public static let tokenBudget = 200
    public static let whisperPromptLimit = 223
    public static let maxContextTokens = 224
    public static let maxTermCharacters = 24
    public static let maxTermUTF8Bytes = 96
    public static let maxPromptUTF8Bytes = 1024
    public static let separator = "、"
    public static let separatorTokens = 1

    public static let minimumTerms = 8

    private static var shortUtteranceSecondsText: String {
        ShortUtterance.maxSeconds.formatted(.number.precision(.fractionLength(0...1)))
    }

    public static var whenUsedClause: String {
        "詞庫有 \(minimumTerms) 個以上的詞時（只說一兩個字的短口述，約 \(shortUtteranceSecondsText) 秒內，"
            + "只要有 \(ShortUtterance.promptMinimumTerms) 個詞就會）"
    }

    public static func belowMinimumSummary(candidateCount: Int) -> String {
        let seconds = shortUtteranceSecondsText
        return "詞庫有 \(minimumTerms) 個以上的詞，一般口述才會拿來幫忙認字（目前 \(candidateCount) 個）；"
            + "只說一兩個字的短口述（約 \(seconds) 秒內）有 \(ShortUtterance.promptMinimumTerms) 個詞就會用"
    }

    public static let promptlessMaxSeconds = 2.0
    public static let quietRMSDBFS = -47.0
    public static let quietPeakDBFS = -30.0

    public let terms: [String]

    public struct Counts: Equatable, Sendable {
        public var manual = 0
        public var learned = 0
        public var dropped = 0
        public var gated = 0
        public var tokens = 0
        public init(manual: Int = 0, learned: Int = 0, dropped: Int = 0, gated: Int = 0, tokens: Int = 0) {
            self.manual = manual; self.learned = learned; self.dropped = dropped
            self.gated = gated; self.tokens = tokens
        }
    }
    public let counts: Counts

    public enum TermStatus: Equatable, Sendable {
        case sent
        case budgetFull
        case notAWord
        case tooFewTerms
        case unusable
    }
    private let sentKeys: Set<String>
    private let gatedKeys: Set<String>
    private let belowMinimum: Bool

    public var candidateCount: Int { terms.count + counts.dropped + counts.gated }

    public func status(of entry: PersonalDictionary.Entry) -> TermStatus {
        guard PersonalDictionary.isUsable(entry) else { return .unusable }
        let term = Self.sanitized(entry.replacement)
        let key = LearnedTermGate.foldedKey(term)
        if sentKeys.contains(key) { return .sent }
        guard Self.isUsableTerm(term) else { return .unusable }
        if gatedKeys.contains(key) { return .notAWord }
        return belowMinimum ? .tooFewTerms : .budgetFull
    }

    public init(dictionary: PersonalDictionary) {
        self.init(dictionary: dictionary, minimumTerms: Self.minimumTerms)
    }

    public init(dictionary: PersonalDictionary, minimumTerms: Int) {
        self.init(dictionary: dictionary, minimumTerms: minimumTerms, tokens: Self.tokens)
    }

    init(dictionary: PersonalDictionary, minimumTerms: Int, tokens countTokens: (String) -> Int) {
        let candidates = dictionary.promptCandidates
        func usable(_ list: [String]) -> [String] { list.map(Self.sanitized).filter(Self.isUsableTerm) }
        let manual = usable(candidates.manual), learned = usable(candidates.learned)
        let total = manual.count + learned.count
        guard total > 0, total >= minimumTerms else {
            self.init(terms: [], counts: Counts(dropped: total, gated: candidates.gated),
                      gatedKeys: candidates.gatedKeys, belowMinimum: total > 0); return
        }
        let ranked = manual.reversed().map { ($0, true) } + learned.map { ($0, false) }
        var picked: [(term: String, isManual: Bool)] = []
        var used = 0
        var bytes = 0
        for (term, isManual) in ranked {
            let cost = countTokens(term) + (picked.isEmpty ? 0 : Self.separatorTokens)
            let size = term.utf8.count + (picked.isEmpty ? 0 : Self.separator.utf8.count)
            guard used + cost <= Self.tokenBudget, bytes + size <= Self.maxPromptUTF8Bytes else { continue }
            used += cost
            bytes += size
            picked.append((term, isManual))
        }
        var emitted = Array(picked.reversed())
        var tokens = countTokens(emitted.map(\.term).joined(separator: Self.separator))
        while tokens > Self.tokenBudget, !emitted.isEmpty {
            emitted.removeFirst()
            tokens = countTokens(emitted.map(\.term).joined(separator: Self.separator))
        }
        let sentManual = emitted.filter(\.isManual).count
        self.init(terms: emitted.map(\.term),
                  counts: Counts(manual: sentManual, learned: emitted.count - sentManual,
                                 dropped: total - emitted.count, gated: candidates.gated, tokens: tokens),
                  gatedKeys: candidates.gatedKeys, belowMinimum: false)
    }

    init(terms: [String], counts: Counts = Counts(), gatedKeys: Set<String> = [], belowMinimum: Bool = false) {
        self.terms = terms
        self.counts = counts
        sentKeys = Set(terms.map(LearnedTermGate.foldedKey))
        self.gatedKeys = gatedKeys
        self.belowMinimum = belowMinimum
    }

    static func isUsableTerm(_ term: String) -> Bool {
        !term.isEmpty && term.count <= maxTermCharacters && term.utf8.count <= maxTermUTF8Bytes
    }

    public static func == (a: TranscriptionPrompt, b: TranscriptionPrompt) -> Bool { a.terms == b.terms }

    public var isEmpty: Bool { terms.isEmpty }

    public var text: String { terms.joined(separator: Self.separator) }

    public var maxContext: Int { isEmpty ? 0 : Self.maxContextTokens }

    public func forChunk(_ level: AudioLevelSummary) -> TranscriptionPrompt {
        Self.withholds(level) ? .empty : self
    }

    public static func withholds(_ level: AudioLevelSummary) -> Bool {
        level.seconds < promptlessMaxSeconds && (level.rmsDBFS < quietRMSDBFS || level.peakDBFS < quietPeakDBFS)
    }

    public static func isNearSilent(_ level: AudioLevelSummary) -> Bool {
        level.rmsDBFS < quietRMSDBFS && level.peakDBFS < quietPeakDBFS
    }

    public static func tokens(_ s: String) -> Int { WhisperTokenCounter.count(s) }

    static func sanitized(_ s: String) -> String {
        var out = ""
        var lastWasSpace = false
        for u in s.unicodeScalars {
            if u.properties.generalCategory == .control || u.properties.isWhitespace {
                if !lastWasSpace, !out.isEmpty { out.append(" ") }
                lastWasSpace = true
                continue
            }
            if u.properties.generalCategory == .format || u.properties.generalCategory == .lineSeparator
                || u.properties.generalCategory == .paragraphSeparator { continue }
            out.unicodeScalars.append(u)
            lastWasSpace = false
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
