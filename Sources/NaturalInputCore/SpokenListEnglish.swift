import Foundation

extension SpokenList {
    static func englishMarker(_ c: [Character], at i: Int) -> Marker? {
        guard i < c.count, c[i].isASCII, c[i].isLetter else { return nil }
        if i > 0, isWordChar(c[i - 1]) { return nil }
        let (word, wordEnd) = readWord(c, i)
        guard wordEnd < c.count, !isWordChar(c[wordEnd]) else { return nil }

        var k = i - 1
        while k >= 0, c[k] == " " { k -= 1 }
        let atClauseStart = k < 0 || englishClauseBreaks.contains(c[k]) || TranscriptFormatter.isHan(c[k])
        if !atClauseStart {
            guard c[k].isASCII, c[k].isLetter else { return nil }
            var s = k
            while s > 0, c[s - 1].isASCII, c[s - 1].isLetter { s -= 1 }
            guard !blockedBeforeEnglishMarker.contains(String(c[s...k]).lowercased()) else { return nil }
        }

        if word == "number" {
            var j = wordEnd
            guard j < c.count, c[j] == " " else { return nil }
            while j < c.count, c[j] == " " { j += 1 }
            let n: Int, end: Int
            if let (v, len) = number(c, j), c[j].isASCII {
                (n, end) = (v, j + len)
            } else {
                let (w, e) = readWord(c, j)
                guard let v = englishCardinals[w] else { return nil }
                (n, end) = (v, e)
            }
            guard end < c.count, !isWordChar(c[end]), hasContent(c, after: end) else { return nil }
            if !atClauseStart, nextWord(c, after: end) == nil { return nil }
            return Marker(family: .englishNumber, weak: !atClauseStart, number: n, strong: false, start: i, end: end)
        }

        if let n = englishOrdinals[word] {
            guard hasContent(c, after: wordEnd) else { return nil }
            var end = wordEnd
            if let (next, nextEnd) = nextWord(c, after: wordEnd) {
                if n == 1, next == "of", let (all, allEnd) = nextWord(c, after: nextEnd), all == "all" {
                    end = allEnd
                } else if next == "one", hasContent(c, after: nextEnd) {
                    end = nextEnd
                } else if excludedAfterEnglishOrdinal.contains(next) {
                    return nil
                }
            }
            if !atClauseStart, nextWord(c, after: end) == nil { return nil }
            return Marker(family: .english, weak: !atClauseStart, number: n, strong: false, start: i, end: end)
        }

        if word == "finally" || word == "lastly", atClauseStart {
            var j = wordEnd
            while j < c.count, c[j] == " " { j += 1 }
            guard j < c.count, ",:，：".contains(c[j]), hasContent(c, after: j + 1) else { return nil }
            return Marker(family: .english, number: -1, strong: false, start: i, end: wordEnd)
        }
        return nil
    }

    static func englishSkipFiller(_ c: [Character], _ start: Int, dropsIs: Bool = true) -> Int {
        var i = start
        func skipPunct() { while i < c.count, ",:，：、 -".contains(c[i]) { i += 1 } }
        skipPunct()
        if dropsIs, let (w, e) = nextWord(c, after: i), w == "is",
           e < c.count, c[e] == " ", hasContent(c, after: e) {
            i = e
            skipPunct()
        }
        return i
    }

    static func englishTrimEnd(_ c: [Character], from: Int, to: Int) -> Int {
        var to = to
        func trim() { while to > from, ",;:，；：。 ".contains(c[to - 1]) || (c[to - 1] == "." && !TranscriptFormatter.isProtected(c, to - 1)) { to -= 1 } }
        trim()
        for phrase in englishTrailingConnectives {
            let p = Array(phrase)
            let s = to - p.count
            guard s > from, String(c[s..<to]).lowercased() == phrase, !isWordChar(c[s - 1]) else { continue }
            to = s
            trim()
            break
        }
        return to
    }

    static func englishSentenceEnd(_ c: [Character], from: Int) -> Int {
        var to = from
        while to < c.count {
            if "。？！?!".contains(c[to]) { break }
            if c[to] == ".", !TranscriptFormatter.isProtected(c, to) { break }
            to += 1
        }
        return to
    }

    private static func isWordChar(_ ch: Character) -> Bool {
        (ch.isASCII && (ch.isLetter || ch.isNumber)) || ch == "'" || ch == "-" || ch == "’"
    }

    private static func readWord(_ c: [Character], _ i: Int) -> (String, Int) {
        var j = i
        while j < c.count, c[j].isASCII, c[j].isLetter { j += 1 }
        return (String(c[i..<j]).lowercased(), j)
    }

    private static func nextWord(_ c: [Character], after i: Int) -> (String, Int)? {
        var j = i
        while j < c.count, c[j] == " " { j += 1 }
        guard j < c.count, c[j].isASCII, c[j].isLetter else { return nil }
        let (w, e) = readWord(c, j)
        guard e >= c.count || !isWordChar(c[e]) else { return nil }
        return (w, e)
    }

    private static func hasContent(_ c: [Character], after i: Int) -> Bool {
        c[min(i, c.count)...].contains { !",:;.，：；。 ".contains($0) }
    }

    private static let englishOrdinals: [String: Int] = [
        "first": 1, "firstly": 1, "second": 2, "secondly": 2, "third": 3, "thirdly": 3,
        "fourth": 4, "fourthly": 4, "fifth": 5, "fifthly": 5, "sixth": 6, "seventh": 7,
        "eighth": 8, "ninth": 9, "tenth": 10,
    ]
    private static let englishCardinals: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
    ]
    private static let englishClauseBreaks: Set<Character> = [
        ",", ".", ";", ":", "!", "?", "，", "。", "；", "：", "！", "？", "、", "(", "（", "\"", "“",
    ]
    private static let blockedBeforeEnglishMarker: Set<String> = [
        "a", "an", "the", "my", "your", "his", "her", "its", "our", "their", "this", "that", "these", "those",
        "every", "each", "at", "in", "on", "for", "from", "of", "to", "by", "per", "come", "came", "comes",
        "finish", "finished", "finishes", "rank", "ranked", "ranks", "place", "placed", "just", "only", "very",
        "wait", "hold",
        "is", "was", "are", "were", "be", "been", "being", "am", "got", "get", "gets", "took", "take", "takes",
        "end", "ended", "ends", "won", "win", "wins", "came", "finishing", "ranking", "placing", "landed",
    ]
    private static let excludedAfterEnglishOrdinal: Set<String> = [
        "time", "times", "place", "half", "hand", "class", "floor", "name", "names", "rate", "aid", "lady",
        "grade", "person", "world", "date", "round", "base", "degree", "cousin", "nature", "guess", "glance",
        "sight", "language", "generation", "season", "episode", "day", "week", "month", "year", "quarter",
        "and", "or", "of", "to", "ago", "was", "were", "went", "goes", "came", "prize", "later", "thing", "things", "ones", "choice", "row", "draft", "version", "chance", "opinion", "thought", "thoughts",
    ]
    private static let englishTrailingConnectives = ["and then", "and also", "and", "then", "also", "plus"]
}
