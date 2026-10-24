import Foundation

public enum SpokenList {
    public static let defaultsKey = "spokenListFormatting"
    public static let defaultEnabled = true

    public static func enabled(fromDefaults value: Any?) -> Bool {
        (value as? Bool) ?? defaultEnabled
    }

    public static let example = "有兩件事，一個是速度，另一個是用詞"

    static func lines(_ paragraph: String) -> [String] {
        blocks(paragraph).map(\.text)
    }

    static func blocks(_ paragraph: String, modelPunctuated: Bool = false) -> [(text: String, isItem: Bool)] {
        let chars = Array(paragraph)
        let run = findRun(chars)
        if let counted = announcedList(chars), run.map({ counted.end <= $0[0].start }) ?? true {
            return layout(chars, introEnd: counted.introEnd, items: counted.items, restStart: counted.restStart,
                          modelPunctuated: modelPunctuated)
        }
        guard let run else { return [(paragraph, false)] }

        let english = run[0].family.isEnglish
        var items: [String] = []
        var restStart = chars.count
        for (k, m) in run.enumerated() {
            let from = m.keepsText ? m.start : english ? englishSkipFiller(chars, m.end) : skipFiller(chars, m.end)
            var to: Int
            var keep = ""
            if k + 1 < run.count {
                to = run[k + 1].start
            } else if english {
                to = englishSentenceEnd(chars, from: from)
                restStart = min(to + 1, chars.count)
                if to < chars.count, !"。.".contains(chars[to]) { keep = String(chars[to]) }
            } else {
                to = from
                while to < chars.count, !sentenceEnders.contains(chars[to]) { to += 1 }
                if modelPunctuated, to < chars.count, chars[to] == "。",
                   cutShortByModel(chars, run: run, lastFrom: m.end, lastTo: to) {
                    var next = to + 1
                    while next < chars.count, !sentenceEnders.contains(chars[next]) { next += 1 }
                    to = next
                }
                restStart = min(to + 1, chars.count)
                if to < chars.count, chars[to] != "。" { keep = String(chars[to]) }
            }
            while to > from, trailingTrim.contains(chars[to - 1]) { to -= 1 }
            if english {
                to = englishTrimEnd(chars, from: from, to: to)
                guard to > from else { return [(paragraph, false)] }
                var item = String(chars[from..<to]) + keep
                if !m.keepsText, item.last == "?" || item.last == "？" {
                    let withIs = englishSkipFiller(chars, m.end, dropsIs: false)
                    if withIs < from { item = String(chars[withIs..<to]) + keep }
                }
                items.append(item)
                continue
            }
            if k + 1 < run.count {
                for word in trailingConnectives where to - from > word.count
                    && String(chars[(to - word.count)..<to]) == word {
                    to -= word.count
                    while to > from, trailingTrim.contains(chars[to - 1]) { to -= 1 }
                    break
                }
            }
            guard to > from else { return [(paragraph, false)] }
            items.append(String(chars[from..<to]) + keep)
        }
        return layout(chars, introEnd: run[0].start, items: items, restStart: restStart, english: english,
                      modelPunctuated: modelPunctuated)
    }

    private static func cutShortByModel(_ c: [Character], run: [Marker], lastFrom: Int, lastTo: Int) -> Bool {
        guard run.count >= 2, lastTo > lastFrom else { return false }
        let last = TranscriptFormatter.countUnits(String(c[lastFrom..<lastTo]))
        guard last <= modelCutLastItemMaxUnits else { return false }
        let others = zip(run, run.dropFirst()).map { TranscriptFormatter.countUnits(String(c[$0.end..<$1.start])) }
        guard let shortest = others.min() else { return false }
        return shortest >= max(3 * last, modelCutOtherItemMinUnits)
    }
    static let modelCutLastItemMaxUnits = 4
    static let modelCutOtherItemMinUnits = 8

    private static func layout(_ chars: [Character], introEnd: Int, items: [String],
                               restStart: Int, english: Bool = false,
                               modelPunctuated: Bool = false) -> [(text: String, isItem: Bool)] {
        var out: [(text: String, isItem: Bool)] = []
        var intro = String(chars[0..<introEnd])
        while intro.last == " " { intro.removeLast() }
        if let last = intro.last, introJoiners.contains(last) { intro.removeLast() }
        if english {
            if let last = intro.last, !sentenceEnders.contains(last), !".?!".contains(last) {
                intro.append(TranscriptFormatter.isHan(last) ? "：" : ":")
            }
        } else if let last = intro.last, !sentenceEnders.contains(last) { intro.append("：") }
        if !intro.isEmpty { out.append((intro, false)) }
        for (k, item) in items.enumerated() { out.append(("\(k + 1). \(item)", true)) }
        var rest = String(chars[restStart...])
        while rest.first == " " { rest.removeFirst() }
        if !rest.isEmpty { out += blocks(rest, modelPunctuated: modelPunctuated) }
        return out
    }

