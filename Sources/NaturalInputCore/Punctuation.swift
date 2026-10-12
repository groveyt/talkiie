import Foundation

public protocol Punctuator: Sendable {
    func punctuate(_ text: String) async -> PunctuationReply
}

public enum PunctuationReply: Equatable, Sendable {
    case suggestion(String)
    case failed(PunctuationFallback)
}

public enum PunctuationFallback: String, Equatable, Sendable, CaseIterable {
    case disabled
    case tooShort
    case tooLong
    case notIssued
    case tailnetDown
    case logUnavailable
    case timeout
    case network
    case badStatus
    case malformed
    case rejectedByGuard
    case invariantViolated
    case whisperEnglishList
    case pauseList
}

public struct PunctuationReport: Equatable, Sendable {
    public var applied: Bool
    public var fallback: PunctuationFallback?
    public var millis: Int?
    public var marks: Int?
    public var alignedPercent: Int?

    public init(applied: Bool, fallback: PunctuationFallback?, millis: Int? = nil,
                marks: Int? = nil, alignedPercent: Int? = nil) {
        self.applied = applied
        self.fallback = fallback
        self.millis = millis
        self.marks = marks
        self.alignedPercent = alignedPercent
    }
}

public enum PunctuationGuard {
    public static let insertable: Set<Character> = [
        "，", "。", "？", "！", "、", "；", "：", ",", ".", "?", "!", ";", ":",
    ]
    public static let minAlignedFraction = 0.9

    public struct Verdict: Equatable, Sendable {
        public var marks: [Int: Character]
        public var alignedPercent: Int
    }

    public static func marks(sent: String, output: String) -> Verdict? {
        let a = sent.filter { !$0.isWhitespace }.map { $0 }
        let b = output.filter { !$0.isWhitespace }.map { $0 }
        guard !a.isEmpty else { return nil }
        var spaceAfter = [Bool](repeating: false, count: a.count)
        var k = -1
        for c in sent {
            if c.isWhitespace { if k >= 0 { spaceAfter[k] = true } } else { k += 1 }
        }
        let maxD = min(a.count + b.count, a.count / 2 + 64)
        guard let ops = align(a, b, maxD: maxD) else { return nil }

        var matched = 0
        var raw: [Int: [Character]] = [:]
        var lastEqual: Int?
        var pending: [Character] = []
        var dirty = false
        func commit(after i: Int) {
            if !dirty, !pending.isEmpty { raw[i] = pending }
        }
        for op in ops {
            switch op {
            case .equal(let i, _):
                matched += 1
                if let last = lastEqual, last == i - 1 { commit(after: last) }
                pending = []
                dirty = false
                lastEqual = i
            case .delete:
                dirty = true
            case .insert(let j):
                if insertable.contains(b[j]) {
                    pending.append(b[j])
                } else if !isPunctuation(b[j]) {
                    dirty = true
                }
            }
        }
        if let last = lastEqual, last == a.count - 1 { commit(after: last) }

        guard Double(matched) >= Double(a.count) * minAlignedFraction else { return nil }
        var marks: [Int: Character] = [:]
        for (i, cs) in raw {
            if insertable.contains(a[i]) || (i + 1 < a.count && insertable.contains(a[i + 1])) { continue }
            let prev = a[i]
            let next: Character? = i + 1 < a.count ? a[i + 1] : nil
            if let next, isASCIIAlnum(prev), isASCIIAlnum(next), !spaceAfter[i] { continue }
            if let m = normalize(cs, prev: prev, next: next) { marks[i] = m }
        }
        return Verdict(marks: marks, alignedPercent: Int((Double(matched) * 100 / Double(a.count)).rounded(.down)))
    }

    public static func render(_ original: String, marks: [Int: Character]) -> String {
        var out = ""
        out.reserveCapacity(original.count + marks.count)
        var k = 0
        for c in original {
            out.append(c)
            guard !c.isWhitespace else { continue }
            if let m = marks[k] { out.append(m) }
            k += 1
        }
        return out
    }

    public static func preserves(original: String, result: String) -> Bool {
        let o = Array(original)
        var i = 0
        for c in result {
            if i < o.count, c == o[i] {
                i += 1
            } else if !insertable.contains(c) {
                return false
            }
        }
        return i == o.count
    }

    static func normalize(_ cs: [Character], prev: Character, next: Character?) -> Character? {
        let order: [(Set<Character>, Character)] = [
            (["？", "?"], "?"), (["。", "."], "."), (["！", "!"], "!"),
            (["；", ";"], ";"), (["：", ":"], ":"), (["，", ","], ","), (["、"], "、"),
        ]
        for (set, mark) in order where cs.contains(where: set.contains) {
            if mark == "、", isASCIIAlnum(prev), let next, isASCIIAlnum(next) { return "," }
            return mark
        }
        return nil
    }

    private static func isASCIIAlnum(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }

    static func isPunctuation(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy {
            switch $0.properties.generalCategory {
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
            default: return false
            }
        }
    }

    enum Op: Equatable {
        case equal(Int, Int)
        case delete(Int)
        case insert(Int)
    }

    static func align(_ a: [Character], _ b: [Character], maxD: Int) -> [Op]? {
        let n = a.count, m = b.count
        let limit = min(maxD, n + m)
        let off = limit + 1
        var v = [Int](repeating: 0, count: 2 * limit + 3)
        var trace: [[Int]] = []
        for d in 0...limit {
            trace.append(Array(v[(off - d - 1)...(off + d + 1)]))
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && v[off + k - 1] < v[off + k + 1]) {
                    x = v[off + k + 1]
                } else {
                    x = v[off + k - 1] + 1
                }
                var y = x - k
                while x < n, y < m, a[x] == b[y] { x += 1; y += 1 }
                v[off + k] = x
                if x >= n, y >= m { return backtrack(trace, n: n, m: m) }
                k += 2
            }
        }
        return nil
    }

    private static func backtrack(_ trace: [[Int]], n: Int, m: Int) -> [Op] {
        var ops: [Op] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let w = trace[d]
            func v(_ kk: Int) -> Int { w[kk + d + 1] }
            let k = x - y
            if d == 0 {
                while x > 0, y > 0 { ops.append(.equal(x - 1, y - 1)); x -= 1; y -= 1 }
                break
            }
            let prevK = (k == -d || (k != d && v(k - 1) < v(k + 1))) ? k + 1 : k - 1
            let prevX = v(prevK)
            let prevY = prevX - prevK
            while x > prevX, y > prevY { ops.append(.equal(x - 1, y - 1)); x -= 1; y -= 1 }
            if x == prevX { ops.append(.insert(y - 1)) } else { ops.append(.delete(x - 1)) }
            x = prevX
            y = prevY
        }
        return ops.reversed()
    }
}
