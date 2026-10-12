import Foundation

public enum FillerStrength: String, CaseIterable, Sendable {
    case off, light, medium, strong

    public var title: String {
        switch self {
        case .off: return "關"
        case .light: return "輕"
        case .medium: return "中"
        case .strong: return "強"
        }
    }

    public var detail: String {
        switch self {
        case .off: return "原樣保留"
        case .light: return "句尾的「這樣子／然後」、單獨的「嗯／呃」"
        case .medium: return "＋連說三次以上的重複收成兩次、重新講一次的整句話只留後面那句"
        case .strong: return "＋子句開頭的「那個／就是／然後」"
        }
    }
}

public enum FillerRemoval {
    public static let defaultsKey = "fillerRemovalStrength"
    public static let defaultStrength: FillerStrength = .off

    public static let example = "嗯。我們明天早上九點在車站集合，那個，要帶的東西東西東西先收好，然後大家在月台等就可以了這樣子。"

    public static func strength(fromDefaults raw: String?) -> FillerStrength {
        raw.flatMap(FillerStrength.init(rawValue:)) ?? defaultStrength
    }

    public struct Report: Equatable, Sendable {
        public var strength: FillerStrength
        public var spans: Int
        public var characters: Int
        public var guardRejected: Bool
    }

    public struct Result: Equatable, Sendable {
        public var text: String
        public var report: Report
    }

    static let thisWayMinContext = 4
    static let thenMinContext = 2

    public static func apply(_ text: String, strength: FillerStrength,
                             spokenLists: Bool = SpokenList.defaultEnabled) -> Result {
        guard strength != .off else {
            return Result(text: text, report: Report(strength: .off, spans: 0, characters: 0, guardRejected: false))
        }
        var r = Remover(text)
        r.run(strength, spokenLists: spokenLists)
        let out = r.output()
        guard r.spans > 0, out != text else {
            return Result(text: text, report: Report(strength: strength, spans: 0, characters: 0, guardRejected: false))
        }
        guard DeletionGuard.accepts(original: text, result: out, exempt: r.restartExemptChars) else {
            return Result(text: text, report: Report(strength: strength, spans: r.spans, characters: 0, guardRejected: true))
        }
        return Result(text: out, report: Report(strength: strength, spans: r.spans,
                                                characters: text.count - out.count, guardRejected: false))
    }

    static let trailingThisWay = ["這樣子", "这样子", "這樣", "这样"]
    static let trailingThen = ["然後最後", "然后最后", "然後", "然后"]
    static let thisWayBlockers: Set<Character> = [
        "就", "是", "像", "不", "別", "别", "要", "會", "会", "成", "得", "麼", "么", "能", "以", "該", "该",
        "敢", "都", "也", "還", "还", "才", "只", "如", "照", "按", "變", "变", "先", "再", "直", "果", "這", "这",
        "那", "樣", "样", "麽",
    ]
    static let interjections: Set<Character> = ["嗯", "呃", "啊", "欸", "诶", "誒"]
    static let leadingFillers = ["那個", "那个", "就是", "然後", "然后"]
    static let leadingThen: Set<String> = ["然後", "然后"]
    static let thenQuestion: Set<Character> = ["呢", "咧", "勒", "嘞"]
    static let listOpeners = ["首先"]
    static let numerals: Set<Character> = [
        "〇", "零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "百", "千", "萬", "万", "兩", "两",
    ]

    static let weakBreaks: Set<Character> = ["，", "、", "；", "：", ",", ";", ":"]
    static let strongBreaks: Set<Character> = ["。", "？", "！", ".", "?", "!", "…"]
    static func isBreak(_ c: Character) -> Bool { weakBreaks.contains(c) || strongBreaks.contains(c) }

    static let restartMinHanChars = 3
    static let restartMinWords = 2

    struct Remover {
        let chars: [Character]
        var deleted: [Bool]
        var spans = 0
        var restartExemptChars = 0

        init(_ text: String) {
            chars = Array(text)
            deleted = [Bool](repeating: false, count: chars.count)
        }

        func output() -> String {
            var s = ""
            s.reserveCapacity(chars.count)
            for (i, c) in chars.enumerated() where !deleted[i] { s.append(c) }
            return s
        }

        func clauses() -> [Range<Int>] {
            var out: [Range<Int>] = []
            var start = 0
            for i in 0..<chars.count where isBreak(chars[i]) {
                if i > start { out.append(start..<i) }
                start = i + 1
            }
            if start < chars.count { out.append(start..<chars.count) }
            return out
        }