    enum Family {
        case ordinal, enumeration, sequence
        case pair
        case lai
        case qi
        case english
        case englishNumber

        var isEnglish: Bool { self == .english || self == .englishNumber }
    }

    struct Marker {
        var family: Family
        var weak = false
        var number: Int
        var strong: Bool
        var start: Int
        var end: Int
        var keepsText = false
        var bareDigit = false
        var droppedOrdinal = false
    }

    static func findRun(_ c: [Character]) -> [Marker]? {
        var i = 0
        while i < c.count {
            guard let first = marker(c, at: i), first.number == 1 else { i += 1; continue }
            var run = [first]
            var j = first.end
            scan: while j < c.count {
                if first.family == .pair, sentenceEnders.contains(c[j]) { break scan }
                if first.family == .ordinal, let m = droppedOrdinalMarker(c, at: j, expected: run.count + 1) {
                    run.append(m)
                    j = m.end
                    continue scan
                }
                guard let m = marker(c, at: j), sameList(first, m, c) else { j += 1; continue }
                switch m.family {
                case .ordinal, .enumeration, .lai, .qi, .englishNumber:
                    if m.bareDigit, m.number != run.count + 1 { j = m.end; continue scan }
                    guard m.number == run.count + 1 else { break scan }
                    run.append(m)
                case .english:
                    guard m.number == run.count + 1 || m.number == -1 else { break scan }
                    run.append(m)
                    if m.number == -1 { break scan }
                case .pair:
                    run.append(m)
                case .sequence:
                    guard m.number != 1 else { break scan }
                    run.append(m)
                    if m.number == -1 { break scan }
                }
                j = m.end
            }
            if let cut = run.firstIndex(where: \.droppedOrdinal),
               run.filter({ $0.family == .ordinal && !$0.droppedOrdinal }).count < droppedOrdinalMinExplicit {
                run = Array(run[..<cut])
            }
            let bareMidSentence = run.contains(where: \.bareDigit) && !atSentenceStart(c, first.start)
            let needs = run.contains(where: \.weak) || bareMidSentence
                || (first.family == .sequence && run.last?.number != -1) ? 3 : 2
            if run.count >= needs { return run }
            i += 1
        }
        return implicitFirstItemRun(c)
    }

    private static func droppedOrdinalMarker(_ c: [Character], at i: Int, expected: Int) -> Marker? {
        guard expected >= 2, !c[i].isASCII, let (n, len) = number(c, i), n == expected else { return nil }
        if i > 0 {
            let p = c[i - 1]
            let afterWord = isHan(p) && !attachers.contains(p) && !droppedOrdinalBlockedBefore.contains(p)
            guard clauseBreaks.contains(p) || afterWord else { return nil }
        }
        let k = i + len
        guard k < c.count else { return nil }
        var content = k
        if markerPunct.contains(c[k]) {
            content = k + 1
            while content < c.count, c[content] == " " { content += 1 }
            guard content < c.count else { return nil }
        }
        guard isHan(c[content]), !droppedOrdinalBlockedAfter.contains(c[content]) else { return nil }
        return Marker(family: .ordinal, number: n, strong: false, start: i, end: k, droppedOrdinal: true)
    }
    static let droppedOrdinalMinExplicit = 2
    private static let droppedOrdinalBlockedBefore: Set<Character> = [
        "第", "週", "周", "期", "拜", "初", "十", "百", "千", "萬", "万", "零", "一", "二", "三", "四", "五", "六", "七",
        "八", "九", "兩", "两", "幾", "几", "每", "約", "约", "共", "前", "號", "号", "年", "月",
    ]
    private static let droppedOrdinalBlockedAfter: Set<Character> = [
        "個", "个", "位", "名", "次", "回", "遍", "趟", "件", "張", "张", "份", "本", "篇", "條", "条", "項", "项", "組", "组",
        "塊", "块", "元", "角", "毛", "人", "天", "年", "月", "日", "號", "号", "點", "点", "時", "时", "分", "秒", "週", "周",
        "歲", "岁", "樓", "楼", "層", "层", "樣", "样", "種", "种", "成", "倍", "度", "季", "期", "級", "级", "輪", "轮",
        "場", "场", "局", "屆", "届", "代", "章", "節", "节", "題", "题", "頁", "页", "段", "句", "行", "列", "排", "線", "线",
        "半", "輩", "辈", "世",
        "十", "百", "千", "萬", "万", "億", "亿", "零", "一", "二", "三", "四", "五", "六", "七", "八", "九", "兩", "两",
        "手", "胎", "來", "来", "明", "國", "国", "星", "處", "处", "川", "面", "方", "金", "官", "夕", "卦", "足", "心",
        "意", "合", "環", "环", "寶", "宝", "姊", "姐", "妹", "哥", "弟", "叔", "伯", "等",
    ]

