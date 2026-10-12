import Foundation

public enum WrittenStyleMode: String, CaseIterable, Sendable {
    case cautious
    case aggressive

    public var title: String {
        switch self {
        case .cautious: return "謹慎（只刪贅字）"
        case .aggressive: return "積極（改寫，可能改到原意）"
        }
    }

    public var detail: String {
        switch self {
        case .cautious:
            return "只刪掉贅字與重複的字，不改寫、不換字；否定詞、數字、英文與問句不會被刪，不確定就照原樣打。"
        case .aggressive:
            return "會把句子改寫得更像書面語，可能改到你的原意；改壞了可以從選單列「最近口述」插入原文。"
        }
    }
}

public enum WrittenStyle {
    public static let enabledDefaultsKey = "writtenStyleEnabled"
    public static let defaultEnabled = false
    public static let modeDefaultsKey = "writtenStyleMode"
    public static let defaultMode = WrittenStyleMode.cautious

    public static func enabled(fromDefaults value: Any?) -> Bool {
        (value as? Bool) ?? defaultEnabled
    }

    public static let offeredModes: [WrittenStyleMode] = [.cautious]

    public static let example = "我覺得，呃，這家麵店其實還不錯啦，就是湯頭的部分可能要再淡一點這樣。"
    public static let exampleSuggestion = "我覺得這家麵店還不錯，湯頭的部分可能要再淡一點。"

    public static var exampleResult: String {
        if case .accepted(let text) = RewriteGuard.check(mode: .cautious, original: example, suggestion: exampleSuggestion) {
            return text
        }
        return example
    }

    public static func mode(fromDefaults raw: String?) -> WrittenStyleMode {
        guard let m = raw.flatMap(WrittenStyleMode.init(rawValue:)), offeredModes.contains(m) else { return defaultMode }
        return m
    }

    public static func roundMode(enabled: Any?, mode: String?) -> WrittenStyleMode? {
        WrittenStyle.enabled(fromDefaults: enabled) ? WrittenStyle.mode(fromDefaults: mode) : nil
    }

    public static let minUnits = 15
    public static let maxCharacters = 500

    public static func timeout(mode: WrittenStyleMode, characters: Int) -> TimeInterval {
        let n = Double(max(0, characters))
        switch mode {
        case .cautious: return min(0.8 + 0.020 * n, maxTimeout(.cautious))
        case .aggressive: return min(2.0 + 0.060 * n, maxTimeout(.aggressive))
        }
    }

    public static func maxTimeout(_ mode: WrittenStyleMode) -> TimeInterval {
        mode == .cautious ? 2 : 10
    }

    public static let warmUpTimeout: TimeInterval = 1.5

    public static let readinessGrace: TimeInterval = 1
    public static let serverIdleSeconds: TimeInterval = 10 * 60
    public static let assumeLoadedWindow: TimeInterval = serverIdleSeconds - 2 * 60

    public struct Budget: Equatable, Sendable {
        public let sendReadiness: Bool
        public let readinessTimeout: TimeInterval
        public let inferenceTimeout: TimeInterval
        public var worstCase: TimeInterval { readinessTimeout + inferenceTimeout }
    }

    public struct Warmth: Equatable, Sendable {
        public let mode: WrittenStyleMode
        public let at: Date
        public init(mode: WrittenStyleMode, at: Date) {
            self.mode = mode
            self.at = at
        }
    }

    public static func budget(mode: WrittenStyleMode, characters: Int, lastSuccess: Warmth?, now: Date) -> Budget {
        let inference = timeout(mode: mode, characters: characters)
        if let w = lastSuccess, w.mode == mode, now >= w.at, now.timeIntervalSince(w.at) < assumeLoadedWindow {
            return Budget(sendReadiness: false, readinessTimeout: 0, inferenceTimeout: inference)
        }
        return Budget(sendReadiness: true, readinessTimeout: readinessGrace, inferenceTimeout: inference)
    }

    public static func worstCase(mode: WrittenStyleMode, characters: Int) -> TimeInterval {
        readinessGrace + timeout(mode: mode, characters: characters)
    }
}

