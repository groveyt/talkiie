import Foundation

public enum ParagraphStrength: String, CaseIterable, Sendable {
    case off, standard, aggressive

    public var title: String {
        switch self {
        case .off: return "關"
        case .standard: return "標準"
        case .aggressive: return "積極"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            return "不自動分段，整段打成一段（清單仍照「條列」的設定）"
        case .standard:
            return "超過 150 字時，在句首的「另外／至於／所以／接下來……」換段，每段至少 30 字"
        case .aggressive:
            return "超過 100 字就分，每段至少 15 字；也看「再來／對了／營地那邊」，逗號後面的轉折詞也斷（那個逗號改成句號）"
        }
    }
}

public enum SemanticParagraphs {
    public static let defaultsKey = "semanticParagraphStrength"
    public static let defaultStrength: ParagraphStrength = .aggressive

    public static func strength(fromDefaults raw: String?) -> ParagraphStrength {
        raw.flatMap(ParagraphStrength.init(rawValue:)) ?? defaultStrength
    }

    public static let example = "這次露營的準備大概是這樣，帳篷跟睡袋都已經借到了，也在陽台試搭過一次，目前沒有看到什麼大問題，"
        + "只是營燈的電池還要再買一下。另外吃的會比較麻煩，因為要看當天的天氣決定煮什麼，我估計要準備兩到三種菜單。"
        + "營地那邊說中午才能進場，至於停車位還在等回覆。所以我的建議是先在山下吃完午餐再上山。"
        + "接下來我會先整理一份清單，把每個人要帶的東西列清楚，明天早上傳給大家。"

    public struct Parameters: Equatable, Sendable {
        public var triggerUnits: Int
        public var minParagraphUnits: Int
        public var maxParagraphUnits: Int
        public var minScore: Int
    }

    public static func parameters(_ strength: ParagraphStrength) -> Parameters? {
        switch strength {
        case .off: return nil
        case .standard: return Parameters(triggerUnits: 150, minParagraphUnits: 30, maxParagraphUnits: 120, minScore: 2)
        case .aggressive: return Parameters(triggerUnits: 100, minParagraphUnits: 15, maxParagraphUnits: 80, minScore: 1)
        }
    }

    static let commaSentenceUnits = 20

    public enum Category: String, Sendable, CaseIterable {
        case topicShift
        case conclusion
        case action
        case party
        case enumeration
        case length
    }

    public struct Break: Equatable, Sendable {
        public var position: Int
        public var category: Category
        public var score: Int
        public var afterComma: Bool
    }

    public static func split(_ line: String, strength: ParagraphStrength, totalUnits: Int) -> [String] {
        let chars = Array(line)
        let found = breaks(chars, strength: strength, totalUnits: totalUnits)
        guard !found.isEmpty else { return [trimTrailingSpaces(line)].filter { !$0.isEmpty } }
        var out: [String] = []
        var start = 0
        for b in found {
            var para = trimTrailingSpaces(String(chars[start..<b.position]))
            if b.afterComma, let last = para.last, commaBreaks.contains(last) {
                para.removeLast()
                para.append("。")
            }
            out.append(para)
            start = b.position
        }
        out.append(trimTrailingSpaces(String(chars[start...])))
        return out.filter { !$0.isEmpty }
    }

    public static func breaks(_ line: String, strength: ParagraphStrength, totalUnits: Int) -> [Break] {
        breaks(Array(line), strength: strength, totalUnits: totalUnits)
    }

    static func breaks(_ chars: [Character], strength: ParagraphStrength, totalUnits: Int) -> [Break] {
        guard let p = parameters(strength), totalUnits >= p.triggerUnits else { return [] }
        let candidates = self.candidates(chars)
        var out: [Break] = []
        var start = 0
        for c in candidates {
            let current = units(chars, start, c.position)
            let rest = units(chars, c.position, chars.count)
            guard rest >= p.minParagraphUnits, current >= p.minParagraphUnits else { continue }
            if c.score >= p.minScore {
                out.append(c)
                start = c.position
            } else if !c.afterComma, current >= p.maxParagraphUnits {
                out.append(Break(position: c.position, category: .length, score: 0, afterComma: false))
                start = c.position
            }
        }
        return out
    }

