import Foundation

public enum HeardCorrectionSuggestion {
    public struct Suggestion: Equatable, Sendable {
        public var heard: String
        public var replacement: String
    }

    public static func suggest(recognized: String, actual: String, lexicon: BopomofoLexicon?) -> Suggestion? {
        let a = Array(PersonalDictionary.trimmed(recognized)), b = Array(PersonalDictionary.trimmed(actual))
        guard a != b, !a.isEmpty, !b.isEmpty,
              a.count <= DictionaryLearner.maxCharacters, b.count <= DictionaryLearner.maxCharacters else { return nil }
        let hunks = DictionaryLearner.hunks(a, b)
        guard hunks.count == 1, let hunk = hunks.first else { return nil }

        var p = 0
        while p < a.count, p < b.count, a[p] == b[p] { p += 1 }
        var s = 0
        while s < a.count - p, s < b.count - p, a[a.count - 1 - s] == b[b.count - 1 - s] { s += 1 }
        let midA = a.count - p - s, midB = b.count - p - s

        let heard: String, target: String
        switch hunk {
        case .han(let aStart, let bStart, let length):
            guard midA <= length, midB <= length else { return nil }
                        let tiny = a.count <= DictionaryLearner.maxWordLength && b.count <= DictionaryLearner.maxWordLength
            guard length * 2 <= min(a.count, b.count) || (tiny && length == a.count && length == b.count) else { return nil }
            if let lexicon {
                guard let (h, t) = DictionaryLearner.word(aStart: aStart, bStart: bStart, length: length, a: a, b: b, lexicon: lexicon)
                else { return nil }
                heard = String(h); target = String(t)
            } else {
                guard length >= 2, length <= DictionaryLearner.maxWordLength else { return nil }
                heard = String(a[aStart..<(aStart + length)]); target = String(b[bStart..<(bStart + length)])
            }
        case .ascii(let aWord, let bWord, let neighbor):
            guard midA <= aWord.count, midB <= bWord.count else { return nil }
            guard let e = DictionaryLearner.englishEntry(aWord: aWord, bWord: bWord, neighbor: neighbor) else { return nil }
            heard = e.heard; target = e.replacement
        }
        guard PersonalDictionary.problem(heard: heard, replacement: target) == nil else { return nil }
        return Suggestion(heard: heard, replacement: target)
    }
}
