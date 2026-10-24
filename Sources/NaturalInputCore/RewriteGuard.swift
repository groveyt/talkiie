import Foundation

public enum RewriteGuard {
    public static let maxDeletionPercent = 35
    public static let deletableClauseMaxUnits = 4
    public static let questionClauseMaxDeletionPercent = 40
    public static let maxGrowthPercent = 10
    public static let maxNewCharacterPercent = 25

    public enum Verdict: Equatable, Sendable {
        case accepted(String)
        case unchanged
        case rejected(RewriteRejection)
    }

    public static func check(mode: WrittenStyleMode, original: String, suggestion: String,
                             keepWords: [String] = []) -> Verdict {
        switch mode {
        case .cautious: return cautious(original: original, suggestion: suggestion, keepWords: keepWords)
        case .aggressive: return aggressive(original: original, suggestion: suggestion, keepWords: keepWords)
        }
    }

    static let negationSingles: Set<Character> = ["不", "沒", "没", "別", "别", "未", "無", "无", "莫", "勿"]
    static let negationWords = ["不要", "不用", "沒有", "没有", "不是", "不會", "不会", "不能", "不可以", "不必",
                                "不需要", "無法", "无法", "別再", "未必"]
    static let scopeSingles: Set<Character> = ["只", "才", "都", "也"]
    static let degreeSingles: Set<Character> = ["很", "更", "最", "太", "蠻", "蛮", "挺", "極", "极"]
    static let degreeWords = ["比較", "比较", "非常", "相當", "相当", "有點", "有点", "稍微", "特別", "特别"]
    static let numberSingles: Set<Character> = ["零", "〇", "一", "二", "三", "四", "五", "六", "七", "八", "九", "十",
                                                 "百", "千", "萬", "万", "億", "亿", "兩", "两", "廿", "卅"]
    static let questionSingles: Set<Character> = ["？", "?", "嗎", "吗"]
    static let questionWords = ["呢？", "呢?"]
    static let interrogativeSingles: Set<Character> = ["誰", "谁", "哪", "幾", "几"]
    static let interrogativeWords = ["什麼", "甚麼", "什么", "怎麼", "怎么", "怎樣", "怎样", "為什麼", "为什么",
                                     "多少", "是否", "如何", "為何", "为何"]

    static func compact(_ s: String) -> [Character] { s.filter { !$0.isWhitespace }.map { $0 } }

    static func count(_ c: Character, in a: [Character]) -> Int { a.reduce(0) { $0 + ($1 == c ? 1 : 0) } }

    static func count(_ word: String, in a: [Character]) -> Int {
        let w = Array(word)
        guard !w.isEmpty, w.count <= a.count else { return 0 }
        var n = 0
        for i in 0...(a.count - w.count) where a[i] == w[0] && Array(a[i..<(i + w.count)]) == w { n += 1 }
        return n
    }

    static func freeFei(in a: [Character]) -> Int {
        var n = 0
        for (i, c) in a.enumerated() where c == "非" && !(i + 1 < a.count && a[i + 1] == "常") { n += 1 }
        return n
    }

    static func freeJiu(in a: [Character]) -> Int {
        var n = 0
        for (i, c) in a.enumerated() where c == "就" {
            let next = i + 1 < a.count ? a[i + 1] : nil
            let next2: [Character] = i + 3 <= a.count ? Array(a[(i + 1)..<(i + 3)]) : []
            if next == "是" || next2 == ["這", "樣"] || next2 == ["这", "样"] { continue }
            n += 1
        }
        return n
    }

    static func isFullWidthDigit(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1 else { return false }
        return (0xFF10...0xFF19).contains(v)
    }

    static func protectedLoss(original o: [Character], result r: [Character], keepWords: [String]) -> RewriteRejection? {
        func lost(_ singles: Set<Character>) -> Bool { singles.contains { count($0, in: r) < count($0, in: o) } }
        func lost(_ words: [String]) -> Bool { words.contains { count($0, in: r) < count($0, in: o) } }
        if lost(negationSingles) || lost(negationWords) || freeFei(in: r) < freeFei(in: o) { return .negationDeleted }
        if lost(scopeSingles) || freeJiu(in: r) < freeJiu(in: o) { return .scopeWordDeleted }
        if lost(degreeSingles) || lost(degreeWords) { return .degreeWordDeleted }
        if lost(numberSingles) || r.filter(isFullWidthDigit) != o.filter(isFullWidthDigit) { return .numberChanged }
        if r.filter({ $0.isASCII }) != o.filter({ $0.isASCII }) { return .asciiChanged }
        if lost(questionSingles) || lost(questionWords) { return .questionChanged }
        if lost(interrogativeSingles) || lost(interrogativeWords) { return .interrogativeDeleted }
        if lost(keepWords.filter { !$0.isEmpty }) { return .keepWordDeleted }
        return nil
    }