    static func candidates(_ chars: [Character]) -> [Break] {
        var out: [Break] = []
        var lastParty: String?
        for i in 1..<max(chars.count, 1) {
            guard let kind = boundary(chars, i) else { continue }
            let afterComma = kind == .comma
            if afterComma, onlyPrefixes(chars, from: sentenceStart(chars, i), to: i) { continue }
            let at = skipPrefixes(chars, i)
            var best: (Category, Int)?
            var partyAt = at
            if let cue = cue(chars, at: at) {
                if guardReason(chars, cue: cue, at: at, afterComma: afterComma) == nil { best = (cue.category, cue.weight) }
                partyAt = at + cue.word.count
                while partyAt < chars.count, chars[partyAt] == " " { partyAt += 1 }
            }
            if best == nil, enumerationMarker(chars, at: at) { best = (.enumeration, 2) }
            if let party = party(chars, at: partyAt) {
                let w = lastParty == nil ? 1 : (lastParty == party ? 0 : 2)
                lastParty = party
                if w > (best?.1 ?? 0) { best = (.party, w) }
            }
            var score = (best?.1 ?? 0) - (afterComma ? 1 : 0)
            if afterComma, score > 0, units(sentenceAround(chars, i)) < commaSentenceUnits { score = 0 }
            if score > 0, let best {
                out.append(Break(position: i, category: best.0, score: score, afterComma: afterComma))
            } else if !afterComma {
                out.append(Break(position: i, category: .length, score: 0, afterComma: false))
            }
        }
        return out
    }

    struct Cue {
        var word: String
        var category: Category
        var weight: Int
    }

    static let cues: [Cue] = {
        func make(_ words: [String], _ c: Category, _ w: Int) -> [Cue] { words.map { Cue(word: $0, category: c, weight: w) } }
        let all = make(["除此之外", "除此以外", "還有一件事", "还有一件事", "還有一點", "还有一点", "另一件事", "另一方面",
                        "順帶一提", "顺带一提", "順便一提", "顺便一提", "換個話題", "换个话题", "另外", "至於", "至于", "此外"],
                       .topicShift, 2)
            + make(["再來", "再来", "對了", "对了", "還有", "还有", "以及"], .topicShift, 1)
            + make(["總而言之", "总而言之", "總結來說", "总结来说", "我的建議是", "我的建议是", "結論是", "结论是",
                    "我建議", "我建议", "總之", "总之", "所以", "因此"], .conclusion, 2)
            + make(["接下來", "接下来", "下一步", "最後", "最后"], .action, 2)
            + make(["我們需要", "我们需要", "接著", "接着"], .action, 1)
        return all.sorted { $0.word.count > $1.word.count }
    }()

    static let prefixes = ["那麼", "那么", "然後", "然后", "那", "好", "嗯", "啊", "而"]

    enum GuardReason: Equatable {
        case determiner
        case nounPhrase
        case comeAgain
        case question
        case causalPair
        case eventually
    }

    static let determinerNext: Set<Character> = ["一", "的", "兩", "两", "幾", "几", "那", "個", "个", "些", "位", "半", "三", "四"]
    static let topicNouns = ["一件事", "件事", "一個問題", "一个问题", "個問題", "个问题", "一點", "一点",
                             "一個重點", "一个重点", "一個部分", "一个部分", "一部分", "一個議題", "一个议题"]
    static let comeAgainNext: Set<Character> = ["一", "吧", "啦", "喔", "哦", "了", "玩", "吃", "喝", "坐", "找", "拜", "過", "过", "嗎", "吗"]
    static let questionNext: Set<Character> = ["呢", "嗎", "吗", "咧"]
    static let stillHaveNext: Set<Character> = ["沒", "没", "多", "幾", "几", "時", "时"]
    static let eventuallyNext = ["還", "还", "才", "也", "都", "只", "決定", "决定", "變成", "变成", "發現", "发现",
                                 "竟然", "居然", "選", "选", "改"]