    private static func sameList(_ first: Marker, _ m: Marker, _ c: [Character]) -> Bool {
        if m.family == first.family { return true }
        let pair = [first, m]
        return pair.contains { $0.family == .ordinal }
            && pair.contains { $0.family == .enumeration && c[$0.start].isASCII }
    }

    private static func atSentenceStart(_ c: [Character], _ i: Int) -> Bool {
        var b = i
        while b > 0, c[b - 1] == " " { b -= 1 }
        return b == 0 || sentenceEnders.contains(c[b - 1])
    }

    static let implicitFirstMaxLength = 80
    private static func implicitFirstItemRun(_ c: [Character]) -> [Marker]? {
        var i = 0
        while i < c.count {
            guard let second = marker(c, at: i), second.family == .ordinal, second.number == 2, second.strong
            else { i += 1; continue }
            var run = [second]
            var j = second.end
            while j < c.count {
                guard let m = marker(c, at: j), m.family == .ordinal else { j += 1; continue }
                guard m.number == run.count + 2, m.strong else { break }
                run.append(m)
                j = m.end
            }
            var sentenceStart = second.start
            while sentenceStart > 0, !sentenceEnders.contains(c[sentenceStart - 1]) { sentenceStart -= 1 }
            let firstText = c[sentenceStart..<second.start].filter { !trailingTrim.contains($0) }
            if run.count >= 2, !firstText.isEmpty, second.start - sentenceStart <= implicitFirstMaxLength {
                return [Marker(family: .ordinal, number: 1, strong: false, start: sentenceStart, end: sentenceStart)] + run
            }
            i += 1
        }
        return nil
    }

    static func marker(_ c: [Character], at i: Int) -> Marker? {
        if c[i].isASCII, c[i].isLetter { return englishMarker(c, at: i) }
        let atClauseStart = i == 0 || clauseBreaks.contains(c[i - 1])
        let afterHan = i > 0 && isHan(c[i - 1]) && !attachers.contains(c[i - 1])
        if c[i] == "第", let (n, len) = number(c, i + 1) {
            let j = i + 1 + len
            let afterCountIntro = i > 1 && (c[i - 1] == "個" || c[i - 1] == "个") && (c[i - 2] == "幾" || c[i - 2] == "几")
            let afterAlnum = i > 0 && c[i - 1].isASCII && (c[i - 1].isLetter || c[i - 1].isNumber)
            guard j < c.count, atClauseStart || afterHan || afterCountIntro || afterAlnum else { return nil }
            var m = Marker(family: .ordinal, number: n, strong: false, start: i, end: j)
            if let word = strongWords.first(where: { hasPrefix(c, j, $0) }) {
                m.strong = true
                m.end = j + word.count
            } else if c[j] == "個" || c[j] == "个" {
                guard j + 1 < c.count else { return nil }
                if fillerOrPunct(c, j + 1) {
                    m.end = j + 1
                } else if isHan(c[j + 1]), !excludedAfterOrdinal.contains(c[j + 1]) {
                    m.end = j + 1
                    m.weak = true
                } else {
                    return nil
                }
            } else if keptMeasures.contains(c[j]) {
                m.end = j + 1
                m.weak = true
                m.keepsText = true
            } else if c[j] == "是" || hasPrefix(c, j, "就是") {
                guard !(c[j] == "是" && j + 1 < c.count && "否非不".contains(c[j + 1])) else { return nil }
            } else if c[j] == "呢" || markerPunct.contains(c[j]) {
            } else if isHan(c[j]), !excludedAfterOrdinal.contains(c[j]) {
                m.weak = true
            } else if j + 1 < c.count, ordinalWordExceptions.contains(String(c[j...(j + 1)])) {
                m.weak = true
            } else {
                return nil
            }
            return m
        }
        if atClauseStart || afterHan || (i > 0 && !c[i - 1].isLetter) {
            if let m = sequenceMarker(c, at: i) { return m }
        }
        if afterHan, !atClauseStart, let m = countedMarker(c, at: i), m.family == .lai, m.number >= 2 { return m }
        if let m = bareDigitMarker(c, at: i) { return m }
        guard atClauseStart else { return nil }
        if let m = pairMarker(c, at: i) { return m }
        if let m = countedMarker(c, at: i) { return m }
        if let (n, len) = number(c, i), i + len < c.count {
            let p = c[i + len]
            if p == "、" || (c[i].isASCII && (p == "." || p == "。") && i + len + 1 < c.count
                             && !sentenceEnders.contains(c[i + len + 1]) && !(c[i + len + 1].isASCII && c[i + len + 1].isNumber)) {
                return Marker(family: .enumeration, number: n, strong: false, start: i, end: i + len + 1)
            }
        }
        return nil
    }

