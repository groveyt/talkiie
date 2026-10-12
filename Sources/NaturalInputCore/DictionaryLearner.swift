import Foundation

public enum DictionaryLearner {
    public static let threshold = PersonalDictionary.fuzzyThreshold
    public static let maxWordLength = 4
    public static let maxCharacters = 1_000

    public static func learn(inserted: String, edited: String, lexicon: BopomofoLexicon) -> [PersonalDictionary.Entry] {
        let a = Array(inserted), b = Array(edited)
        guard a != b, !a.isEmpty, !b.isEmpty, a.count <= maxCharacters, b.count <= maxCharacters else { return [] }
        let candidates = edits(a, b).compactMap { candidate(for: $0, a: a, b: b, lexicon: lexicon) }
        var out: [PersonalDictionary.Entry] = []
        var seen = Set<String>()
        for c in maximalSpans(candidates) {
            let entry = c.entry
            guard PersonalDictionary.problem(heard: entry.heard, replacement: entry.replacement) == nil,
                  LearnedTermGate.rejection(entry.replacement) == nil,
                  seen.insert(entry.heard).inserted else { continue }
            out.append(entry)
        }
        return out
    }

    struct Candidate {
        let entry: PersonalDictionary.Entry
        let span: Range<Int>
    }

    static func maximalSpans(_ candidates: [Candidate]) -> [Candidate] {
        let bySize = candidates.enumerated().sorted {
            $0.element.span.count != $1.element.span.count ? $0.element.span.count > $1.element.span.count : $0.offset < $1.offset
        }
        var kept: [(offset: Int, element: Candidate)] = []
        for c in bySize where !kept.contains(where: { $0.element.span.overlaps(c.element.span) }) {
            kept.append(c)
        }
        return kept.sorted { $0.offset < $1.offset }.map(\.element)
    }

    private static func candidate(for edit: Edit, a: [Character], b: [Character], lexicon: BopomofoLexicon) -> Candidate? {
        switch edit {
        case .han(let aStart, let bStart, let length):
            guard let (heard, target, left) = wordSpan(aStart: aStart, bStart: bStart, length: length, a: a, b: b, lexicon: lexicon),
                  let d = lexicon.distance(heard, target), d <= threshold else { return nil }
            let heardText = String(heard), targetText = String(target)
            return Candidate(entry: PersonalDictionary.Entry(heard: heardText, replacement: targetText, origin: .learned,
                                                             promptOnly: lexicon.isWord(heardText)),
                             span: (aStart - left)..<(aStart - left + heard.count))
        case .ascii(let aWord, let bWord, let neighbor, let span):
            return englishEntry(aWord: aWord, bWord: bWord, neighbor: neighbor).map { Candidate(entry: $0, span: span) }
        case .maximalSpan(let aRange, let bRange):
            return maximalSpanEntry(heard: String(a[aRange]), replacement: String(b[bRange])).map { Candidate(entry: $0, span: aRange) }
        }
    }

    static func maximalSpanEntry(heard: String, replacement: String) -> PersonalDictionary.Entry? {
        let heard = PersonalDictionary.trimmed(heard), replacement = PersonalDictionary.trimmed(replacement)
        guard !heard.isEmpty, !replacement.isEmpty, heard != replacement,
              heard.count <= TranscriptionPrompt.maxTermCharacters,
              replacement.count <= TranscriptionPrompt.maxTermCharacters else { return nil }
        return PersonalDictionary.Entry(heard: heard, replacement: replacement, origin: .learned,
                                        promptOnly: heard.lowercased() != replacement.lowercased())
    }

    struct Atom: Equatable {
        let chars: [Character]
        let isAsciiWord: Bool
    }