    static func guardReason(_ c: [Character], cue: Cue, at i: Int, afterComma: Bool) -> GuardReason? {
        let after = i + cue.word.count
        let next: Character? = after < c.count ? c[after] : nil
        switch cue.word {
        case "另外":
            if topicNouns.contains(where: { hasPrefix(c, after, $0) }) { return nil }
            if let n = next, determinerNext.contains(n) { return .determiner }
        case "最後", "最后":
            if next == "的" { return .nounPhrase }
            if afterComma || eventuallyNext.contains(where: { hasPrefix(c, after, $0) }) { return .eventually }
        case "接下來", "接下来", "下一步", "我們需要", "我们需要":
            if next == "的", !hasPrefix(c, after, "的話"), !hasPrefix(c, after, "的话") { return .nounPhrase }
        case "再來", "再来":
            if let n = next, comeAgainNext.contains(n) { return .comeAgain }
        case "還有", "还有":
            if let n = next, stillHaveNext.contains(n) || questionNext.contains(n) { return .question }
            if hasPrefix(c, after, "是不") { return .question }
        case "所以", "因此":
            if let n = next, questionNext.contains(n) { return .question }
            if afterComma { return .causalPair }
        case "對了", "对了":
            if let n = next, questionNext.contains(n) { return .question }
        default:
            break
        }
        if afterComma, questionWords.contains(where: { clause(c, from: after).contains($0) }) { return .question }
        return nil
    }

    static let questionWords = ["怎麼", "怎么", "為什麼", "为什么", "嗎", "吗"]

    static func clause(_ c: [Character], from i: Int) -> String {
        var j = i
        while j < c.count, !boundaryChars.contains(c[j]) { j += 1 }
        return String(c[min(i, j)..<j])
    }

    static let partyMarkers = ["那邊", "這邊", "那边", "这边", "的部分", "方面"]
    static let notParties: Set<String> = [
        "這", "这", "那", "這個", "这个", "那個", "那个", "這裡", "这里", "那裡", "那里", "另一", "一", "各",
        "上", "下", "左", "右", "前", "後", "后", "裡", "里", "外", "旁", "中間", "中间",
        "上面", "下面", "最上面", "最下面", "左邊", "左边", "右邊", "右边", "前面", "後面", "后面",
        "裡面", "里面", "外面", "旁邊", "旁边", "其他", "其它", "很多", "各個", "各个",
    ]
    static let clauseChars: Set<Character> = ["的", "在", "是", "有", "要", "說", "说", "到", "去", "從", "从",
                                              "放", "看", "把", "給", "给", "跟", "和", "被", "讓", "让", "個", "个",
                                              "為", "为", "什", "怎", "哪", "誰", "谁"]
    static let maxPartyUnits = 6

    static func party(_ c: [Character], at i: Int) -> String? {
        guard i < c.count else { return nil }
        var j = i
        var limit = 0
        while j < c.count, limit < 16 {
            if boundaryChars.contains(c[j]) { return nil }
            for m in partyMarkers where hasPrefix(c, j, m) {
                let x = String(c[i..<j]).trimmingCharacters(in: .whitespaces)
                return validParty(x) ? x.lowercased().filter { !$0.isWhitespace } : nil
            }
            j += 1
            limit += 1
        }
        return nil
    }