    private static func sequenceMarker(_ c: [Character], at i: Int) -> Marker? {
        for (word, n) in sequenceWords where hasPrefix(c, i, word) {
            var end = i + word.count
            if n == -1 {
                for tail in ["一點", "一点", "一個", "一个", "一項", "一项"] where hasPrefix(c, end, tail) {
                    end += tail.count
                    break
                }
            }
            return Marker(family: .sequence, number: n, strong: false, start: i, end: end)
        }
        return nil
    }

    private static func pairMarker(_ c: [Character], at i: Int) -> Marker? {
        for (prefix, n) in pairPrefixes where hasPrefix(c, i, prefix) {
            let end = i + prefix.count
            guard end < c.count else { return nil }
            let shi = hasPrefix(c, end, "就是")
                || (c[end] == "是" && !(end + 1 < c.count && "否非不".contains(c[end + 1])))
            guard shi else { return nil }
            return Marker(family: .pair, number: n, strong: false, start: i, end: end)
        }
        return nil
    }

    private static func countedMarker(_ c: [Character], at i: Int) -> Marker? {
        if c[i] == "其", let (n, len) = number(c, i + 1), !c[i + 1].isASCII {
            let end = i + 1 + len
            guard end < c.count else { return nil }
            return Marker(family: .qi, number: n, strong: false, start: i, end: end)
        }
        if let n = laiNumbers[c[i]], i + 2 < c.count, c[i + 1] == "來" || c[i + 1] == "来" {
            return Marker(family: .lai, number: n, strong: false, start: i, end: i + 2)
        }
        return nil
    }

    private static func bareDigitMarker(_ c: [Character], at i: Int) -> Marker? {
        guard c[i].isASCII, c[i].isNumber, let (n, len) = number(c, i), len == 1 else { return nil }
        var b = i
        while b > 0, c[b - 1] == " " { b -= 1 }
        if b > 0 {
            let p = c[b - 1]
            let afterWord = isHan(p) && !digitBlockedBefore.contains(p)
            let afterEnglishWord = b < i && n >= 2 && p.isASCII && p.isLetter
            guard afterWord || afterEnglishWord || digitLeadPunct.contains(p) else { return nil }
        }
        let glued = b == i && b > 0 && isHan(c[b - 1])
        var k = i + len
        if k < c.count, c[k] == " " { k += 1 }
        guard k < c.count else { return nil }
        var content = k
        if c[k] == "，" || c[k] == "：" {
            guard !glued else { return nil }
            content = k + 1
            while content < c.count, c[content] == " " { content += 1 }
            guard content < c.count else { return nil }
        }
        guard isHan(c[content]), !digitFollowersNotItem.contains(c[content]) else { return nil }
        if digitConnectives.contains(c[content]) {
            var d = content + 1
            while d < c.count, c[d] == " " { d += 1 }
            if d < c.count, c[d].isASCII, c[d].isNumber { return nil }
        }
        return Marker(family: .enumeration, number: n, strong: false, start: i, end: k, bareDigit: true)
    }

    struct AnnouncedList {
        var introEnd: Int
        var items: [String]
        var end: Int
        var restStart: Int
    }

    static func announcedList(_ c: [Character]) -> AnnouncedList? {
        var i = 0
        while i < c.count {
            if let found = announcedList(c, countAt: i) { return found }
            i += 1
        }
        return nil
    }