    static func isContent(_ c: Character) -> Bool { !c.isWhitespace && !PunctuationGuard.isPunctuation(c) }

    static let clauseEnders: Set<Character> = ["，", "。", "？", "！", "；", "：", "、", "\n", ",", "?", "!", ";"]
    static let questionEnders: Set<Character> = ["？", "?"]

    static func cautious(original: String, suggestion: String, keepWords: [String]) -> Verdict {
        let o = Array(original)
        let s = compact(suggestion)
        guard !s.isEmpty else { return .rejected(.empty) }

        guard let keep = embed(o, s, fromRight: false), let keepRight = embed(o, s, fromRight: true) else {
            return .rejected(.notSubsequence)
        }
        guard keep.contains(false) else { return .unchanged }

        let total = o.filter(isContent).count
        let removed = o.indices.filter { !keep[$0] && isContent(o[$0]) }.count
        if removed * 100 > total * maxDeletionPercent { return .rejected(.tooMuchDeleted) }

        if let r = structureLoss(o, keep: keep) ?? structureLoss(o, keep: keepRight) { return .rejected(r) }
        if mergesClauses(o, keep: keep) || mergesClauses(o, keep: keepRight) { return .rejected(.clauseMerged) }

        let result = tidy(restoringSeparators(o, keep: keep))
        if let loss = protectedLoss(original: compact(original), result: compact(String(result)), keepWords: keepWords) {
            return .rejected(loss)
        }
        guard isSubsequence(result, of: o) else { return .rejected(.notSubsequence) }
        let out = String(result)
        return out == original ? .unchanged : .accepted(out)
    }

    static func restoringSeparators(_ o: [Character], keep: [Bool]) -> [Character] {
        var keep = keep
        let strength: [Character: Int] = ["？": 6, "?": 6, "！": 6, "!": 6, "。": 5, "；": 4, ";": 4, "：": 3,
                                          "，": 2, ",": 2, "、": 1]
        var i = 0
        while i < o.count {
            guard !keep[i], !o[i].isWhitespace else { i += 1; continue }
            var j = i
            var content = 0
            var best: Int?
            while j < o.count, o[j] != "\n", !keep[j] || o[j].isWhitespace {
                if !o[j].isWhitespace {
                    if isContent(o[j]) { content += 1 }
                    if let st = strength[o[j]], st > (best.map { strength[o[$0]] ?? 0 } ?? 0) { best = j }
                }
                j += 1
            }
            let prev = o[..<i].lastIndex { !$0.isWhitespace && $0 != "\n" }
            let lineBreakBefore = o[(prev.map { $0 + 1 } ?? 0)..<i].contains("\n")
            let interior = prev != nil && !lineBreakBefore && j < o.count && o[j] != "\n" && keep[j]
            if interior, let b = best, let p = prev, isContent(o[p]), isContent(o[j]),
               content != 1 || joinsASCIIAndCJK(o[p], o[j]) {
                keep[b] = true
            }
            i = max(j, i + 1)
        }
        return o.indices.filter { keep[$0] }.map { o[$0] }
    }

