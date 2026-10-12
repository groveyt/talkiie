import Foundation

public struct TranscriptSegment: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

extension TranscriptionOutcome {
    public static let paragraphSeparator = "\n"

    public var paragraphs: [String]? {
        guard case .text(let t) = self else { return nil }
        return t.components(separatedBy: Self.paragraphSeparator).filter { !$0.isEmpty }
    }
}

public enum TranscriptFormatter {
    public static let longPause: Double = 1.0
    public static let sentenceUnits = 15

    public static let softBreakGap: Double = 0.15

    static func healSplitWords(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard segments.count > 1, segments.contains(where: { $0.text.first?.isWhitespace == true }) else { return segments }
        var out: [TranscriptSegment] = []
        for seg in segments {
            if let prev = out.last, let a = prev.text.last, let b = seg.text.first,
               isASCIILetter(a), isASCIILetter(b), seg.start - prev.end < 0.05 {
                out[out.count - 1] = TranscriptSegment(text: prev.text + seg.text, start: prev.start, end: seg.end)
            } else {
                out.append(seg)
            }
        }
        return out
    }

    public static let punctuationMinUnits = 4

    public static func paragraphs(_ segments: [TranscriptSegment], fillers: FillerStrength = .off,
                                  spokenLists: Bool = SpokenList.defaultEnabled,
                                  paragraphing: ParagraphStrength = SemanticParagraphs.defaultStrength,
                       spokenCommands: Bool = SpokenCommands.defaultEnabled) -> [String] {
        finish(pauseText(segments), fillers: fillers, spokenLists: spokenLists, paragraphing: paragraphing, spokenCommands: spokenCommands).paragraphs
    }

    public static func format(_ segments: [TranscriptSegment], fillers: FillerStrength = .off,
                              spokenLists: Bool = SpokenList.defaultEnabled,
                              paragraphing: ParagraphStrength = SemanticParagraphs.defaultStrength,
                       spokenCommands: Bool = SpokenCommands.defaultEnabled) -> String {
        formatReporting(segments, fillers: fillers, spokenLists: spokenLists, paragraphing: paragraphing, spokenCommands: spokenCommands).text
    }

    public static func formatReporting(_ segments: [TranscriptSegment], fillers: FillerStrength,
                                       spokenLists: Bool = SpokenList.defaultEnabled,
                                       paragraphing: ParagraphStrength = SemanticParagraphs.defaultStrength,
                       spokenCommands: Bool = SpokenCommands.defaultEnabled)
        -> (text: String, fillers: FillerRemoval.Report?) {
        let f = finish(pauseText(segments), fillers: fillers, spokenLists: spokenLists, paragraphing: paragraphing, spokenCommands: spokenCommands)
        return (f.text, f.fillers)
    }

    static func pauseText(_ segments: [TranscriptSegment]) -> String {
        let segs = cleaned(healSplitWords(segments))
        guard !segs.isEmpty else { return "" }
        let isSentence = isSentence(segs)
        var current = ""
        for (i, seg) in segs.enumerated() {
            var text = seg.text
            let isLast = i == segs.count - 1
            if isSentence, !endsWithPunctuation(text) {
                let gap = isLast ? longPause : segs[i + 1].start - seg.end
                let fullStop = isLast || gap >= longPause
                if !isLast, gap < softBreakGap, !containsHan(text), !containsHan(segs[i + 1].text) {
                } else if containsHan(text) {
                    text += fullStop ? "。" : "，"
                } else {
                    text += fullStop ? "." : ","
                }
            }
            current = join(current, text)
        }
        return EnglishFormatting.apply(current, capitalizeStart: isSentence)
    }