    private static func announcedList(_ c: [Character], countAt i: Int) -> AnnouncedList? {
        guard let (n, introEnd) = announcedIntro(c, countAt: i) else { return nil }

        var start = introEnd
        while start < c.count, c[start] == " " { start += 1 }
        if start < c.count, c[start] == "：" || c[start] == "，" {
            start += 1
        } else if !announcedLeads.contains(where: { hasPrefix(c, start, $0) }) {
            return nil
        }
        while start < c.count, c[start] == " " { start += 1 }
        if let lead = announcedLeads.first(where: { hasPrefix(c, start, $0) }) { start += lead.count }

        var end = start
        while end < c.count, !sentenceEnders.contains(c[end]) { end += 1 }
        let region = Array(c[start..<end])
        guard !region.contains(where: { "；：,;:".contains($0) }) else { return nil }
        let hasDun = region.contains("、"), hasComma = region.contains("，")
        guard !(hasDun && hasComma) else { return nil }
        let separator: Character = hasComma ? "，" : "、"

        var items = region.split(separator: separator, omittingEmptySubsequences: false).map(trimmedItem)
        if n >= 3, items.count == n - 1, let last = items.last, let (left, right) = splitAtConnective(last) {
            items[items.count - 1] = left
            items.append(right)
        }
        guard items.count == n else { return nil }
        items = items.map(droppingLeadingConnective)
        guard items.allSatisfy({ !$0.isEmpty }) else { return nil }
        guard !items.contains(where: { item in item.indices.contains { announcedIntro(item, countAt: $0) != nil } })
        else { return nil }
        let limit = hasComma ? announcedCommaItemMax : announcedDunItemMax
        guard items.allSatisfy({ $0.count <= limit }) else { return nil }
        let longestOther = items.dropLast().map(\.count).max() ?? 0
        guard items[items.count - 1].count <= max(2 * longestOther, announcedLastItemFloor) else { return nil }

        var restStart = end
        if end < c.count {
            if c[end] != "。" { items[items.count - 1].append(c[end]) }
            restStart = end + 1
        }
        return AnnouncedList(introEnd: introEnd, items: items.map { String($0) }, end: end, restStart: restStart)
    }

    private static func announcedIntro(_ c: [Character], countAt i: Int) -> (Int, Int)? {
        var b = i
        while b > 0, c[b - 1] == " " { b -= 1 }
        if b > 0, c[b - 1] == "第" || chineseNumerals.contains(c[b - 1]) || (c[b - 1].isASCII && c[b - 1].isNumber) {
            return nil
        }
        let n: Int
        var j: Int
        if c[i] == "兩" || c[i] == "两" {
            (n, j) = (2, i + 1)
        } else if let (v, len) = number(c, i) {
            (n, j) = (v, i + len)
        } else {
            return nil
        }
        guard (2...maxAnnouncedCount).contains(n) else { return nil }
        if c[i].isASCII { while j < c.count, c[j] == " " { j += 1 } }

        if let word = announcedNouns.first(where: { hasPrefix(c, j, $0) }) {
            j += word.count
        } else if announcedMeasures.contains(where: { hasPrefix(c, j, $0) }),
                  announcedVerbs.contains(where: { b >= $0.count && hasPrefix(c, b - $0.count, $0) }) {
            j += 1
        } else {
            return nil
        }
        return (n, j)
    }

    private static func trimmedItem(_ s: ArraySlice<Character>) -> [Character] {
        var a = Array(s)
        while let f = a.first, f == " " { a.removeFirst() }
        while let l = a.last, l == " " { a.removeLast() }
        return a
    }

    private static func splitAtConnective(_ s: [Character]) -> ([Character], [Character])? {
        var hits: [(Int, Int)] = []
        var k = 0
        while k < s.count {
            if let w = listConnectives.first(where: { hasPrefix(s, k, $0) }) {
                hits.append((k, w.count))
                k += w.count
            } else {
                k += 1
            }
        }
        guard hits.count == 1, let (at, len) = hits.first else { return nil }
        guard at >= 2, s.count - (at + len) >= 2 else { return nil }
        if len == 1 {
            let conj = s[at]
            if connectiveCompounds.contains(String([s[at - 1], conj])) || connectiveCompounds.contains(String([conj, s[at + 1]])) {
                return nil
            }
        }
        return (Array(s[..<at]), Array(s[(at + len)...]))
    }

    static let connectiveCompounds: Set<String> = [
        "平和", "溫和", "温和", "暖和", "緩和", "缓和", "柔和", "祥和", "總和", "总和", "調和", "调和", "附和", "謙和", "谦和",
        "隨和", "随和", "講和", "讲和", "求和", "共和", "飽和", "饱和", "中和", "人和", "議和", "议和",
        "和平", "和諧", "和谐", "和藹", "和蔼", "和氣", "和气", "和好", "和解", "和尚", "和睦", "和煦", "和善", "和約", "和约",
        "和弦", "和局", "和棋", "和風", "和风", "和服", "和牛", "和聲", "和声",
        "腳跟", "脚跟", "高跟", "後跟", "后跟", "跟蹤", "跟踪", "跟隨", "跟随", "跟進", "跟进", "跟前", "跟班", "跟頭", "跟头", "跟風", "跟风",
        "參與", "参与", "給與", "给与", "賦與", "赋与", "授與", "授与", "與會", "与会", "與其", "与其", "與否", "与否", "與日", "与日",
        "普及", "涉及", "顧及", "顾及", "波及", "危及", "觸及", "触及", "企及", "遍及", "推及", "論及", "论及", "提及", "不及", "以及",
        "及時", "及时", "及格", "及早", "及至",
        "或許", "或许", "或多", "抑或", "或然", "間或", "间或", "或缺",
    ]

