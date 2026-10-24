import Foundation

public enum HallucinationFilter {
    public struct Candidate: Equatable, Sendable {
        public var segment: TranscriptSegment
        public var noSpeechProb: Double?
        public var avgLogprob: Double?
        public var compressionRatio: Double?
        #if DEBUG
        public var tokenCount: Int?
        #endif

        public init(segment: TranscriptSegment, noSpeechProb: Double? = nil,
                    avgLogprob: Double? = nil, compressionRatio: Double? = nil) {
            self.segment = segment
            self.noSpeechProb = noSpeechProb
            self.avgLogprob = avgLogprob
            self.compressionRatio = compressionRatio
        }
    }

    public enum Reason: CaseIterable, Sendable {
        case silentChunk, artifact, blacklist, promptEcho, noSpeech, repetition
    }

    public struct Chunk: Equatable, Sendable {
        public var isSilent: Bool
        public var isNearSilent: Bool
        public var prompt: TranscriptionPrompt

        public init(isSilent: Bool, isNearSilent: Bool = false, prompt: TranscriptionPrompt = .empty) {
            self.isSilent = isSilent
            self.isNearSilent = isNearSilent
            self.prompt = prompt
        }

        public init(level: AudioLevelSummary, prompt: TranscriptionPrompt) {
            self.init(isSilent: level.isSilent, isNearSilent: TranscriptionPrompt.isNearSilent(level), prompt: prompt)
        }
    }

    public struct Drops: Equatable, Sendable {
        public var silentChunk = 0
        public var artifact = 0
        public var blacklist = 0
        public var promptEcho = 0
        public var noSpeech = 0
        public var repetition = 0

        public init() {}

        public var total: Int { silentChunk + artifact + blacklist + promptEcho + noSpeech + repetition }

        public mutating func add(_ reason: Reason) {
            switch reason {
            case .silentChunk: silentChunk += 1
            case .artifact: artifact += 1
            case .blacklist: blacklist += 1
            case .promptEcho: promptEcho += 1
            case .noSpeech: noSpeech += 1
            case .repetition: repetition += 1
            }
        }

        public static func + (a: Drops, b: Drops) -> Drops {
            var d = a
            d.silentChunk += b.silentChunk
            d.artifact += b.artifact
            d.blacklist += b.blacklist
            d.promptEcho += b.promptEcho
            d.noSpeech += b.noSpeech
            d.repetition += b.repetition
            return d
        }
    }

    public static let noSpeechThreshold = 0.6
    public static let logprobThreshold = -1.0
    public static let compressionRatioThreshold = 2.4
    public static let repetitionMinCharacters = 24
    public static let nearMatchMinLength = 8

    public static func filter(_ candidates: [Candidate], chunkIsSilent: Bool) -> (segments: [TranscriptSegment], drops: Drops) {
        filter(candidates, chunk: Chunk(isSilent: chunkIsSilent))
    }

    public static func filter(_ candidates: [Candidate], chunk: Chunk) -> (segments: [TranscriptSegment], drops: Drops) {
        var kept: [TranscriptSegment] = []
        var drops = Drops()
        let echo = PromptEcho(chunk)
        for c in candidates {
            var seg = c.segment
            seg.text = strippingSpecialTokens(seg.text)
            if let reason = reason(for: c, cleanedText: seg.text, chunkIsSilent: chunk.isSilent, echo: echo) {
                drops.add(reason)
            } else {
                kept.append(seg)
            }
        }
        return (kept, drops)
    }

    public static func reason(for c: Candidate, chunkIsSilent: Bool) -> Reason? {
        reason(for: c, chunk: Chunk(isSilent: chunkIsSilent))
    }

    public static func reason(for c: Candidate, chunk: Chunk) -> Reason? {
        reason(for: c, cleanedText: strippingSpecialTokens(c.segment.text), chunkIsSilent: chunk.isSilent,
               echo: PromptEcho(chunk))
    }

    private static func reason(for c: Candidate, cleanedText text: String, chunkIsSilent: Bool, echo: PromptEcho?) -> Reason? {
        let hadText = c.segment.text.contains(where: { !$0.isWhitespace })
        guard hadText else { return nil }
        if chunkIsSilent { return .silentChunk }
        if isArtifact(text) { return .artifact }
        if isBlacklisted(text) { return .blacklist }
        if let echo, echo.matches(text) { return .promptEcho }
        if let nsp = c.noSpeechProb, let lp = c.avgLogprob, nsp > noSpeechThreshold, lp < logprobThreshold {
            return .noSpeech
        }
        if let cr = c.compressionRatio ?? localCompressionRatio(text), cr > compressionRatioThreshold {
            return .repetition
        }
        return nil
    }