public protocol Rewriter: Sendable {
    func rewrite(_ text: String, mode: WrittenStyleMode) async -> RewriteReply
    func warmUp(mode: WrittenStyleMode) async
}

public enum RewriteReply: Equatable, Sendable {
    case suggestion(String)
    case failed(RewriteFallback)
}

public enum RewriteFallback: String, Equatable, Sendable, CaseIterable {
    case disabled
    case tooShort
    case tooLong
    case lateRound
    case notIssued
    case tailnetDown
    case logUnavailable
    case timeout
    case loadTimeout
    case network
    case badStatus
    case malformed
    case rejected
    case unchanged
}

public enum RewriteRejection: String, Equatable, Sendable, CaseIterable {
    case empty
    case notSubsequence
    case tooMuchDeleted
    case negationDeleted
    case scopeWordDeleted
    case degreeWordDeleted
    case numberChanged
    case asciiChanged
    case questionChanged
    case interrogativeDeleted
    case keepWordDeleted
    case clauseDeleted
    case lineDeleted
    case gotLonger
    case simplifiedIntroduced
    case negationChanged
    case tooManyNewCharacters
    case lineStructure
}

public struct RewriteReport: Equatable, Sendable {
    public var mode: WrittenStyleMode
    public var applied: Bool
    public var fallback: RewriteFallback?
    public var rejection: RewriteRejection?
    public var millis: Int?
    public var changedPercent: Int?

    public init(mode: WrittenStyleMode, applied: Bool, fallback: RewriteFallback?, rejection: RewriteRejection? = nil,
                millis: Int? = nil, changedPercent: Int? = nil) {
        self.mode = mode
        self.applied = applied
        self.fallback = fallback
        self.rejection = rejection
        self.millis = millis
        self.changedPercent = changedPercent
    }
}

public struct WrittenStyleResult: Equatable, Sendable {
    public let text: String
    public let original: String?
    public let report: RewriteReport
}

public enum WrittenStyleRound {
    public static func run(_ text: String, mode: WrittenStyleMode, keepWords: [String] = [],
                           rewriter: (any Rewriter)?, budget: TimeInterval? = nil) async -> WrittenStyleResult {
        func original(_ f: RewriteFallback, rejection: RewriteRejection? = nil, millis: Int? = nil,
                      changed: Int? = nil) -> WrittenStyleResult {
            WrittenStyleResult(text: text, original: nil,
                               report: RewriteReport(mode: mode, applied: false, fallback: f, rejection: rejection,
                                                     millis: millis, changedPercent: changed))
        }
        guard let rewriter else { return original(.disabled) }
        guard TranscriptFormatter.countUnits(text) >= WrittenStyle.minUnits else { return original(.tooShort) }
        guard text.count <= WrittenStyle.maxCharacters else { return original(.tooLong) }
        if let budget, budget < WrittenStyle.worstCase(mode: mode, characters: text.count) + 1 { return original(.lateRound) }

        let started = DispatchTime.now().uptimeNanoseconds
        let reply = await rewriter.rewrite(text, mode: mode)
        let millis = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
        switch reply {
        case .failed(let f):
            return original(f, millis: millis)
        case .suggestion(let s):
            let verdict = RewriteGuard.check(mode: mode, original: text, suggestion: s, keepWords: keepWords)
            switch verdict {
            case .unchanged:
                return original(.unchanged, millis: millis, changed: 0)
            case .rejected(let r):
                return original(.rejected, rejection: r, millis: millis,
                                changed: RewriteGuard.changedPercent(original: text, result: s))
            case .accepted(let out):
                return WrittenStyleResult(
                    text: out, original: text,
                    report: RewriteReport(mode: mode, applied: true, fallback: nil, millis: millis,
                                          changedPercent: RewriteGuard.changedPercent(original: text, result: out)))
            }
        }
    }

    public static func warmUp(mode: WrittenStyleMode, rewriter: (any Rewriter)?) async {
        await rewriter?.warmUp(mode: mode)
    }
}