    private static func droppingLeadingConnective(_ s: [Character]) -> [Character] {
        for w in ["以及", "還有", "还有"] where hasPrefix(s, 0, w) && s.count > w.count {
            return Array(s[w.count...])
        }
        return s
    }

    static func number(_ c: [Character], _ i: Int) -> (Int, Int)? {
        guard i < c.count else { return nil }
        if let d = c[i].wholeNumberValue, c[i].isASCII {
            if i + 1 < c.count, c[i + 1].isASCII, let d2 = c[i + 1].wholeNumberValue {
                if i + 2 < c.count, c[i + 2].isASCII, c[i + 2].isNumber { return nil }
                return d * 10 + d2 > 0 ? (d * 10 + d2, 2) : nil
            }
            return d > 0 ? (d, 1) : nil
        }
        let digits: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
                                        "六": 6, "七": 7, "八": 8, "九": 9]
        var j = i
        var tens = 0
        if let d = digits[c[j]] {
            j += 1
            guard j < c.count, c[j] == "十" else { return (d, 1) }
            tens = d
        }
        guard j < c.count, c[j] == "十" else { return nil }
        j += 1
        let value = max(tens, 1) * 10
        if j < c.count, let u = digits[c[j]] { return (value + u, j + 1 - i) }
        return (value, j - i)
    }

    static func skipFiller(_ c: [Character], _ start: Int) -> Int {
        var i = start
        func skipPunct() { while i < c.count, markerPunct.contains(c[i]) || c[i] == " " { i += 1 } }
        skipPunct()
        if i < c.count, c[i] == "呢" { i += 1; skipPunct() }
        if hasPrefix(c, i, "就是") {
            i += 2
        } else if i + 1 < c.count, c[i] == "是", !"否非不".contains(c[i + 1]) {
            i += 1
        }
        skipPunct()
        return i
    }

    private static func fillerOrPunct(_ c: [Character], _ i: Int) -> Bool {
        markerPunct.contains(c[i]) || c[i] == "是" || c[i] == "呢" || hasPrefix(c, i, "就是")
    }

    private static func hasPrefix(_ c: [Character], _ i: Int, _ word: String) -> Bool {
        let w = Array(word)
        return i + w.count <= c.count && Array(c[i..<(i + w.count)]) == w
    }

    private static func isHan(_ c: Character) -> Bool { TranscriptFormatter.isHan(c) }

    private static let strongWords = ["件事情", "個問題", "个问题", "個部分", "个部分", "個方面", "个方面", "件事",
                                      "部分", "方面", "點", "点", "項", "项", "條", "条", "步"]
    private static let excludedAfterOrdinal: Set<Character> = [
        "次", "名", "天", "年", "月", "日", "週", "周", "位", "屆", "届", "輪", "轮", "回", "季", "期", "級", "级",
        "號", "号", "樓", "楼", "層", "层", "代", "任", "頁", "页", "章", "節", "节", "人", "個", "个", "版", "眼",
        "手", "時", "时", "線", "线", "排", "場", "场", "局", "集", "課", "课", "題", "题", "句", "段", "行", "列",
    ]
    static let ordinalWordExceptions: Set<String> = [
        "排程", "排序", "排版", "行動", "行动", "行銷", "行销", "場景", "场景", "時程", "时程",
        "名單", "名单", "名稱", "名称", "位置", "版本", "版面", "手機", "手机", "號碼", "号码",
        "人員", "人员", "人力", "回覆", "回复", "回饋", "回馈", "段落", "頁面", "页面", "列表", "任務", "任务",
    ]
    private static let digitBlockedBefore: Set<Character> = ["第", "週", "周", "期", "每", "約", "约", "共", "號", "号"]
    private static let digitLeadPunct: Set<Character> = ["，", "。", "；", "：", "！", "？", "、", ",", ";", "!", "?", "\u{3000}"]
    private static let digitFollowersNotItem: Set<Character> = [
        "個", "个", "位", "名", "次", "回", "遍", "趟", "件", "張", "张", "份", "本", "篇", "封", "則", "则", "首", "幅",
        "頁", "页", "章", "節", "节", "題", "题", "行", "列", "排", "條", "条", "項", "项", "組", "组", "套", "雙", "双",
        "支", "台", "臺", "部", "輛", "辆", "隻", "顆", "颗", "粒", "根", "塊", "块", "片", "種", "种",
        "類", "类", "款", "間", "间", "家", "座", "棟", "栋", "戶", "户", "口", "人", "杯", "瓶", "碗", "盤", "盘", "包",
        "盒", "箱", "罐", "票", "筆", "笔", "枚", "圈", "步", "局", "場", "场", "輪", "轮", "集", "季", "期", "級", "级",
        "屆", "届", "代", "版", "度", "隊", "队", "樣", "样",
        "點", "点", "時", "时", "分", "秒", "天", "日", "號", "号", "週", "周", "月", "年", "歲", "岁", "晚", "夜", "星",
        "樓", "楼", "層", "层", "元", "角", "毛", "萬", "万", "千", "百", "億", "亿", "倍", "成", "折", "克", "斤",
        "米", "尺", "寸", "里", "歐", "欧", "美", "小", "多", "幾", "几",
    ]
    private static let digitConnectives: Set<Character> = [
        "到", "至", "跟", "和", "與", "与", "及", "或", "比", "加", "減", "减", "乘", "除", "對", "对",
    ]
    private static let keptMeasures: Set<Character> = [
        "張", "张", "份", "本", "封", "篇", "幅", "則", "则", "塊", "块", "片", "款", "種", "种", "類", "类",
        "組", "组", "台", "臺", "支", "部", "首", "道", "間", "间", "家", "顆", "颗",
        "件",
    ]
    private static let markerPunct: Set<Character> = ["，", "、", "：", ",", ":"]
    private static let clauseBreaks: Set<Character> = ["，", "。", "；", "：", "！", "？", "、", " ", "\u{3000}",
                                                       ",", ".", ";", ":", "!", "?"]
    private static let sentenceEnders: Set<Character> = ["。", "？", "！"]
    private static let trailingTrim: Set<Character> = ["，", "、", "；", "：", "。", ",", ";", ":", " "]
    private static let introJoiners: Set<Character> = ["，", "、", "；", "：", ",", ";", ":"]
    private static let attachers: Set<Character> = ["的", "是", "這", "这", "那", "在", "了", "個", "个"]
    private static let trailingConnectives = ["以及", "還有", "还有", "而且", "另外", "然後", "然后"]
    private static let pairPrefixes: [(String, Int)] = [
        ("另外一個", 0), ("另外一个", 0), ("還有一個", 0), ("还有一个", 0), ("另一個", 0), ("另一个", 0),
        ("一個", 1), ("一个", 1),
    ]
    static let maxAnnouncedCount = 10
    static let announcedCommaItemMax = 12
    static let announcedDunItemMax = 20
    static let announcedLastItemFloor = 4
    private static let chineseNumerals: Set<Character> = ["零", "一", "二", "兩", "两", "三", "四", "五", "六", "七",
                                                          "八", "九", "十", "百", "千", "萬", "万", "幾", "几"]
    private static let announcedNouns = [
        "件事情", "件事", "個問題", "个问题", "個重點", "个重点", "個要點", "个要点", "個原因", "个原因",
        "個理由", "个理由", "個部分", "个部分", "個方面", "个方面", "個步驟", "个步骤", "個階段", "个阶段",
        "個選項", "个选项", "個選擇", "个选择", "個建議", "个建议", "個目標", "个目标", "個原則", "个原则",
        "個條件", "个条件", "個優點", "个优点", "個缺點", "个缺点", "個好處", "个好处", "個壞處", "个坏处",
        "個地方", "个地方", "個方法", "个方法", "個辦法", "个办法", "個東西", "个东西", "個功能", "个功能",
        "樣東西", "样东西", "種方法", "种方法", "種方式", "种方式", "大點", "大点", "部分", "方面", "步驟", "步骤",
    ]
    private static let announcedMeasures = ["個", "个", "點", "点", "項", "项", "樣", "样", "種", "种",
                                            "類", "类", "步", "條", "条"]
    private static let announcedVerbs = ["有", "分成", "分為", "分为", "包括", "包含"]
    private static let announcedLeads = ["分別是", "分别是", "就是"]
    private static let listConnectives = ["以及", "還有", "还有", "或是", "或者", "和", "跟", "與", "与", "及", "或"]
    private static let laiNumbers: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
                                                       "六": 6, "七": 7, "八": 8, "九": 9]
    private static let sequenceWords: [(String, Int)] = [
        ("首先", 1), ("其次", 0), ("再來", 0), ("再来", 0), ("然後", 0), ("然后", 0), ("接著", 0), ("接着", 0),
        ("最後", -1), ("最后", -1),
    ]
}