    static func isAsciiWordCharacter(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    static func atomize(_ chars: [Character]) -> [Atom] {
        var atoms: [Atom] = []
        var i = 0
        while i < chars.count {
            if isAsciiWordCharacter(chars[i]) {
                var j = i + 1
                while j < chars.count, isAsciiWordCharacter(chars[j]) { j += 1 }
                atoms.append(Atom(chars: Array(chars[i..<j]), isAsciiWord: true))
                i = j
            } else {
                atoms.append(Atom(chars: [chars[i]], isAsciiWord: false))
                i += 1
            }
        }
        return atoms
    }

    private static func charStarts(_ atoms: [Atom]) -> [Int] {
        var starts: [Int] = []
        var pos = 0
        for atom in atoms { starts.append(pos); pos += atom.chars.count }
        return starts
    }

    struct AsciiNeighbor: Equatable {
        let text: String
        let before: Bool
    }

    private static func isWhitespaceAtom(_ atom: Atom) -> Bool {
        !atom.isAsciiWord && atom.chars.allSatisfy(\.isWhitespace)
    }

    private static func asciiNeighbor(around index: Int, in atoms: [Atom], before: Bool) -> String? {
        neighborIndex(around: index, in: atoms, before: before).map { String(atoms[$0].chars) }
    }

    private static func neighborIndex(around index: Int, in atoms: [Atom], before: Bool) -> Int? {
        var k = before ? index - 1 : index + 1
        guard k >= 0, k < atoms.count else { return nil }
        if isWhitespaceAtom(atoms[k]) { k += before ? -1 : 1 }
        guard k >= 0, k < atoms.count, atoms[k].isAsciiWord else { return nil }
        return k
    }

    private static func sharedNeighbor(aIndex: Int, in atomsA: [Atom], bIndex: Int, in atomsB: [Atom]) -> AsciiNeighbor? {
        for before in [false, true] {
            guard let x = asciiNeighbor(around: aIndex, in: atomsA, before: before),
                  let y = asciiNeighbor(around: bIndex, in: atomsB, before: before), x == y,
                  LearnedTermGate.rejection(x) == nil, !x.allSatisfy(\.isNumber) else { continue }
            return AsciiNeighbor(text: x, before: before)
        }
        return nil
    }

    enum Hunk: Equatable {
        case han(aStart: Int, bStart: Int, length: Int)
        case ascii(aWord: String, bWord: String, neighbor: AsciiNeighbor?)
    }

    enum Edit: Equatable {
        case han(aStart: Int, bStart: Int, length: Int)
        case ascii(aWord: String, bWord: String, neighbor: AsciiNeighbor?, span: Range<Int>)
        case maximalSpan(a: Range<Int>, b: Range<Int>)
    }

    struct ChangedRun {
        let a: Range<Int>
        let b: Range<Int>
        let hunk: Hunk?
        let asciiSpan: Range<Int>?
    }

    static func hunks(_ a: [Character], _ b: [Character]) -> [Hunk] {
        changedRuns(atomize(a), atomize(b)).compactMap(\.hunk)
    }

    static func edits(_ a: [Character], _ b: [Character]) -> [Edit] {
        let atomsA = atomize(a), atomsB = atomize(b)
        let startsA = charStarts(atomsA), startsB = charStarts(atomsB)
        func chars(_ r: Range<Int>, _ starts: [Int], total: Int) -> Range<Int> {
            func at(_ k: Int) -> Int { k < starts.count ? starts[k] : total }
            return at(r.lowerBound)..<at(r.upperBound)
        }
        let runs = changedRuns(atomsA, atomsB)
        var out: [Edit] = []
        var k = 0
        while k < runs.count {
            var last = k
            while last + 1 < runs.count,
                  (runs[last].a.upperBound..<runs[last + 1].a.lowerBound).allSatisfy({ isWhitespaceAtom(atomsA[$0]) }) {
                last += 1
            }
            if last > k {
                out.append(.maximalSpan(a: chars(runs[k].a.lowerBound..<runs[last].a.upperBound, startsA, total: a.count),
                                        b: chars(runs[k].b.lowerBound..<runs[last].b.upperBound, startsB, total: b.count)))
            } else if let hunk = runs[k].hunk {
                switch hunk {
                case .han(let aStart, let bStart, let length):
                    out.append(.han(aStart: aStart, bStart: bStart, length: length))
                case .ascii(let aWord, let bWord, let neighbor):
                    out.append(.ascii(aWord: aWord, bWord: bWord, neighbor: neighbor, span: runs[k].asciiSpan!))
                }
            }
            k = last + 1
        }
        return out
    }

    static func changedRuns(_ atomsA: [Atom], _ atomsB: [Atom]) -> [ChangedRun] {
        let startsA = charStarts(atomsA), startsB = charStarts(atomsB)
        let m = atomsA.count, n = atomsB.count
        var lcs = [[UInt16]](repeating: [UInt16](repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    lcs[i][j] = atomsA[i] == atomsB[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        func charRange(_ k: Int) -> Range<Int> { startsA[k]..<(startsA[k] + atomsA[k].chars.count) }
        var out: [ChangedRun] = []
        var i = 0, j = 0
        var runA = 0, runB = 0
        var inRun = false
        func close() {
            guard inRun else { return }
            inRun = false
            let countA = i - runA, countB = j - runB
            guard countA > 0 || countB > 0 else { return }
            if countA == 1, countB == 1, atomsA[runA].isAsciiWord, atomsB[runB].isAsciiWord {
                let neighbor = sharedNeighbor(aIndex: runA, in: atomsA, bIndex: runB, in: atomsB)
                var span = charRange(runA)
                if let neighbor, let k = neighborIndex(around: runA, in: atomsA, before: neighbor.before) {
                    span = min(span.lowerBound, charRange(k).lowerBound)..<max(span.upperBound, charRange(k).upperBound)
                }
                out.append(ChangedRun(a: runA..<i, b: runB..<j,
                                      hunk: .ascii(aWord: String(atomsA[runA].chars), bWord: String(atomsB[runB].chars),
                                                   neighbor: neighbor),
                                      asciiSpan: span))
                return
            }
            let han = countA == countB
                && (runA..<i).allSatisfy({ !atomsA[$0].isAsciiWord && PersonalDictionary.isHan(atomsA[$0].chars[0]) })
                && (runB..<j).allSatisfy({ !atomsB[$0].isAsciiWord && PersonalDictionary.isHan(atomsB[$0].chars[0]) })
            out.append(ChangedRun(a: runA..<i, b: runB..<j,
                                  hunk: han ? .han(aStart: startsA[runA], bStart: startsB[runB], length: countA) : nil,
                                  asciiSpan: nil))
        }
        while i < m || j < n {
            if i < m, j < n, atomsA[i] == atomsB[j], lcs[i][j] == lcs[i + 1][j + 1] + 1 {
                close()
                i += 1; j += 1
                continue
            }
            if !inRun { inRun = true; runA = i; runB = j }
            if i < m, j == n || lcs[i + 1][j] >= lcs[i][j + 1] { i += 1 } else { j += 1 }
        }
        close()
        return out
    }

    static func word(aStart: Int, bStart: Int, length: Int, a: [Character], b: [Character],
                     lexicon: BopomofoLexicon) -> ([Character], [Character])? {
        wordSpan(aStart: aStart, bStart: bStart, length: length, a: a, b: b, lexicon: lexicon).map { ($0.0, $0.1) }
    }

    static func wordSpan(aStart: Int, bStart: Int, length: Int, a: [Character], b: [Character],
                         lexicon: BopomofoLexicon) -> ([Character], [Character], left: Int)? {
        guard length <= maxWordLength else { return nil }
        func sharedLeft(_ k: Int) -> Bool {
            let ai = aStart - k, bi = bStart - k
            return ai >= 0 && bi >= 0 && a[ai] == b[bi] && PersonalDictionary.isHan(a[ai])
        }
        func sharedRight(_ k: Int) -> Bool {
            let ai = aStart + length + k - 1, bi = bStart + length + k - 1
            return ai < a.count && bi < b.count && a[ai] == b[bi] && PersonalDictionary.isHan(a[ai])
        }
        var best: (heard: [Character], target: [Character], left: Int)?
        for total in max(2, length)...maxWordLength {
            let extra = total - length
            for left in stride(from: extra, through: 0, by: -1) {
                let right = extra - left
                guard (0..<left).allSatisfy({ sharedLeft($0 + 1) }),
                      (0..<right).allSatisfy({ sharedRight($0 + 1) }) else { continue }
                let heard = Array(a[(aStart - left)..<(aStart + length + right)])
                let target = Array(b[(bStart - left)..<(bStart + length + right)])
                if lexicon.isWord(String(target)) { return (heard, target, left) }
                if best == nil, extra == 0 { best = (heard, target, left) }
            }
        }
        return best.map { ($0.heard, $0.target, left: $0.left) }
    }

    static func englishEntry(aWord: String, bWord: String, neighbor: AsciiNeighbor?) -> PersonalDictionary.Entry? {
        guard aWord != bWord else { return nil }
        let aLetters = aWord.filter(\.isLetter), bLetters = bWord.filter(\.isLetter)
        guard !aLetters.isEmpty, !bLetters.isEmpty, aLetters != bLetters || aWord.lowercased() == bWord.lowercased()
        else { return nil }
        if aWord.lowercased() == bWord.lowercased() {
            return PersonalDictionary.Entry(heard: aWord, replacement: bWord, origin: .learned, promptOnly: false)
        }
        return PersonalDictionary.Entry(heard: phrase(aWord, neighbor), replacement: phrase(bWord, neighbor),
                                        origin: .learned, promptOnly: true)
    }

    private static func phrase(_ word: String, _ neighbor: AsciiNeighbor?) -> String {
        guard let neighbor else { return word }
        return neighbor.before ? "\(neighbor.text) \(word)" : "\(word) \(neighbor.text)"
    }
}
