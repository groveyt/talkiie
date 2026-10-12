import Foundation

public enum ExampleDiff {
    public enum Kind: Equatable, Sendable { case kept, removed, added }

    public struct Segment: Equatable, Sendable {
        public let kind: Kind
        public let text: String
        public init(_ kind: Kind, _ text: String) {
            self.kind = kind
            self.text = text
        }
    }

    public static let maxCharacters = 2_000

    public static func segments(original: String, result: String) -> [Segment] {
        let a = Array(original), b = Array(result)
        guard a.count <= maxCharacters, b.count <= maxCharacters else {
            return merge([Segment(.removed, original), Segment(.added, result)].filter { !$0.text.isEmpty })
        }
        var lcs = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        if !a.isEmpty, !b.isEmpty {
            for i in stride(from: a.count - 1, through: 0, by: -1) {
                for j in stride(from: b.count - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var out: [Segment] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] {
                out.append(Segment(.kept, String(a[i]))); i += 1; j += 1
            } else if j < b.count, i == a.count || lcs[i][j + 1] > lcs[i + 1][j] {
                out.append(Segment(.added, String(b[j]))); j += 1
            } else {
                out.append(Segment(.removed, String(a[i]))); i += 1
            }
        }
        return merge(out)
    }

    public static func reconstruct(_ segments: [Segment], including kind: Kind) -> String {
        segments.filter { $0.kind == .kept || $0.kind == kind }.map(\.text).joined()
    }

    private static func merge(_ segments: [Segment]) -> [Segment] {
        var out: [Segment] = []
        for s in segments {
            if let last = out.last, last.kind == s.kind {
                out[out.count - 1] = Segment(s.kind, last.text + s.text)
            } else {
                out.append(s)
            }
        }
        return out
    }
}
