import Foundation

enum HowQuestionMarks {
    static func apply(_ marks: [Int: Character], chars: [Character]) -> (marks: [Int: Character], removed: Int) {
        var out = marks
        var removed = 0
        for (p, m) in marks where m == "?" || m == "？" {
            guard p + 1 < chars.count, endsWithHowWord(chars, at: p) else { continue }
            let stop = marks.keys.filter { $0 > p }.min() ?? (chars.count - 1)
            let span = String(chars[(p + 1)...stop])
            guard span.count <= maxSpan, span.allSatisfy(isHan),
                  verdictEndings.contains(where: { span.hasSuffix($0) }) else { continue }
            out[p] = nil
            removed += 1
        }
        return (out, removed)
    }

    static func endsWithHowWord(_ chars: [Character], at p: Int) -> Bool {
        howWords.contains { w in
            let n = w.count
            guard p + 1 >= n else { return false }
            return String(chars[(p + 1 - n)...p]) == w
        }
    }

    private static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    static let maxSpan = 7
    private static let howWords = ["怎麼樣", "怎么样", "怎樣", "怎样", "怎麼", "怎么", "如何"]
    private static let verdictEndings = [
        "比較好", "比较好", "較好", "较好", "才好", "最好", "比較適合", "比较适合", "比較方便", "比较方便",
    ]
}