        mutating func run(_ strength: FillerStrength, spokenLists: Bool) {
            let all = clauses()
            let hasListOpener = FillerRemoval.listOpeners.contains { String(chars).contains($0) }
            let contentClauses = all.filter { r in chars[r].contains(where: TranscriptFormatter.isHan) }
            for r in all {
                if strength == .medium || strength == .strong { collapseRepeats(r) }
                if strength == .strong { leading(r, hasListOpener: hasListOpener) }
                trailing(r, beforeListMarker: spokenLists)
                if contentClauses.count > 1 { interjectionClause(r) }
            }
            if strength == .medium || strength == .strong {
                for r in all { repairImmediateRepeat(r) }
            }
            for r in all where isFullyRemoved(r) { tidy(r) }
        }

        func kept(_ r: Range<Int>) -> [Int] { r.filter { !deleted[$0] && !chars[$0].isWhitespace } }

        func matches(_ word: String, at positions: ArraySlice<Int>) -> Bool {
            let w = Array(word)
            guard positions.count >= w.count else { return false }
            return zip(positions.prefix(w.count), w).allSatisfy { chars[$0] == $1 }
        }

        mutating func delete(_ positions: some Sequence<Int>) {
            for p in positions { deleted[p] = true }
            spans += 1
        }

        mutating func deleteRestart(_ positions: [Int]) {
            delete(positions)
            restartExemptChars += positions.count
        }

        mutating func trailing(_ r: Range<Int>, beforeListMarker: Bool) {
            while true {
                let k = kept(r)
                guard let (word, isThen) = trailingWord(k) else { break }
                let before = k.dropLast(word.count)
                let context = before.filter { TranscriptFormatter.isHan(chars[$0]) }.count
                if isThen {
                    guard context >= FillerRemoval.thenMinContext else { break }
                } else {
                    guard context >= FillerRemoval.thisWayMinContext, let last = before.last,
                          !FillerRemoval.thisWayBlockers.contains(chars[last]) else { break }
                }
                delete(k.suffix(word.count))
            }
            guard beforeListMarker else { return }
            let k = kept(r)
            var i = 0
            while i < k.count {
                if let word = FillerRemoval.trailingThen.first(where: { matches($0, at: k[i...]) }),
                   i + word.count < k.count, k[i + word.count] == k[i + word.count - 1] + 1,
                   i >= FillerRemoval.thenMinContext,
                   let m = SpokenList.marker(chars, at: k[i + word.count]), m.family == .ordinal {
                    delete(k[i..<(i + word.count)])
                    i += word.count
                } else {
                    i += 1
                }
            }
        }

        func trailingWord(_ k: [Int]) -> (String, Bool)? {
            for word in FillerRemoval.trailingThen + FillerRemoval.trailingThisWay where k.count >= word.count {
                if matches(word, at: k.suffix(word.count)[...]) {
                    return (word, FillerRemoval.trailingThen.contains(word))
                }
            }
            return nil
        }

        mutating func interjectionClause(_ r: Range<Int>) {
            let k = kept(r)
            guard !k.isEmpty, k.count <= 3, k.allSatisfy({ FillerRemoval.interjections.contains(chars[$0]) }) else { return }
            delete(k)
        }

        mutating func collapseRepeats(_ r: Range<Int>) {
            let k = kept(r)
            var i = 0
            outer: while i < k.count {
                for len in 1...4 where i + len <= k.count {
                    let unit = k[i..<(i + len)].map { chars[$0] }
                    guard unit.allSatisfy({ TranscriptFormatter.isHan($0) && !FillerRemoval.numerals.contains($0) })
                    else { continue }
                    var reps = 1
                    while i + (reps + 1) * len <= k.count,
                          k[(i + reps * len)..<(i + (reps + 1) * len)].map({ chars[$0] }) == unit {
                        reps += 1
                    }
                    if reps >= 3 {
                        delete(k[(i + 2 * len)..<(i + reps * len)])
                        i += reps * len
                        continue outer
                    }
                }
                i += 1
            }
        }

