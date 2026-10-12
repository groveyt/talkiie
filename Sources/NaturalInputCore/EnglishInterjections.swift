import Foundation

public enum EnglishInterjections {
    static let replacements: [(han: String, english: String)] = [
        ("哈哈", "Haha"), ("哇", "Wow"), ("哦", "Oh"), ("喔", "Oh"), ("哼", "Hmm"), ("嗯", "Hmm"), ("呃", "Uh"),
    ]
    public static let minLatinShare = 0.8
    public static let minEnglishWords = 2

    static func isMostlyEnglish(_ chars: [Character]) -> Bool {
        var latin = 0, han = 0, words = 0
        var inWord = false
        for c in chars {
            if c.isASCII && c.isLetter {
                latin += 1
                if !inWord { words += 1 }
                inWord = true
            } else {
                if TranscriptFormatter.isHan(c) { han += 1 }
                inWord = inWord && (c == "'" || c == "’")
            }
        }
        guard han > 0, words >= minEnglishWords else { return false }
        return Double(latin) / Double(latin + han) >= minLatinShare
    }

    private static func isStandaloneNeighbor(_ c: Character?) -> Bool {
        guard let c else { return true }
        return !(c.isLetter || c.isNumber)
    }

    public static func apply(_ text: String) -> String {
        let chars = Array(text)
        guard chars.contains(where: TranscriptFormatter.isHan), isMostlyEnglish(chars) else { return text }
        var out = ""
        var i = 0
        while i < chars.count {
            if let r = replacements.first(where: { r in
                let h = Array(r.han)
                return i + h.count <= chars.count && Array(chars[i..<(i + h.count)]) == h
            }) {
                let end = i + r.han.count
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let after: Character? = end < chars.count ? chars[end] : nil
                if isStandaloneNeighbor(before), isStandaloneNeighbor(after) {
                    out += startsSentence(out) ? r.english : r.english.lowercased()
                    i = end
                    continue
                }
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    private static func startsSentence(_ before: String) -> Bool {
        guard let last = before.last(where: { $0 != " " }) else { return true }
        return ".?!。？！\n…".contains(last)
    }
}
