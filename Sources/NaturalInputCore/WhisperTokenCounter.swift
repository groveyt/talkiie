import Foundation

public enum WhisperTokenCounter {
    public static func count(_ text: String) -> Int {
        guard let vocab = Vocabulary.shared else { return text.utf8.count }
        var total = 0
        let bytes = Array(text.utf8)
        for word in words(bytes) {
            total += vocab.greedyCount(bytes[word])
        }
        return total
    }

    public static func prewarm() { _ = Vocabulary.shared }

    public static var vocabularyLoaded: Bool { Vocabulary.shared != nil }

    enum ByteClass { case alpha, digit, space, other }

    static func byteClass(_ b: UInt8) -> ByteClass {
        switch b {
        case 0x41...0x5A, 0x61...0x7A: return .alpha
        case 0x30...0x39: return .digit
        case 0x20, 0x09...0x0D: return .space
        default: return .other
        }
    }

    private static let contractions: [[UInt8]] = ["'s", "'t", "'re", "'ve", "'m", "'ll", "'d"].map { Array($0.utf8) }

    static func words(_ b: [UInt8]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var p = 0
        let n = b.count
        func run(from start: Int, _ cls: ByteClass) -> Int {
            var e = start
            while e < n, byteClass(b[e]) == cls { e += 1 }
            return e
        }
        while p < n {
            if let c = contractions.first(where: { p + $0.count <= n && b[p..<(p + $0.count)].elementsEqual($0) }) {
                out.append(p..<(p + c.count)); p += c.count; continue
            }
            let cls = byteClass(b[p])
            if b[p] == 0x20, p + 1 < n, byteClass(b[p + 1]) != .space {
                let e = run(from: p + 1, byteClass(b[p + 1]))
                out.append(p..<e); p = e; continue
            }
            if cls != .space {
                let e = run(from: p, cls)
                out.append(p..<e); p = e; continue
            }
            let e = run(from: p, .space)
            if e < n, e - p >= 2 {
                out.append(p..<(e - 1)); p = e - 1
            } else {
                out.append(p..<e); p = e
            }
        }
        return out
    }

    final class Vocabulary: @unchecked Sendable {
        private let storage: [UInt8]
        private let tokens: Set<ArraySlice<UInt8>>
        let maxLength: Int

        init?(data: Data) {
            let raw = [UInt8](data)
            guard raw.count > 8, raw[0..<4].elementsEqual(Array("TWV1".utf8)) else { return nil }
            let count = Int(raw[4]) | Int(raw[5]) << 8 | Int(raw[6]) << 16 | Int(raw[7]) << 24
            var set = Set<ArraySlice<UInt8>>(minimumCapacity: count)
            var p = 8
            var longest = 0
            for _ in 0..<count {
                guard p < raw.count else { return nil }
                let len = Int(raw[p]); p += 1
                guard len > 0, p + len <= raw.count else { return nil }
                set.insert(raw[p..<(p + len)])
                longest = max(longest, len)
                p += len
            }
            guard p == raw.count, set.count > 50_000 else { return nil }
            guard (0...255).allSatisfy({ set.contains([UInt8($0)][...]) }) else { return nil }
            storage = raw
            tokens = set
            maxLength = longest
        }

        static let shared: Vocabulary? = {
            guard let path = Bundle.module.path(forResource: "whisper-vocab", ofType: "bin", inDirectory: "WhisperTokenizer"),
                  let data = FileManager.default.contents(atPath: path) else { return nil }
            return Vocabulary(data: data)
        }()

        func greedyCount(_ word: ArraySlice<UInt8>) -> Int {
            var count = 0
            var i = word.startIndex
            let end = word.endIndex
            while i < end {
                var j = min(end, i + maxLength)
                while j > i + 1, !tokens.contains(word[i..<j]) { j -= 1 }
                count += 1
                i = j
            }
            return count
        }
    }
}