    static func joinsASCIIAndCJK(_ a: Character, _ b: Character) -> Bool {
        func ascii(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
        func cjk(_ c: Character) -> Bool { !c.isASCII && isContent(c) }
        return (ascii(a) && cjk(b)) || (cjk(a) && ascii(b))
    }

    static let fillerChars: Set<Character> = Set("啦吧啊呀嘛喔哦囉呃嗯欸耶喇那個這就是然後其實所以反正對好")

    static func mergesClauses(_ o: [Character], keep: [Bool]) -> Bool {
        func deletedSpan(from start: Int, step: Int) -> [Character]? {
            var i = start
            while o.indices.contains(i), o[i].isWhitespace { i += step }
            guard o.indices.contains(i), !keep[i], isContent(o[i]) else { return nil }
            var span: [Character] = []
            while o.indices.contains(i), o[i] != "\n", !clauseEnders.contains(o[i]), !(keep[i] && isContent(o[i])) {
                if !keep[i], isContent(o[i]) { span.append(o[i]) }
                i += step
            }
            return o.indices.contains(i) && keep[i] && isContent(o[i]) ? span : nil
        }
        for e in o.indices where keep[e] && clauseEnders.contains(o[e]) && o[e] != "\n" {
            guard let left = deletedSpan(from: e - 1, step: -1), let right = deletedSpan(from: e + 1, step: 1) else { continue }
            if !left.allSatisfy(fillerChars.contains) || !right.allSatisfy(fillerChars.contains) { return true }
        }
        return false
    }

    static func embed(_ o: [Character], _ s: [Character], fromRight: Bool) -> [Bool]? {
        var keep = [Bool](repeating: true, count: o.count)
        let order = fromRight ? Array(o.indices.reversed()) : Array(o.indices)
        var j = fromRight ? s.count - 1 : 0
        for i in order where !o[i].isWhitespace {
            let inRange = fromRight ? j >= 0 : j < s.count
            if inRange, s[j] == o[i] { j += fromRight ? -1 : 1 } else { keep[i] = false }
        }
        return (fromRight ? j == -1 : j == s.count) ? keep : nil
    }

    static func structureLoss(_ o: [Character], keep: [Bool]) -> RewriteRejection? {
        var marker = [Bool](repeating: false, count: o.count)
        var lineStart = 0
        for i in 0...o.count where i == o.count || o[i] == "\n" {
            var k = lineStart
            while k < i, o[k].isASCII, o[k].isNumber { k += 1 }
            if k > lineStart, k + 1 < i, o[k] == ".", o[k + 1] == " " { for m in lineStart..<k { marker[m] = true } }
            lineStart = i + 1
        }
        var clauseTotal = 0, clauseKept = 0
        var lineTotal = 0, lineKept = 0
        for (i, c) in o.enumerated() {
            if isContent(c), !marker[i] {
                clauseTotal += 1; lineTotal += 1
                if keep[i] { clauseKept += 1; lineKept += 1 }
            }
            if clauseEnders.contains(c) || i == o.count - 1 {
                if clauseTotal > deletableClauseMaxUnits, clauseKept == 0 { return .clauseDeleted }
                if questionEnders.contains(c), clauseTotal > 0,
                   (clauseTotal - clauseKept) * 100 > clauseTotal * questionClauseMaxDeletionPercent {
                    return .questionChanged
                }
                clauseTotal = 0; clauseKept = 0
            }
            if c == "\n" || i == o.count - 1 {
                if lineTotal > 0, lineKept == 0 { return .lineDeleted }
                lineTotal = 0; lineKept = 0
            }
        }
        return nil
    }

    static func isSubsequence(_ a: [Character], of b: [Character]) -> Bool {
        var it = b.makeIterator()
        return a.allSatisfy { c in
            while let x = it.next() { if x == c { return true } }
            return false
        }
    }

    static let pausePunctuation: Set<Character> = ["，", "、", "；", "：", ",", ";"]
    static let trailingPausePunctuation: Set<Character> = ["，", "、", "；", ",", ";"]
    static let anyPunctuation: Set<Character> = ["，", "。", "？", "！", "、", "；", "：", ",", ".", "?", "!", ";", ":"]

    static func tidy(_ input: [Character]) -> [Character] {
        var lines: [[Character]] = [[]]
        for c in input { if c == "\n" { lines.append([]) } else { lines[lines.count - 1].append(c) } }
        return Array(lines.map(tidyLine).joined(separator: ["\n"]))
    }

    private static func tidyLine(_ line: [Character]) -> [Character] {
        var start = 0
        while start < line.count, line[start].isASCII, line[start].isNumber { start += 1 }
        let marker = start > 0 && start + 1 < line.count && line[start] == "." && line[start + 1] == " "
        let prefix = marker ? Array(line[0..<(start + 2)]) : []
        var body = Array(line[prefix.count...])

        var changed = true
        while changed {
            changed = false
            while let f = body.first, f == " " || pausePunctuation.contains(f) { body.removeFirst(); changed = true }
            var out: [Character] = []
            var i = 0
            while i < body.count {
                let c = body[i]
                if trailingPausePunctuation.contains(c) {
                    var k = i + 1
                    while k < body.count, body[k] == " " { k += 1 }
                    if k == body.count || anyPunctuation.contains(body[k]) { i += 1; changed = true; continue }
                }
                if c == " " {
                    let prev = out.last
                    let next: Character? = i + 1 < body.count ? body[i + 1] : nil
                    let keepSpace: Bool = {
                        guard let p = prev, let n = next, p != " ", n != " " else { return false }
                        if isCJKPunctuation(p) || isCJKPunctuation(n) { return false }
                        return p.isASCII || n.isASCII
                    }()
                    if !keepSpace { i += 1; changed = true; continue }
                }
                out.append(c)
                i += 1
            }
            body = out
        }
        return prefix + body
    }

    static func isCJKPunctuation(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3000...0x303F).contains(v) || (0xFF00...0xFFEF).contains(v)
    }

