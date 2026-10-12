import Foundation

public enum EnglishFormatting {
    public static func apply(_ text: String, capitalizeStart: Bool = true) -> String {
        capitalizeSentenceStarts(abbreviateVersus(percentSign(joinAmPm(text))), capitalizeStart: capitalizeStart)
    }

    static func percentSign(_ text: String) -> String {
        guard let regex = percentRegex, !text.isEmpty else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1%")
    }

    private static let percentRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_])(?<![A-Za-z0-9_][.,])(\d+(?:[.,]\d+)*)[ \t]*percent(?![A-Za-z0-9_])"#,
        options: [.caseInsensitive])

    static func abbreviateVersus(_ text: String) -> String {
        guard text.contains("versus"), text.contains(where: TranscriptFormatter.isHan) else { return text }
        let chars = Array(text)
        var out = String()
        var i = 0
        let word = Array("versus")
        func isWordChar(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "_") }
        func neighbour(_ from: Int, step: Int) -> Character? {
            var j = from
            while j >= 0, j < chars.count {
                if chars[j] != " " && chars[j] != "\t" { return chars[j] }
                j += step
            }
            return nil
        }
        func qualifies(_ c: Character?) -> Bool {
            guard let c else { return false }
            return TranscriptFormatter.isCJK(c) || (c.isASCII && c.isNumber)
        }
        while i < chars.count {
            if chars[i] == "v", i + word.count <= chars.count, Array(chars[i..<i + word.count]) == word,
               i == 0 || !isWordChar(chars[i - 1]),
               i + word.count == chars.count || !isWordChar(chars[i + word.count]),
               qualifies(neighbour(i - 1, step: -1)) || qualifies(neighbour(i + word.count, step: 1)) {
                out += "vs"
                i += word.count
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out
    }

    static func joinAmPm(_ text: String) -> String {
        guard let regex = amPmRegex, !text.isEmpty else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1 $2")
    }

    private static let amPmRegex = try? NSRegularExpression(
        pattern: #"(\d)\.\s*([ap]m)\b"#, options: [.caseInsensitive])

    private static let sentenceEnders: Set<Character> = [".", "?", "!", "。", "？", "！"]

    private static let wordTerminators: Set<Character> = [
        " ", "\n", "\t", ",", "!", "?", ";", ":", "\"", "'", ")", "]", "}",
        "，", "。", "！", "？", "；", "：", "、", "“", "”", "‘", "’", "（", "）", "「", "」", "『", "』",
    ]

    static func capitalizeSentenceStarts(_ text: String, capitalizeStart: Bool = true) -> String {
        guard !text.isEmpty else { return text }
        var chars = Array(text)

        if capitalizeStart, let range = eligibleWordRange(chars, at: 0) {
            uppercaseFirst(&chars, at: range.lowerBound)
        }

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if sentenceEnders.contains(c), isGenuineSentenceEnd(chars, i) {
                var j = i + 1
                while j < chars.count, chars[j] == " " { j += 1 }
                if let range = eligibleWordRange(chars, at: j) {
                    uppercaseFirst(&chars, at: range.lowerBound)
                }
            }
            i += 1
        }
        return String(chars)
    }

    private static func isGenuineSentenceEnd(_ chars: [Character], _ i: Int) -> Bool {
        let c = chars[i]
        if c == "。" || c == "？" || c == "！" { return true }
        return !TranscriptFormatter.isProtected(chars, i)
    }

    private static func eligibleWordRange(_ chars: [Character], at start: Int) -> Range<Int>? {
        guard start < chars.count, isLowercaseASCIILetter(chars[start]) else { return nil }
        var end = start
        while end < chars.count, isLowercaseASCIILetter(chars[end]) { end += 1 }
        guard end < chars.count else { return start..<end }
        let next = chars[end]
        if next == "." {
            return isGenuineSentenceEnd(chars, end) ? start..<end : nil
        }
        return wordTerminators.contains(next) ? start..<end : nil
    }

    private static func uppercaseFirst(_ chars: inout [Character], at index: Int) {
        chars[index] = Character(chars[index].uppercased())
    }

    private static func isLowercaseASCIILetter(_ c: Character) -> Bool {
        c.isASCII && c.isLowercase && c.isLetter
    }
}
