import Foundation

public enum SpokenCommands {
    public static let defaultsKey = "spokenFormattingCommands"
    public static let defaultEnabled = false

    public static let example = "大家好，換行，今天晚餐要煮三道菜。新段落，第一道是番茄炒蛋。"

    public static func enabled(fromDefaults raw: Any?) -> Bool {
        (raw as? Bool) ?? defaultEnabled
    }

    public enum Break: Int, Comparable, Sendable {
        case line = 1
        case paragraph = 2
        public static func < (a: Break, b: Break) -> Bool { a.rawValue < b.rawValue }
        public var separator: String {
            String(repeating: TranscriptionOutcome.paragraphSeparator, count: rawValue)
        }
    }

    public struct Piece: Equatable, Sendable {
        public var text: String
        public var breakBefore: Break?
    }

    public struct Split: Equatable, Sendable {
        public var pieces: [Piece]
        public var trailing: Break?
        public var commands: Int
    }

    static let words: [(word: String, kind: Break)] = [
        ("新段落", .paragraph), ("下一段", .paragraph),
        ("new paragraph", .paragraph), ("next paragraph", .paragraph),
        ("換行", .line), ("换行", .line),
        ("new line", .line), ("newline", .line),
    ]

    static let boundaries: Set<Character> = [
        "。", "，", "？", "！", "、", "；", "：", "…", ",", ".", "?", "!", ";", ":", "\n",
    ]
    static let weakTrailing: Set<Character> = ["，", "、", "；", "：", ",", ";", ":"]

    public static func split(_ text: String) -> Split? {
        let chars = Array(text)
        var matches: [(start: Int, end: Int, kind: Break)] = []
        var i = 0
        while i < chars.count {
            if let m = match(chars, at: i) {
                matches.append((i, m.end, m.kind))
                i = m.end
            } else {
                i += 1
            }
        }
        guard !matches.isEmpty else { return nil }

        var pieces: [Piece] = []
        var pending: Break?
        var cursor = 0
        func emit(_ range: Range<Int>, followedByCommand: Bool) {
            var s = Array(chars[range])
            if pending != nil { while let f = s.first, f.isWhitespace || boundaries.contains(f) { s.removeFirst() } }
            while let f = s.first, f.isWhitespace { s.removeFirst() }
            while let l = s.last, l.isWhitespace || (followedByCommand && weakTrailing.contains(l)) { s.removeLast() }
            guard !s.isEmpty else { return }
            pieces.append(Piece(text: String(s), breakBefore: pending))
            pending = nil
        }
        for m in matches {
            emit(cursor..<m.start, followedByCommand: true)
            pending = max(pending ?? m.kind, m.kind)
            cursor = m.end
        }
        emit(cursor..<chars.count, followedByCommand: false)
        return Split(pieces: pieces, trailing: pending, commands: matches.count)
    }

    private static func match(_ chars: [Character], at i: Int) -> (end: Int, kind: Break)? {
        var p = i - 1
        while p >= 0, chars[p] == " " { p -= 1 }
        guard p < 0 || boundaries.contains(chars[p]) else { return nil }
        for (word, kind) in words {
            guard let end = consume(word, chars, at: i) else { continue }
            var n = end
            while n < chars.count, chars[n] == " " { n += 1 }
            guard n >= chars.count || boundaries.contains(chars[n]) else { continue }
            return (end, kind)
        }
        return nil
    }

    private static func consume(_ word: String, _ chars: [Character], at i: Int) -> Int? {
        var j = i
        for w in word {
            if w == " " {
                while j < chars.count, chars[j] == " " { j += 1 }
                continue
            }
            guard j < chars.count, String(chars[j]).lowercased() == String(w) else { return nil }
            j += 1
        }
        return j
    }
}