    static func validParty(_ x: String) -> Bool {
        guard !x.isEmpty, !notParties.contains(x) else { return false }
        guard x.allSatisfy({ TranscriptFormatter.isHan($0) || ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == " " })
        else { return false }
        if x.contains(where: { clauseChars.contains($0) }) { return false }
        if let first = x.first, first.isASCII, !first.isUppercase { return false }
        return TranscriptFormatter.countUnits(x) <= maxPartyUnits
    }

    enum BoundaryKind { case sentence, comma }

    static let sentenceBreaks: Set<Character> = ["。", "？", "！"]
    static let commaBreaks: Set<Character> = ["，", "；"]
    static let boundaryChars: Set<Character> = ["。", "？", "！", "，", "；", "：", "、", ".", "?", "!", ",", ";", ":"]

    static func boundary(_ c: [Character], _ i: Int) -> BoundaryKind? {
        guard i < c.count, !c[i].isWhitespace else { return nil }
        var j = i - 1
        while j >= 0, c[j] == " " { j -= 1 }
        guard j >= 0 else { return nil }
        if sentenceBreaks.contains(c[j]) { return .sentence }
        if commaBreaks.contains(c[j]) { return .comma }
        if ".?!".contains(c[j]), j < i - 1, !(j > 0 && c[j - 1] == ".") { return .sentence }
        return nil
    }

    static func sentenceStart(_ c: [Character], _ i: Int) -> Int {
        var j = i - 1
        while j >= 0, !sentenceBreaks.contains(c[j]) { j -= 1 }
        return j + 1
    }

    static func sentenceAround(_ c: [Character], _ i: Int) -> String {
        var hi = i
        while hi < c.count, !sentenceBreaks.contains(c[hi]) { hi += 1 }
        return String(c[sentenceStart(c, i)..<hi])
    }

    static func skipPrefixes(_ c: [Character], _ i: Int) -> Int {
        var at = i
        for _ in 0..<2 {
            guard cue(c, at: at) == nil, party(c, at: at) == nil,
                  let p = prefixes.first(where: { hasPrefix(c, at, $0) }) else { break }
            var k = at + p.count
            while k < c.count, c[k] == " " || commaBreaks.contains(c[k]) { k += 1 }
            guard k < c.count, cue(c, at: k) != nil || party(c, at: k) != nil || enumerationMarker(c, at: k)
                    || prefixes.contains(where: { hasPrefix(c, k, $0) })
            else { break }
            at = k
        }
        return at
    }

    static func onlyPrefixes(_ c: [Character], from: Int, to: Int) -> Bool {
        var k = from
        var any = false
        while k < to {
            if c[k] == " " || commaBreaks.contains(c[k]) { k += 1; continue }
            guard let p = prefixes.first(where: { hasPrefix(c, k, $0) }), k + p.count <= to else { return false }
            k += p.count
            any = true
        }
        return any
    }

    static func enumerationMarker(_ c: [Character], at i: Int) -> Bool {
        guard i < c.count, let m = SpokenList.marker(c, at: i), !m.weak else { return false }
        switch m.family {
        case .ordinal, .enumeration, .lai, .qi: return true
        case .sequence: return m.number == 1
        case .pair, .english, .englishNumber: return false
        }
    }

    static func cue(_ c: [Character], at i: Int) -> Cue? {
        cues.first { hasPrefix(c, i, $0.word) }
    }

    static func hasPrefix(_ c: [Character], _ i: Int, _ word: String) -> Bool {
        let w = Array(word)
        guard i >= 0, i + w.count <= c.count else { return false }
        return Array(c[i..<(i + w.count)]) == w
    }

    static func units(_ c: [Character], _ from: Int, _ to: Int) -> Int {
        TranscriptFormatter.countUnits(String(c[from..<to]))
    }

    static func units(_ s: String) -> Int { TranscriptFormatter.countUnits(s) }

    static func trimTrailingSpaces(_ s: String) -> String {
        var t = s
        while t.last == " " { t.removeLast() }
        return t
    }
}