    static func finish(_ text: String, fillers: FillerStrength = .off,
                       spokenLists: Bool = SpokenList.defaultEnabled,
                       paragraphing: ParagraphStrength = SemanticParagraphs.defaultStrength,
                       spokenCommands: Bool = SpokenCommands.defaultEnabled,
                       modelPunctuated: Bool = false,
                       looseLists: Bool = false)
        -> (paragraphs: [String], text: String, fillers: FillerRemoval.Report?, hasList: Bool) {
        guard !text.isEmpty else { return ([], "", nil, false) }
        var t = fullWidthPunctuation(EnglishInterjections.apply(text))
        var report: FillerRemoval.Report?
        if fillers != .off {
            let removal = FillerRemoval.apply(t, strength: fillers, spokenLists: spokenLists)
            t = removal.text
            report = removal.report
        }
        if spokenCommands, let split = SpokenCommands.split(t) {
            let total = split.pieces.reduce(0) { $0 + countUnits($1.text) }
            var lines: [(text: String, isItem: Bool, breakBefore: SpokenCommands.Break?)] = []
            for piece in split.pieces {
                let ls = layout(piece.text, total: total, spokenLists: spokenLists, paragraphing: paragraphing,
                                modelPunctuated: modelPunctuated, looseLists: looseLists)
                for (n, l) in ls.enumerated() {
                    lines.append((l.text, l.isItem, n == 0 ? piece.breakBefore : nil))
                }
            }
            var out = ""
            for (i, line) in lines.enumerated() {
                if let b = line.breakBefore { out += b.separator }
                else if i > 0 { out += line.isItem ? TranscriptionOutcome.paragraphSeparator
                                                    : TranscriptionOutcome.paragraphSeparator + TranscriptionOutcome.paragraphSeparator }
                out += line.text
            }
            if let b = split.trailing { out += b.separator }
            return (lines.map(\.text), out, report, lines.contains(where: \.isItem))
        }
        let lines = layout(t, total: nil, spokenLists: spokenLists, paragraphing: paragraphing,
                           modelPunctuated: modelPunctuated, looseLists: looseLists)
        return (lines.map(\.text), joined(lines), report, lines.contains(where: \.isItem))
    }

    private static func layout(_ text: String, total: Int?, spokenLists: Bool, paragraphing: ParagraphStrength,
                               modelPunctuated: Bool = false, looseLists: Bool = false)
        -> [(text: String, isItem: Bool)] {
        let t = QuestionMarks.apply(text)
        var blocks = spokenLists ? SpokenList.blocks(t, modelPunctuated: modelPunctuated) : [(text: t, isItem: false)]
        if spokenLists, looseLists, !blocks.contains(where: \.isItem), let loose = SpokenList.looseBlocks(t) {
            blocks = loose
        }
        let total = total ?? countUnits(t)
        return blocks
            .flatMap { block -> [(text: String, isItem: Bool)] in
                block.isItem ? [block]
                    : SemanticParagraphs.split(block.text, strength: paragraphing, totalUnits: total).map { ($0, false) }
            }
            .map { (text: PanguSpacing.apply($0.text), isItem: $0.isItem) }
    }

    static func joined(_ lines: [(text: String, isItem: Bool)]) -> String {
        let sep = TranscriptionOutcome.paragraphSeparator
        var out = ""
        for (i, line) in lines.enumerated() {
            if i > 0 { out += line.isItem ? sep : sep + sep }
            out += line.text
        }
        return out
    }

    private static func cleaned(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.compactMap { seg -> TranscriptSegment? in
            let t = clean(seg.text)
            return t.isEmpty ? nil : TranscriptSegment(text: t, start: seg.start, end: seg.end)
        }
    }

    private static func isSentence(_ segs: [TranscriptSegment]) -> Bool {
        segs.count > 1 || segs.map { countUnits($0.text) }.reduce(0, +) >= sentenceUnits
    }

    public struct PunctuationSource: Equatable, Sendable {
        public let original: String
        public let request: String
        public let units: Int
        let whisperMarks: [Int: Character]
        let isSentence: Bool
    }

    enum WhisperPolicy: CaseIterable {
        case drop
        case modelFirst
        case whisperFirst
    }
    static let defaultWhisperPolicy = WhisperPolicy.drop