        mutating func leading(_ r: Range<Int>, hasListOpener: Bool) {
            while true {
                let k = kept(r)
                guard let word = FillerRemoval.leadingFillers.first(where: { matches($0, at: k[...]) }) else { return }
                let rest = k.dropFirst(word.count)
                let nextIsFiller = FillerRemoval.leadingFillers.contains { matches($0, at: rest) }
                if rest.isEmpty || nextIsFiller {
                    if FillerRemoval.leadingThen.contains(word), hasListOpener { return }
                    delete(k.prefix(word.count))
                    continue
                }
                guard FillerRemoval.leadingThen.contains(word), !hasListOpener,
                      let next = rest.first, !FillerRemoval.thenQuestion.contains(chars[next]),
                      rest.filter({ TranscriptFormatter.isHan(chars[$0]) }).count >= 2 else { return }
                delete(k.prefix(word.count))
                return
            }
        }

        func restartTokens(_ r: Range<Int>) -> [[Int]]? {
            var tokens: [[Int]] = []
            var i = r.lowerBound
            while i < r.upperBound {
                if deleted[i] { i += 1; continue }
                let c = chars[i]
                if c.isWhitespace { i += 1; continue }
                if TranscriptFormatter.isHan(c) {
                    tokens.append([i])
                    i += 1
                } else if c.isASCII, c.isLetter {
                    var word: [Int] = []
                    while i < r.upperBound, !deleted[i], chars[i].isASCII, chars[i].isLetter {
                        word.append(i)
                        i += 1
                    }
                    tokens.append(word)
                } else {
                    return nil
                }
            }
            return tokens.isEmpty ? nil : tokens
        }

        func restartLongEnough(_ tokens: ArraySlice<[Int]>) -> Bool {
            var han = 0, words = 0
            for t in tokens {
                if t.count == 1, TranscriptFormatter.isHan(chars[t[0]]) { han += 1 } else { words += 1 }
            }
            return han >= FillerRemoval.restartMinHanChars || words >= FillerRemoval.restartMinWords
        }

        func sameTokens(_ a: ArraySlice<[Int]>, _ b: ArraySlice<[Int]>) -> Bool {
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { ta, tb in
                ta.count == tb.count && zip(ta, tb).allSatisfy { chars[$0] == chars[$1] }
            }
        }

        mutating func repairImmediateRepeat(_ r: Range<Int>) {
            guard let tokens = restartTokens(r) else { return }
            var i = 0
            while i < tokens.count {
                var matched = false
                let maxLen = (tokens.count - i) / 2
                if maxLen >= 1 {
                    for len in stride(from: maxLen, through: 1, by: -1) {
                        let unit = tokens[i..<(i + len)]
                        guard sameTokens(unit, tokens[(i + len)..<(i + 2 * len)]), restartLongEnough(unit) else { continue }
                        var reps = 2
                        while i + (reps + 1) * len <= tokens.count,
                              sameTokens(tokens[(i + reps * len)..<(i + (reps + 1) * len)], unit) {
                            reps += 1
                        }
                        let start = unit.last!.last! + 1
                        let end = tokens[(i + reps * len - 1)].last! + 1
                        deleteRestart(Array(start..<end))
                        i += reps * len
                        matched = true
                        break
                    }
                }
                if !matched { i += 1 }
            }
        }

        func isFullyRemoved(_ r: Range<Int>) -> Bool {
            r.contains { !chars[$0].isWhitespace } && kept(r).isEmpty
        }

        mutating func tidy(_ r: Range<Int>) {
            let next: Int? = r.upperBound < chars.count ? r.upperBound : nil
            var p = r.lowerBound - 1
            while p >= 0, deleted[p] || chars[p].isWhitespace { p -= 1 }
            let prev: Int? = p >= 0 ? p : nil
            if let prev, FillerRemoval.weakBreaks.contains(chars[prev]) {
                if let next, FillerRemoval.weakBreaks.contains(chars[next]) {
                    deleted[next] = true
                } else {
                    deleted[prev] = true
                }
            } else if let next {
                deleted[next] = true
            }
        }
    }
}

public enum DeletionGuard {
    public static let maxDeletedFraction = 0.25

    public static func accepts(original: String, result: String, exempt: Int = 0) -> Bool {
        let o = Array(original), r = Array(result)
        guard isSubsequence(r, of: o) else { return false }
        guard !o.isEmpty else { return r.isEmpty }
        if o.contains(where: { !$0.isWhitespace }), !r.contains(where: { !$0.isWhitespace }) { return false }
        let risky = max(0, (o.count - r.count) - exempt)
        return Double(risky) <= Double(o.count) * maxDeletedFraction
    }

    static func isSubsequence(_ r: [Character], of o: [Character]) -> Bool {
        var i = 0
        for c in r {
            while i < o.count, o[i] != c { i += 1 }
            guard i < o.count else { return false }
            i += 1
        }
        return true
    }
}