extension SpokenList {
    static let looseMinItemUnits = 4

    struct LooseMarker: Equatable {
        var number: Int
        var start: Int
        var end: Int
        var follower: Character?
    }

    private static let looseListFollowers: Set<Character> = [
        "點", "点", "項", "项", "條", "条", "步", "個", "个", "是",
        "，", "、", "：", "。", "；", ",", ":", ";", " ",
    ]
    private static let looseStrippedMeasures: Set<Character> = ["點", "点", "項", "项", "條", "条", "步", "個", "个"]
    private static let looseEnglish: [(String, Int)] = [
        ("first", 1), ("second", 2), ("third", 3), ("fourth", 4), ("fifth", 5),
        ("1st", 1), ("2nd", 2), ("3rd", 3), ("4th", 4), ("5th", 5),
    ]

    static func looseCandidates(_ c: [Character]) -> [LooseMarker] {
        var out: [LooseMarker] = []
        var i = 0
        while i < c.count {
            if c[i] == "第", i + 1 < c.count, let n = looseDigit(c[i + 1]),
               !(i + 2 < c.count && (c[i + 2] == "十" || (c[i + 2].isASCII && c[i + 2].isNumber))) {
                var end = i + 2
                let follower: Character? = end < c.count ? c[end] : nil
                if let f = follower, looseStrippedMeasures.contains(f) { end += 1 }
                out.append(LooseMarker(number: n, start: i, end: end, follower: follower))
                i = end
                continue
            }
            let lower = c[i].isASCII ? String(c[i..<min(c.count, i + 6)]).lowercased() : ""
            let afterLetter = i > 0 && c[i - 1].isASCII && c[i - 1].isLetter
            if !lower.isEmpty, !afterLetter,
               let (word, n) = looseEnglish.first(where: { lower.hasPrefix($0.0) }) {
                let end = i + word.count
                if end >= c.count || !(c[end].isASCII && c[end].isLetter) {
                    out.append(LooseMarker(number: n, start: i, end: end, follower: end < c.count ? c[end] : nil))
                    i = end
                    continue
                }
            }
            if c[i].isASCII, let d = c[i].wholeNumberValue, d >= 1, d <= 9,
               !(i > 0 && c[i - 1].isASCII && (c[i - 1].isLetter || c[i - 1].isNumber || ".,".contains(c[i - 1]))),
               !(i + 1 < c.count && c[i + 1].isASCII && (c[i + 1].isNumber || c[i + 1].isLetter)) {
                var k = i + 1
                while k < c.count, c[k] == " " { k += 1 }
                if k < c.count, !digitFollowersNotItem.contains(c[k]), !":：/.%％".contains(c[k]) {
                    out.append(LooseMarker(number: d, start: i, end: i + 1, follower: c[k]))
                }
            }
            i += 1
        }
        return out
    }