    public static func punctuationSource(_ segments: [TranscriptSegment]) -> PunctuationSource? {
        let segs = cleaned(healSplitWords(segments))
        guard !segs.isEmpty else { return nil }
        let raw = segs.map(\.text).reduce("") { join($0, $1) }
        let (original, whisperMarks) = stripSentencePunctuation(raw)
        guard original.contains(where: { !$0.isWhitespace }) else { return nil }
        let hans = original.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? original
        let sameShape = hans.count == original.count
            && zip(hans, original).allSatisfy { $0.isWhitespace == $1.isWhitespace }
        return PunctuationSource(original: original, request: sameShape ? hans : original,
                                 units: countUnits(original), whisperMarks: whisperMarks,
                                 isSentence: isSentence(segs))
    }

    public struct Punctuated: Equatable, Sendable {
        public let text: String
        public let applied: Bool
        public let fallback: PunctuationFallback?
        public let marks: Int
        public let alignedPercent: Int?
        public var fillers: FillerRemoval.Report? = nil
        public var hasList: Bool = false
    }

    public static func format(_ segments: [TranscriptSegment], modelOutput: String,
                              fillers: FillerStrength = .off,
                              spokenLists: Bool = SpokenList.defaultEnabled,
                              paragraphing: ParagraphStrength = SemanticParagraphs.defaultStrength,
                       spokenCommands: Bool = SpokenCommands.defaultEnabled) -> Punctuated {
        format(segments, modelOutput: modelOutput, policy: defaultWhisperPolicy, fillers: fillers,
               spokenLists: spokenLists, paragraphing: paragraphing, spokenCommands: spokenCommands)
    }

    static func format(_ segments: [TranscriptSegment], modelOutput: String, policy: WhisperPolicy,
                       fillers: FillerStrength = .off,
                       spokenLists: Bool = SpokenList.defaultEnabled,
                       paragraphing: ParagraphStrength = SemanticParagraphs.defaultStrength,
                       spokenCommands: Bool = SpokenCommands.defaultEnabled,
                       looseLists: Bool = false) -> Punctuated {
        func fallback(_ reason: PunctuationFallback, aligned: Int? = nil) -> Punctuated {
            let f = finish(pauseText(segments), fillers: fillers, spokenLists: spokenLists, paragraphing: paragraphing,
                           spokenCommands: spokenCommands, looseLists: looseLists)
            return Punctuated(text: f.text, applied: false, fallback: reason, marks: 0, alignedPercent: aligned,
                              fillers: f.fillers, hasList: f.hasList)
        }
        guard let src = punctuationSource(segments) else { return fallback(.rejectedByGuard) }
        if spokenLists, whisperFormsEnglishList(segments) { return fallback(.whisperEnglishList) }
        guard let verdict = PunctuationGuard.marks(sent: src.request, output: modelOutput) else {
            return fallback(.rejectedByGuard)
        }
        var marks: [Int: Character]
        switch policy {
        case .drop: marks = verdict.marks
        case .modelFirst: marks = src.whisperMarks.merging(verdict.marks) { _, model in model }
        case .whisperFirst: marks = verdict.marks.merging(src.whisperMarks) { _, whisper in whisper }
        }
        marks = HowQuestionMarks.apply(marks, chars: src.original.filter { !$0.isWhitespace }.map { $0 }).marks
        let last = src.original.filter { !$0.isWhitespace }.count - 1
        if !src.isSentence {
            if let m = marks[last], m == "." || m == ",", verdict.marks[last] == m, src.whisperMarks[last] != m {
                marks[last] = nil
            }
        } else if marks[last] == nil, !endsWithPunctuation(src.original) {
            marks[last] = "."
        }
        let text = PunctuationGuard.render(src.original, marks: marks)
        guard PunctuationGuard.preserves(original: src.original, result: text) else {
            return fallback(.invariantViolated, aligned: verdict.alignedPercent)
        }
        let used = marks.filter { verdict.marks[$0.key] == $0.value }.count
        func pauseListInstead() -> Punctuated? {
            guard spokenLists else { return nil }
            let pause = finish(pauseText(segments), fillers: fillers, spokenLists: spokenLists,
                               paragraphing: paragraphing, spokenCommands: spokenCommands, looseLists: looseLists)
            guard pause.hasList else { return nil }
            return Punctuated(text: pause.text, applied: false, fallback: .pauseList, marks: 0,
                              alignedPercent: verdict.alignedPercent, fillers: pause.fillers, hasList: true)
        }
        let f = finish(EnglishFormatting.apply(text, capitalizeStart: src.isSentence), fillers: fillers, spokenLists: spokenLists,
                       paragraphing: paragraphing, spokenCommands: spokenCommands, modelPunctuated: true,
                       looseLists: looseLists)
        if !f.hasList, let pause = pauseListInstead() { return pause }
        return Punctuated(text: f.text,
                          applied: true, fallback: nil, marks: used, alignedPercent: verdict.alignedPercent,
                          fillers: f.fillers, hasList: f.hasList)
    }