    struct PromptEcho {
        let joined: String
        let terms: [[Character]]

        init?(_ chunk: Chunk) {
            guard chunk.isNearSilent, !chunk.prompt.isEmpty else { return nil }
            joined = HallucinationFilter.normalize(chunk.prompt.text)
            terms = chunk.prompt.terms.map { Array(HallucinationFilter.normalize($0)) }.filter { !$0.isEmpty }
            guard !joined.isEmpty else { return nil }
        }

        func matches(_ text: String) -> Bool {
            let n = HallucinationFilter.normalize(text)
            guard !n.isEmpty else { return false }
            if joined.contains(n) { return true }
            let chars = Array(n)
            guard chars.count >= 2 else { return false }
            return terms.contains { $0.count >= 2 && HallucinationFilter.editDistance(chars, $0, limit: 1) <= 1 }
        }
    }

    static func strippingSpecialTokens(_ s: String) -> String {
        guard s.contains("<|") else { return s }
        return s.replacingOccurrences(of: #"<\|[^|<>]*\|>"#, with: "", options: .regularExpression)
    }

    static func isArtifact(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        if isURLOnly(t) { return true }
        if !t.contains(where: { $0.isLetter || $0.isNumber }) { return true }
        let group = #"(?:\[[^\[\]]*\]|\([^()]*\)|（[^（）]*）|【[^【】]*】|\*[^*]+\*|♪[^♪]*♪|[♪♫♬🎵🎶])"#
        let pattern = "^(?:\\s*" + group + "\\s*[\\p{P}\\s]*)+$"
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    static func isURLOnly(_ t: String) -> Bool {
        t.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil
    }

    static let blacklistPhrases: [String] = [
        "谢谢观看", "謝謝觀看", "感谢观看", "謝謝收看", "感謝收看", "谢谢大家观看", "謝謝大家收看",
        "谢谢您的观看", "感謝您的觀看", "谢谢观看，下次再见",
        "请不吝点赞 订阅 转发 打赏支持明镜与点点栏目", "請不吝點讚 訂閱 轉發 打賞支持明鏡與點點欄目",
        "明镜与点点栏目", "点赞订阅转发打赏支持明镜与点点栏目",
        "优优独播剧场——YoYo Television Series Exclusive", "优优独播剧场", "YoYo Television Series Exclusive",
        "字幕由Amara.org社区提供", "小編字幕由Amara.org社區提供", "中文字幕提供",
        "Thank you for watching", "Thanks for watching", "Thank you so much for watching",
        "Thank you for watching!", "Thank you very much for watching",
        "Subtitles by the Amara.org community",
        "ご視聴ありがとうございました", "시청해주셔서 감사합니다", "그",
    ]

    static let creditPrefixes: [String] = ["字幕by"]
    static let creditNameMaxLength = 12

    private static let normalizedBlacklist: [[Character]] = Array(Set(blacklistPhrases.map(normalize)))
        .filter { !$0.isEmpty }.map(Array.init)
    private static let normalizedCreditPrefixes: [String] = creditPrefixes.map(normalize)

    public static func normalize(_ s: String) -> String {
        let hant = TraditionalChinese.convert(s).lowercased()
        return String(hant.filter { $0.isLetter || $0.isNumber })
    }

    static func isBlacklisted(_ text: String) -> Bool {
        let n = normalize(text)
        guard !n.isEmpty else { return false }
        for p in normalizedCreditPrefixes where n.hasPrefix(p) && n.count - p.count <= creditNameMaxLength {
            return true
        }
        let chars = Array(n)
        for entry in normalizedBlacklist {
            if chars == entry || isRepetition(chars, of: entry) { return true }
            if entry.count >= nearMatchMinLength, !entry.contains(where: \.isASCII),
               editDistance(chars, entry, limit: 1) <= 1 { return true }
        }
        return false
    }

    private static func isRepetition(_ chars: [Character], of entry: [Character]) -> Bool {
        guard chars.count >= entry.count * 2, chars.count % entry.count == 0 else { return false }
        return stride(from: 0, to: chars.count, by: entry.count).allSatisfy {
            Array(chars[$0..<($0 + entry.count)]) == entry
        }
    }

    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            if cur.min()! > limit { return limit + 1 }
            prev = cur
        }
        return prev[b.count]
    }

    static func localCompressionRatio(_ text: String) -> Double? {
        guard text.filter({ !$0.isWhitespace }).count >= repetitionMinCharacters else { return nil }
        let data = Data(text.utf8)
        guard let compressed = try? (data as NSData).compressed(using: .zlib) else { return nil }
        return Double(data.count) / Double(compressed.length + 6)
    }
}
