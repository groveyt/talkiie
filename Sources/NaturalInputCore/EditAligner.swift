import Foundation

public enum EditAligner {
    public static let minimumAlignedFraction = 0.5
    public static let maximumInsertedCharacters = 3_000

    public struct Result: Equatable, Sendable {
        public let edited: String
        public let alignedCharacters: Int
        public let insertedCharacters: Int
        public let windowRange: Range<Int>

        public var alignedPercent: Int {
            insertedCharacters == 0 ? 0 : alignedCharacters * 100 / insertedCharacters
        }
    }

    public static func align(inserted: String, window: String, insertionOffsetUTF16: Int) -> Result? {
        let a = Array(inserted), w = Array(window)
        let m = a.count, n = w.count
        guard m > 0, n > 0, m <= maximumInsertedCharacters else { return nil }

        let width = n + 1
        var ops = [UInt8](repeating: 0, count: (m + 1) * width)
        var prev = [Int32](repeating: 0, count: width)
        var cur = [Int32](repeating: 0, count: width)
        for i in 1...m {
            cur[0] = Int32(i)
            ops[i * width] = Op.deleteInserted
            let ai = a[i - 1]
            for j in 1...n {
                let isMatch = ai == w[j - 1]
                let diag = prev[j - 1] + (isMatch ? 0 : 1)
                let up = prev[j] + 1
                let left = cur[j - 1] + 1
                var best = diag, op = isMatch ? Op.match : Op.substitute
                if up < best || (up == best && op == Op.substitute) { best = up; op = Op.deleteInserted }
                if left < best || (left == best && op == Op.substitute) { best = left; op = Op.insertTyped }
                cur[j] = best
                ops[i * width + j] = op
            }
            swap(&prev, &cur)
        }

        let expectedEnd = characterOffset(ofUTF16: insertionOffsetUTF16, in: w) + m
        var end = 1
        for j in 1...n {
            let c = prev[j], b = prev[end]
            if c < b || (c == b && abs(j - expectedEnd) < abs(end - expectedEnd)) { end = j }
        }

        var i = m, j = end
        var firstMatch: Int? = nil, lastMatch: Int? = nil, matches = 0
        while i > 0 {
            switch ops[i * width + j] {
            case Op.match:
                matches += 1
                if lastMatch == nil { lastMatch = j - 1 }
                firstMatch = j - 1
                i -= 1; j -= 1
            case Op.substitute:
                i -= 1; j -= 1
            case Op.deleteInserted:
                i -= 1
            default:
                j -= 1
            }
        }
        guard let first = firstMatch, let last = lastMatch,
              Double(matches) >= Double(m) * minimumAlignedFraction else { return nil }
        return Result(edited: String(w[first...last]), alignedCharacters: matches, insertedCharacters: m,
                      windowRange: first..<(last + 1))
    }

    private enum Op {
        static let match: UInt8 = 1
        static let substitute: UInt8 = 2
        static let deleteInserted: UInt8 = 3
        static let insertTyped: UInt8 = 4
    }

    static func characterOffset(ofUTF16 offset: Int, in chars: [Character]) -> Int {
        guard offset > 0 else { return 0 }
        var units = 0
        for (k, c) in chars.enumerated() {
            if units >= offset { return k }
            units += c.utf16.count
        }
        return chars.count
    }
}