    static func whisperFormsEnglishList(_ segments: [TranscriptSegment]) -> Bool {
        let text = fullWidthPunctuation(pauseText(segments))
        guard !text.isEmpty, let run = SpokenList.findRun(Array(text)) else { return false }
        return run[0].family.isEnglish
    }

    static func stripSentencePunctuation(_ text: String) -> (String, [Int: Character]) {
        let chars = Array(text)
        var out: [Character] = []
        var marks: [Int: [Character]] = [:]
        var content = 0
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let strip = fullWidthSentencePunctuation.contains(c) || (halfToFull[c] != nil && !isProtected(chars, i))
            guard strip else {
                out.append(c)
                if !c.isWhitespace { content += 1 }
                i += 1
                continue
            }
            if content > 0 { marks[content - 1, default: []].append(c) }
            while out.last == " " { out.removeLast() }
            i += 1
            while i < chars.count, chars[i] == " " { i += 1 }
            if let p = out.last, i < chars.count, isASCIIAlnum(p), isASCIIAlnum(chars[i]) { out.append(" ") }
        }
        var normalized: [Int: Character] = [:]
        let contentChars = out.filter { !$0.isWhitespace }
        for (k, cs) in marks {
            let next: Character? = k + 1 < contentChars.count ? contentChars[k + 1] : nil
            if let m = PunctuationGuard.normalize(cs, prev: contentChars[k], next: next) { normalized[k] = m }
        }
        return (String(out), normalized)
    }

    private static let fullWidthSentencePunctuation: Set<Character> = ["，", "。", "？", "！", "：", "；", "、"]

    static func joinedAcrossChunks(_ a: TranscriptSegment, _ b: TranscriptSegment) -> TranscriptSegment? {
        let left = clean(a.text), right = clean(b.text)
        guard !left.isEmpty, !right.isEmpty, !endsWithPunctuation(left),
              b.start - a.end < longPause else { return nil }
        return TranscriptSegment(text: join(left, right), start: a.start, end: b.end)
    }

    private static let halfToFull: [Character: Character] = [
        ",": "，", ".": "。", "?": "？", "!": "！", ":": "：", ";": "；",
    ]
    private static let sentenceEnders: Set<Character> = ["。", "？", "！", ".", "?", "!", "…"]

    static func fullWidthPunctuation(_ s: String) -> String {
        let chars = Array(s)
        var out: [Character] = []
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if let full = halfToFull[c], !isProtected(chars, i), isChineseContext(chars, i) {
                while out.last == " " { out.removeLast() }
                out.append(full)
                i += 1
                while i < chars.count, chars[i] == " " { i += 1 }
                continue
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    static func isProtected(_ chars: [Character], _ i: Int) -> Bool {
        let prev: Character? = i > 0 ? chars[i - 1] : nil
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if let p = prev, let n = next, isASCIIAlnum(p), isASCIIAlnum(n) { return true }
        if chars[i] == ".", prev == "." || next == "." { return true }
        let (lo, hi) = tokenRange(chars, i)
        let token = String(chars[lo..<hi])
        if token.contains("://") || token.lowercased().hasPrefix("www.") {
            let tail = chars[(i + 1)..<hi]
            if !tail.allSatisfy({ halfToFull[$0] != nil }) { return true }
        }
        if chars[i] == "." {
            var j = i - 1
            var dotted = false
            while j >= 1, isASCIILetter(chars[j]), chars[j - 1] == "." {
                dotted = true
                j -= 2
            }
            if dotted, j >= 0, isASCIILetter(chars[j]), j == 0 || !isASCIIAlnum(chars[j - 1]) {
                return true
            }
        }
        return false
    }

    private static func tokenRange(_ chars: [Character], _ i: Int) -> (Int, Int) {
        func boundary(_ c: Character) -> Bool { c == " " || isCJK(c) }
        var lo = i
        while lo > 0, !boundary(chars[lo - 1]) { lo -= 1 }
        var hi = i + 1
        while hi < chars.count, !boundary(chars[hi]) { hi += 1 }
        return (lo, hi)
    }

    private static func isChineseContext(_ chars: [Character], _ i: Int) -> Bool {
        if let p = chars[..<i].last(where: { $0 != " " }), isCJK(p) { return true }
        if let n = chars[(i + 1)...].first(where: { $0 != " " }), isCJK(n) { return true }
        var han = 0, latin = 0
        var j = i - 1
        while j >= 0 {
            if sentenceEnders.contains(chars[j]),
               !(chars[j] == "." && j + 1 < chars.count && isASCIIAlnum(chars[j + 1])) { break }
            if isHan(chars[j]) { han += 1 } else if isASCIILetter(chars[j]) { latin += 1 }
            j -= 1
        }
        return han > 0 && Double(han) / Double(han + latin) >= minHanShareForChineseSentence
    }

    static let minHanShareForChineseSentence = 0.1

    private static func join(_ a: String, _ b: String) -> String {
        guard let last = a.last, let first = b.first else { return a + b }
        return (isCJK(last) || isCJK(first)) ? a + b : a + " " + b
    }

    private static let closers: Set<Character> = ["\"", "'", ")", "]", "」", "』", "”", "’", "）"]

    private static func lastSignificant(_ s: String) -> Character? {
        s.last(where: { !closers.contains($0) })
    }

    private static func endsWithPunctuation(_ s: String) -> Bool {
        guard let c = lastSignificant(s) else { return false }
        return halfToFull[c] != nil || "，。？！：；、…".contains(c)
    }

    static func countUnits(_ s: String) -> Int {
        var n = 0
        var inWord = false
        for c in s {
            if isHan(c) {
                n += 1
                inWord = false
            } else if isASCIIAlnum(c) {
                if !inWord { n += 1 }
                inWord = true
            } else {
                inWord = false
            }
        }
        return n
    }

    private static func clean(_ s: String) -> String {
        var out = ""
        var lastSpace = true
        for ch in s {
            let isSpace = ch.isWhitespace || ch.unicodeScalars.allSatisfy {
                $0.properties.generalCategory == .control
            }
            if isSpace {
                if !lastSpace { out.append(" ") }
                lastSpace = true
            } else {
                out.append(ch)
                lastSpace = false
            }
        }
        if out.last == " " { out.removeLast() }
        return out
    }

    private static func containsHan(_ s: String) -> Bool { s.contains(where: isHan) }

    static func isHan(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0x20000...0x3FFFF).contains(v)
            || (0x3040...0x30FF).contains(v) || (0x3100...0x312F).contains(v)
            || (0xAC00...0xD7AF).contains(v)
    }

    static func isCJK(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return isHan(c) || (0x3000...0x303F).contains(v) || (0xFF00...0xFFEF).contains(v)
    }

    private static func isASCIIAlnum(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }

    private static func isASCIILetter(_ c: Character) -> Bool {
        c.isASCII && c.isLetter
    }
}

private extension Unicode.GeneralCategory {
    var isPunctuation: Bool {
        switch self {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation: return true
        default: return false
        }
    }
}