    static let quotePairs: [(Character, Character)] = [("「", "」"), ("『", "』"), ("“", "”"), ("\"", "\"")]

    static func negationCount(_ a: [Character]) -> Int {
        let words = (["非常"] + negationWords + negationSingles.map { String($0) }).sorted { $0.count > $1.count }
        var n = 0, i = 0
        outer: while i < a.count {
            for w in words {
                let wc = Array(w)
                if i + wc.count <= a.count, Array(a[i..<(i + wc.count)]) == wc {
                    if w != "非常" { n += 1 }
                    i += wc.count
                    continue outer
                }
            }
            i += 1
        }
        return n
    }

    static func asciiWords(_ s: String) -> [String: Int] {
        var out: [String: Int] = [:]
        var cur = ""
        func flush() { if !cur.isEmpty { out[cur.lowercased(), default: 0] += 1; cur = "" } }
        for c in s {
            var ch = c
            if isFullWidthDigit(c), let v = c.unicodeScalars.first?.value, let u = Unicode.Scalar(v - 0xFF10 + 0x30) {
                ch = Character(u)
            }
            if ch.isASCII, ch.isLetter || ch.isNumber { cur.append(ch) } else { flush() }
        }
        flush()
        return out
    }

    static func listMarker(_ line: Substring) -> String? {
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, line.dropFirst(digits.count).first == "." else { return nil }
        return String(digits)
    }

    static func isSimplifiedOnly(_ c: Character) -> Bool {
        guard TranscriptFormatter.isHan(c) else { return false }
        let s = String(c)
        return (s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s) != s
    }

    static func aggressive(original: String, suggestion raw: String, keepWords: [String]) -> Verdict {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for (l, r) in quotePairs where s.count >= 2 && s.first == l && s.last == r && original.first != l {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !s.isEmpty else { return .rejected(.empty) }
        if compact(s) == compact(original) { return .unchanged }

        let oContent = original.filter(isContent).count
        if s.filter(isContent).count * 100 > oContent * (100 + maxGrowthPercent) { return .rejected(.gotLonger) }

        if original.contains("\n") || s.contains("\n") {
            let ol = original.split(separator: "\n", omittingEmptySubsequences: false)
            let sl = s.split(separator: "\n", omittingEmptySubsequences: false)
            guard ol.count == sl.count else { return .rejected(.lineStructure) }
            for (a, b) in zip(ol, sl) {
                let aEmpty = a.allSatisfy(\.isWhitespace), bEmpty = b.allSatisfy(\.isWhitespace)
                guard aEmpty == bEmpty, listMarker(a) == listMarker(b) else { return .rejected(.lineStructure) }
            }
        }

        let ow = asciiWords(original), sw = asciiWords(s)
        for (w, n) in ow where (sw[w] ?? 0) < n {
            return .rejected(w.allSatisfy(\.isNumber) ? .numberChanged : .asciiChanged)
        }
        let oc = compact(original), sc = compact(s)
        for c in numberSingles where c != "一" && count(c, in: sc) < count(c, in: oc) { return .rejected(.numberChanged) }

        let originalSet = Set(original)
        if s.contains(where: { !originalSet.contains($0) && isSimplifiedOnly($0) }) { return .rejected(.simplifiedIntroduced) }
        if negationCount(sc) != negationCount(oc) { return .rejected(.negationChanged) }
        if keepWords.contains(where: { !$0.isEmpty && count($0, in: sc) < count($0, in: oc) }) {
            return .rejected(.keepWordDeleted)
        }

        let han = s.filter(TranscriptFormatter.isHan)
        let novel = han.filter { !originalSet.contains($0) }.count
        if novel * 100 > han.count * maxNewCharacterPercent {
            return .rejected(.tooManyNewCharacters)
        }

        let out = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { PanguSpacing.apply(TranscriptFormatter.fullWidthPunctuation(String($0))) }
            .joined(separator: "\n")
        return out == original ? .unchanged : .accepted(out)
    }

    public static func changedPercent(original: String, result: String) -> Int {
        let a = original.filter(isContent).count, b = result.filter(isContent).count
        guard a > 0 else { return 0 }
        return Int((Double(a - b) * 100 / Double(a)).rounded())
    }
}
