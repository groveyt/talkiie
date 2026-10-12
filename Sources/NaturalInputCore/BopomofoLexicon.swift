import Foundation

/// `tools/lexicon/bopomofo-subset/build.sh` 從小麥注音（McBopomofo 3.1.1，MIT；詞表的讀音上游是 libtabe，BSD）
public final class BopomofoLexicon: Sendable {
    public struct Syllable: Hashable, Sendable {
        public let initial: Character?
        public let final: [Character]
        public let tone: Character?

        public init?(_ s: some StringProtocol) {
            var chars = Array(s)
            guard !chars.isEmpty else { return nil }
            var tone: Character? = nil
            if let last = chars.last, BopomofoLexicon.toneMarks.contains(last) {
                tone = last == "ˉ" ? nil : last
                chars.removeLast()
            }
            if let first = chars.first, first == "˙" { tone = first; chars.removeFirst() }
            guard !chars.isEmpty else { return nil }
            if BopomofoLexicon.initials.contains(chars[0]) {
                initial = chars[0]
                final = Array(chars.dropFirst())
            } else {
                initial = nil
                final = chars
            }
            self.tone = tone
        }
    }

    public static let shared: BopomofoLexicon? = loadBundled()

    public static var isAvailable: Bool { shared != nil }

    /// 授權聲明（McBopomofo MIT＋libtabe BSD）在 bundle 裡的位置：跟資料一起出貨（自測與測試確認它在）。
    public static var licenseURL: URL? {
        Bundle.module.url(forResource: "LICENSE", withExtension: nil, subdirectory: "Bopomofo")
    }

    public static func preload() {
        Task.detached(priority: .utility) { _ = BopomofoLexicon.shared }
    }

    private let readingsByCharacter: [Character: [Syllable]]
    private let words: Set<String>

    public init(readings: [Character: [String]], words: Set<String>) {
        var r: [Character: [Syllable]] = [:]
        for (c, list) in readings {
            let syllables = list.compactMap { Syllable($0) }
            if !syllables.isEmpty { r[c] = syllables }
        }
        readingsByCharacter = r
        self.words = words
    }

    public var characterCount: Int { readingsByCharacter.count }
    public var wordCount: Int { words.count }

    public func isWord(_ s: some StringProtocol) -> Bool { words.contains(String(s)) }

    public func readings(of c: Character) -> [Syllable]? { readingsByCharacter[c] }

    public func distance(_ a: some Collection<Character>, _ b: some Collection<Character>) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var total = 0.0
        for (x, y) in zip(a, b) {
            if x == y { continue }
            guard let rx = readingsByCharacter[x], let ry = readingsByCharacter[y] else { return nil }
            var best = Double.infinity
            for p in rx { for q in ry { best = min(best, Self.cost(p, q)) } }
            total += best
        }
        return total
    }

    public static func cost(_ a: Syllable, _ b: Syllable) -> Double {
        var c = 0.0
        if a.initial != b.initial {
            if let x = a.initial, let y = b.initial, confusablePairs.contains(pair(x, y)) {
                c += 0.3
            } else if let x = a.initial, let y = b.initial, sibilants.contains(x), sibilants.contains(y) {
                c += 0.6
            } else {
                c += 1.0
            }
        }
        if a.final != b.final {
            let diffs = a.final.count == b.final.count
                ? zip(a.final, b.final).filter { $0 != $1 } : []
            if diffs.count == 1, let d = diffs.first, confusableFinals.contains(pair(d.0, d.1)) {
                c += 0.3
            } else {
                c += 1.0
            }
        }
        if a.tone != b.tone { c += 0.1 }
        return c
    }

    static let toneMarks: Set<Character> = ["ˉ", "ˊ", "ˇ", "ˋ", "˙"]
    static let initials: Set<Character> = Set("ㄅㄆㄇㄈㄉㄊㄋㄌㄍㄎㄏㄐㄑㄒㄓㄔㄕㄖㄗㄘㄙ")
    static let sibilants: Set<Character> = Set("ㄓㄔㄕㄗㄘㄙ")
    static let confusablePairs: Set<String> = Set(
        ([("ㄓ", "ㄗ"), ("ㄔ", "ㄘ"), ("ㄕ", "ㄙ"), ("ㄈ", "ㄏ"), ("ㄌ", "ㄋ"), ("ㄌ", "ㄖ")] as [(Character, Character)])
            .map { pair($0.0, $0.1) })
    static let confusableFinals: Set<String> = [pair("ㄣ", "ㄥ")]

    static func pair(_ x: Character, _ y: Character) -> String { x < y ? "\(x)\(y)" : "\(y)\(x)" }

    private static func read(_ name: String) -> String? {
        guard let path = Bundle.module.path(forResource: name, ofType: "txt", inDirectory: "Bopomofo"),
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func loadBundled() -> BopomofoLexicon? {
        guard let charText = read("chars"), let wordText = read("words") else { return nil }
        var readings: [Character: [Syllable]] = [:]
        readings.reserveCapacity(14_000)
        for line in charText.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, parts[0].count == 1, let c = parts[0].first else { continue }
            let syllables = parts[1].split(separator: " ").compactMap { Syllable($0) }
            if !syllables.isEmpty { readings[c] = syllables }
        }
        var set = Set<String>()
        set.reserveCapacity(140_000)
        for line in wordText.split(separator: "\n", omittingEmptySubsequences: true) { set.insert(String(line)) }
        guard !readings.isEmpty, !set.isEmpty else { return nil }
        return BopomofoLexicon(syllables: readings, words: set)
    }

    private init(syllables: [Character: [Syllable]], words: Set<String>) {
        readingsByCharacter = syllables
        self.words = words
    }
}