    private static func looseDigit(_ ch: Character) -> Int? {
        let digits: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let d = digits[ch] { return d }
        if ch.isASCII, let d = ch.wholeNumberValue, d >= 1, d <= 9 { return d }
        return nil
    }

    static func looseRun(_ cands: [LooseMarker]) -> [LooseMarker]? {
        var best: [LooseMarker] = []
        for (i, first) in cands.enumerated() where first.number == 1 || first.number == 2 {
            var run = [first]
            for m in cands[(i + 1)...] where m.number == first.number + run.count {
                run.append(m)
            }
            if run.count >= 2, run.count > best.count { best = run }
        }
        return best.isEmpty ? nil : best
    }

    static func looseBlocks(_ paragraph: String) -> [(text: String, isItem: Bool)]? {
        let c = Array(paragraph)
        guard let run = looseRun(looseCandidates(c)) else { return nil }
        let followers = run.map(\.follower)
        if let f = followers[0], followers.allSatisfy({ $0 == f }), !looseListFollowers.contains(f) { return nil }

        var items: [String] = []
        var introEnd = run[0].start
        if run[0].number == 2 {
            var s = run[0].start
            while s > 0, !sentenceEnders.contains(c[s - 1]) { s -= 1 }
            introEnd = s
            var to = run[0].start
            while to > s, trailingTrim.contains(c[to - 1]) { to -= 1 }
            items.append(String(c[s..<to]))
        }
        var restStart = c.count
        for (k, m) in run.enumerated() {
            let from = skipFiller(c, m.end)
            var to: Int
            var keep = ""
            if k + 1 < run.count {
                to = run[k + 1].start
            } else {
                to = from
                while to < c.count, !sentenceEnders.contains(c[to]) { to += 1 }
                restStart = min(to + 1, c.count)
                if to < c.count, c[to] != "。" { keep = String(c[to]) }
            }
            while to > from, trailingTrim.contains(c[to - 1]) { to -= 1 }
            if k + 1 < run.count {
                for word in trailingConnectives where to - from > word.count
                    && String(c[(to - word.count)..<to]) == word {
                    to -= word.count
                    while to > from, trailingTrim.contains(c[to - 1]) { to -= 1 }
                    break
                }
            }
            guard to > from else { return nil }
            items.append(String(c[from..<to]) + keep)
        }
        guard items.dropLast().allSatisfy({ TranscriptFormatter.countUnits($0) >= looseMinItemUnits }) else { return nil }
        return layout(c, introEnd: introEnd, items: items, restStart: restStart)
    }
}
