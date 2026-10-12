import Foundation

struct SpellingVariants: Sendable {
    static let minimumLength = 3
    static let maxSpanWords = 4

    struct Target: Equatable, Sendable {
        let canonical: String
        let strong: Bool
    }

    private let targets: [String: Target]
    var isEmpty: Bool { targets.isEmpty }

    init(terms: [String]) {
        var t: [String: Target] = [:]
        for term in terms {
            guard let target = Self.target(for: term) else { continue }
            let key = Self.skeleton(term)
            if t[key] == nil { t[key] = target }
        }
        targets = t
    }

    static func target(for term: String) -> Target? {
        let chars = Array(term)
        guard let first = chars.first, let last = chars.last, isAsciiWord(first), isAsciiWord(last),
              chars.allSatisfy({ isAsciiWord($0) || isSeparator($0) }),
              chars.contains(where: \.isLetter) else { return nil }
        for (i, c) in chars.enumerated() where isSeparator(c) {
            guard isAsciiWord(chars[i - 1]), isAsciiWord(chars[i + 1]) else { return nil }
        }
        guard skeleton(term).count >= minimumLength else { return nil }
        let multiword = chars.contains(where: isSeparator)
        let digit = chars.contains(where: \.isNumber)
        let innerUpper = chars.dropFirst().contains(where: \.isUppercase)
        return Target(canonical: term, strong: multiword || digit || innerUpper)
    }

    static func skeleton(_ s: String) -> String { String(s.filter(isAsciiWord)).lowercased() }

    static func isAsciiWord(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
    static func isSeparator(_ c: Character) -> Bool { c == " " || c == "-" }

    func apply(_ text: String) -> (text: String, count: Int) {
        guard !targets.isEmpty else { return (text, 0) }
        let chars = Array(text)
        var words: [Range<Int>] = []
        var i = 0
        while i < chars.count {
            guard Self.isAsciiWord(chars[i]) else { i += 1; continue }
            var j = i + 1
            while j < chars.count, Self.isAsciiWord(chars[j]) { j += 1 }
            words.append(i..<j)
            i = j
        }
        guard !words.isEmpty else { return (text, 0) }
        func joined(_ k: Int) -> Bool {
            k + 1 < words.count && words[k + 1].lowerBound == words[k].upperBound + 1 && Self.isSeparator(chars[words[k].upperBound])
        }
        var replacements: [(Range<Int>, String)] = []
        var w = 0
        while w < words.count {
            var matched = false
            var available = 1
            while available < Self.maxSpanWords, joined(w + available - 1) { available += 1 }
            for k in stride(from: available, through: 1, by: -1) {
                let span = words[w].lowerBound..<words[w + k - 1].upperBound
                guard boundaryOK(span, chars) else { continue }
                let spanText = String(chars[span])
                guard let target = targets[Self.skeleton(spanText)], spanText != target.canonical else { continue }
                if !target.strong {
                    guard k >= 2, spanText.contains(where: { $0.isUppercase || $0.isNumber }) else { continue }
                }
                replacements.append((span, target.canonical))
                w += k
                matched = true
                break
            }
            if !matched { w += 1 }
        }
        guard !replacements.isEmpty else { return (text, 0) }
        var out = ""
        var p = 0
        for (range, canonical) in replacements {
            out += String(chars[p..<range.lowerBound])
            out += canonical
            p = range.upperBound
        }
        out += String(chars[p...])
        return (out, replacements.count)
    }

    private func boundaryOK(_ span: Range<Int>, _ chars: [Character]) -> Bool {
        func cjkLike(_ c: Character) -> Bool {
            PersonalDictionary.isCJK(c) || (c.unicodeScalars.allSatisfy { u in
                (0x3000...0x303F).contains(u.value) || (0xFF00...0xFFEF).contains(u.value)
            } && !c.isLetter && !c.isNumber)
        }
        if span.lowerBound > 0 {
            let before = chars[span.lowerBound - 1]
            guard before.isWhitespace || cjkLike(before) || Self.openers.contains(before) else { return false }
        }
        if span.upperBound < chars.count {
            let after = chars[span.upperBound]
            if after.isWhitespace || cjkLike(after) || Self.closers.contains(after) { return true }
            guard Self.sentencePunctuation.contains(after) else { return false }
            let next = span.upperBound + 1
            return next >= chars.count || chars[next].isWhitespace || cjkLike(chars[next])
        }
        return true
    }

    private static let openers: Set<Character> = ["(", "[", "\"", "'", "\u{201C}", "\u{2018}"]
    private static let closers: Set<Character> = [")", "]", "\"", "'", "\u{201D}", "\u{2019}"]
    private static let sentencePunctuation: Set<Character> = [",", ".", ";", ":", "!", "?"]
}
