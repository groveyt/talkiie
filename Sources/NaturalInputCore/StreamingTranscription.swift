import Foundation

@MainActor
public final class StreamingTranscription {
    public struct ChunkReport: Equatable, Sendable {
        public let index: Int
        public let millis: Int
        public let succeeded: Bool
        public let isTail: Bool
        public var timing: RequestTiming? = nil
        public var queuedMillis: Int? = nil
        public var startDelayMillis: Int? = nil
        public var speculative: Bool = false
        public var shortPaddingMillis: Int? = nil
    }

    public struct Speculation: Equatable, Sendable {
        public var minIntervalSeconds: Double
        public var pauseSeconds: Double
        public var maxUncoveredSeconds: Double

        public init(minIntervalSeconds: Double, pauseSeconds: Double, maxUncoveredSeconds: Double) {
            self.minIntervalSeconds = minIntervalSeconds
            self.pauseSeconds = pauseSeconds
            self.maxUncoveredSeconds = maxUncoveredSeconds
        }
    }

    public var speculation: Speculation?
    public internal(set) var speculativeSends = 0
    public private(set) var tailFromSpeculation = false

    public struct StopSummary: Equatable, Sendable {
        public let isEmpty: Bool
        public let tailSent: Bool
        public let chunksSent: Int
        public let inFlight: Int
        public let level: AudioLevelSummary
        public var tailFromSpeculation: Bool = false
        public var speculativeSends: Int = 0
        public var uncoveredFrames: Int? = nil
    }

    public var onChunkFinished: ((ChunkReport) -> Void)?

    public struct RetryReport: Equatable, Sendable {
        public let index: Int
        public let succeeded: Bool
        public let firstError: TranscriptionFailureKind
        public let millis: Int
    }
    public var onChunkRetry: ((RetryReport) -> Void)?
    public var retryBackoff: Duration = .milliseconds(250)
    public static let retryMaxFirstAttemptMillis = 5_000
    public var onPunctuation: ((PunctuationReport) -> Void)?
    public struct DictionaryReport: Equatable, Sendable {
        public var replacements: Int
        public var fuzzyReplacements: Int
        public var promptTerms: Int
        public var promptWithheldChunks: Int
        public var promptManual: Int = 0
        public var promptLearned: Int = 0
        public var promptDropped: Int = 0
        public var promptGated: Int = 0
        public var promptTokens: Int = 0
        public var spellingReplacements: Int = 0
    }
    public var onPersonalDictionary: ((DictionaryReport) -> Void)?
    public var fillerStrength: FillerStrength = FillerRemoval.defaultStrength
    public var spokenLists: Bool = SpokenList.defaultEnabled
    public var listToggle: Bool = false
    public private(set) var listToggleOffer: ListToggleOffer?
    public var spokenCommands: Bool = SpokenCommands.defaultEnabled
    public var paragraphStrength: ParagraphStrength = SemanticParagraphs.defaultStrength
    public var onFillerRemoval: ((FillerRemoval.Report) -> Void)?
    #if DEBUG
    public struct DebugTexts: Equatable, Sendable {
        public let whisper: String
        public let withoutModel: String
        public let final: String
        public let punctuation: PunctuationReport?
        public init(whisper: String, withoutModel: String, final: String, punctuation: PunctuationReport?) {
            self.whisper = whisper
            self.withoutModel = withoutModel
            self.final = final
            self.punctuation = punctuation
        }
    }
    public private(set) var debugTexts: DebugTexts?

    public struct DebugProvenance: Equatable, Sendable {
        public struct ChunkPrompt: Equatable, Sendable {
            public let index: Int
            public let tail: Bool
            public let sent: Bool
            public init(index: Int, tail: Bool, sent: Bool) { self.index = index; self.tail = tail; self.sent = sent }
        }
        public let promptTerms: [String]
        public let promptCounts: TranscriptionPrompt.Counts
        public let shortUtterancePrompt: Bool
        public let chunks: [ChunkPrompt]
        public let fillerStrength: FillerStrength
        public let spokenLists: Bool
        public let spokenCommands: Bool
        public let paragraphStrength: ParagraphStrength
        public init(promptTerms: [String], promptCounts: TranscriptionPrompt.Counts, shortUtterancePrompt: Bool,
                    chunks: [ChunkPrompt], fillerStrength: FillerStrength, spokenLists: Bool, spokenCommands: Bool,
                    paragraphStrength: ParagraphStrength) {
            self.promptTerms = promptTerms; self.promptCounts = promptCounts
            self.shortUtterancePrompt = shortUtterancePrompt; self.chunks = chunks
            self.fillerStrength = fillerStrength; self.spokenLists = spokenLists
            self.spokenCommands = spokenCommands; self.paragraphStrength = paragraphStrength
        }
    }
    public private(set) var debugProvenance: DebugProvenance?
    public private(set) var debugConfidence: [SegmentConfidence]?
    #endif
    public var onChunkSending: ((UnsafeBufferPointer<Float>) -> Void)?
    public private(set) var chunker = SpeechChunker()
    public private(set) var isCancelled = false
    public private(set) var isStopped = false

    private let transcriber: any SegmentTranscriber
    private let punctuator: (any Punctuator)?
    private let dictionary: PersonalDictionary
    public let prompt: TranscriptionPrompt
    private let shortPrompt: TranscriptionPrompt
    private var promptWithheldChunks = 0
    private let sampleRate: Int
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant
    private var chunks: [Chunk] = []
    var speculative: Chunk?
    var speculatedThrough: Int?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var level = AudioLevelSummary(samples: [])
    private var firstFailure: String?
    private var formatted: String?

    public init(transcriber: any SegmentTranscriber, punctuator: (any Punctuator)? = nil,
                dictionary: PersonalDictionary = .empty, sampleRate: Int = AudioBuffer.sampleRate) {
        self.transcriber = transcriber
        self.punctuator = punctuator
        self.dictionary = dictionary
        self.prompt = TranscriptionPrompt(dictionary: dictionary)
        self.shortPrompt = TranscriptionPrompt(dictionary: dictionary, minimumTerms: ShortUtterance.promptMinimumTerms)
        self.sampleRate = sampleRate
        origin = clock.now
    }

    public var chunksSent: Int { chunks.count }
    public var inFlight: Int { chunks.filter { $0.result == nil }.count }
    public var hasFailed: Bool { firstFailure != nil }

    @discardableResult
    public func ingested(levels: [Float], pipeline: AudioPipeline) -> SpeechChunker.Cut? {
        guard !isStopped, !isCancelled else { return nil }
        let cut = chunker.observe(levels: levels, endFrame: pipeline.endFrame)
        guard !hasFailed else { return nil }
        if let cut {
            dropSpeculation()
            speculatedThrough = nil
            let part = pipeline.takePrefix(upTo: cut.frame)
            send(part.samples, startFrame: part.startFrame, isTail: false)
        } else if speculation != nil {
            speculateIfDue(pipeline)
        }
        releaseHeld(through: pipeline.endFrame)
        return cut
    }

    public var egressHoldSeconds: Double = 0
    private var holdFrames: Int { egressHoldSeconds > 0 ? SpeechChunker.frames(egressHoldSeconds) : 0 }

    public var speculationHoldSeconds: Double?
    var specHoldFrames: Int {
        guard let s = speculationHoldSeconds else { return holdFrames }
        return s > 0 ? SpeechChunker.frames(s) : 0
    }

    private func releaseHeld(through endFrame: Int) {
        for c in chunks where c.isHeld {
            guard c.endFrame + holdFrames <= endFrame else { break }
            transmit(c)
        }
        if let spec = speculative, spec.isHeld {
            if let lastSpeech = chunker.lastSpeechEndFrame, lastSpeech > spec.endFrame {
                dropSpeculation()
            } else if spec.endFrame + specHoldFrames <= endFrame {
                transmit(spec)
            }
        }
    }

    func dropSpeculation() {
        speculative?.task?.cancel()
        speculative?.discardHeldSamples()
        speculative = nil
    }

    public func stop(pipeline: AudioPipeline, cutoffFrame: Int? = nil) -> StopSummary {
        let part = pipeline.takeTailAndWipe()
        var tail = part.samples
        return stop(tail: &tail, startFrame: part.startFrame, cutoffFrame: cutoffFrame)
    }

    public func stop(tail: inout [Float], startFrame: Int, cutoffFrame: Int? = nil) -> StopSummary {
        isStopped = true
        if let cutoffFrame { Self.keepPrefix(&tail, count: cutoffFrame - startFrame) }
        settleHeld(cutoffFrame: cutoffFrame)
        let isEmpty = chunks.isEmpty && tail.isEmpty
        let sendTail = !isCancelled && !hasFailed && !isEmpty
            && chunker.shouldSendTail(chunksSent: chunks.count)
        let adopted = sendTail ? usableSpeculation(tail: tail, tailStart: startFrame) : nil
        let uncoveredFrames = adopted != nil ? speculatedThrough.map { startFrame + tail.count - $0 } : nil
        if adopted == nil { dropSpeculation() }
        if let adopted {
            speculative = nil
            tailFromSpeculation = true
            level = level.merged(with: AudioLevelSummary(samples: tail, sampleRate: sampleRate))
            AudioPipeline.zeroize(&tail)
            tail = []
            adopt(adopted)
        } else if sendTail {
            let owned = tail
            tail = []
            send(owned, startFrame: startFrame, isTail: true)
        } else {
            level = level.merged(with: AudioLevelSummary(samples: tail, sampleRate: sampleRate))
            AudioPipeline.zeroize(&tail)
            tail = []
        }
        wakeIfSettled()
        return StopSummary(isEmpty: isEmpty, tailSent: sendTail, chunksSent: chunks.count,
                           inFlight: inFlight, level: level, tailFromSpeculation: tailFromSpeculation,
                           speculativeSends: speculativeSends, uncoveredFrames: uncoveredFrames)
    }

    private func settleHeld(cutoffFrame: Int?) {
        let held = chunks.filter(\.isHeld)
        guard !held.isEmpty else { return }
        for c in held {
            if isCancelled || hasFailed {
                c.discardHeldSamples()
                chunks.removeAll { $0 === c }
                continue
            }
            if let cutoffFrame, c.endFrame > cutoffFrame {
                guard c.startFrame < cutoffFrame else {
                    c.discardHeldSamples()
                    chunks.removeAll { $0 === c }
                    continue
                }
                c.shortenHeldSamples(keeping: cutoffFrame - c.startFrame)
            }
            transmit(c)
        }
    }

    static func keepPrefix(_ samples: inout [Float], count keeping: Int) {
        let keep = max(0, keeping)
        guard keep < samples.count else { return }
        samples.withUnsafeMutableBufferPointer { buf in
            for i in keep..<buf.count { buf[i] = 0 }
        }
        samples.removeLast(samples.count - keep)
    }

    public func outcome() async -> TranscriptionOutcome? {
        while !isSettled {
            await withCheckedContinuation { waiters.append($0) }
        }
        if isCancelled { return nil }
        if let firstFailure {
            #if DEBUG
            debugProvenance = makeDebugProvenance(shortRound: chunks.count == 1 && !chunks[0].padding.isNone)
            debugConfidence = makeDebugConfidence()
            #endif
            return .failed(firstFailure)
        }
        if let formatted { return .text(formatted) }
        let parts: [(offset: Double, segments: [TranscriptSegment])] = chunks.map { c in
            guard case .segments(let s) = c.result else { return (c.offsetSeconds, []) }
            return (c.offsetSeconds, s)
        }
        let merged = Self.merge(parts)
        let shortRound = chunks.count == 1 && !chunks[0].padding.isNone
        let fuzzyThreshold = shortRound ? ShortUtterance.fuzzyThreshold : PersonalDictionary.fuzzyThreshold
        let (segments, replaced, fuzzy, spelled) = dictionary.applyReporting(to: merged, fuzzyThreshold: fuzzyThreshold)
        let (text, report, fillers, offer) = await punctuated(segments)
        if isCancelled { return nil }
        if let formatted { return .text(formatted) }
        formatted = text
        listToggleOffer = offer
        if dictionary.hasUsableEntries {
            let used = shortRound ? shortPrompt : prompt
            onPersonalDictionary?(DictionaryReport(replacements: replaced, fuzzyReplacements: fuzzy,
                                                   promptTerms: used.terms.count,
                                                   promptWithheldChunks: promptWithheldChunks,
                                                   promptManual: used.counts.manual, promptLearned: used.counts.learned,
                                                   promptDropped: used.counts.dropped, promptGated: used.counts.gated,
                                                   promptTokens: used.counts.tokens, spellingReplacements: spelled))
        }
        if let report { onPunctuation?(report) }
        if let fillers { onFillerRemoval?(fillers) }
        #if DEBUG
        debugProvenance = makeDebugProvenance(shortRound: shortRound)
        debugConfidence = makeDebugConfidence()
        debugTexts = DebugTexts(whisper: merged.map(\.text).joined(),
                                withoutModel: TranscriptFormatter.format(segments, fillers: fillerStrength,
                                                                         spokenLists: spokenLists,
                                                                         paragraphing: paragraphStrength,
                                                                         spokenCommands: spokenCommands),
                                final: text, punctuation: report)
        #endif
        return .text(text)
    }

    #if DEBUG
    private func makeDebugConfidence() -> [SegmentConfidence]? {
        let sent = chunks.filter { $0.sentAt != nil && $0.counts }.sorted { $0.index < $1.index }
        guard !sent.isEmpty else { return nil }
        return sent.flatMap { c in
            (c.segmentConfidences ?? []).map { $0.placed(chunk: c.index, offsetSeconds: c.offsetSeconds) }
        }
    }

    private func makeDebugProvenance(shortRound: Bool) -> DebugProvenance? {
        let sent = chunks.filter { $0.sentAt != nil }.sorted { $0.index < $1.index }
        guard !sent.isEmpty else { return nil }
        let used = shortRound ? shortPrompt : prompt
        return DebugProvenance(
            promptTerms: used.terms, promptCounts: used.counts, shortUtterancePrompt: shortRound,
            chunks: sent.map { DebugProvenance.ChunkPrompt(index: $0.index, tail: $0.isTail, sent: $0.promptSent) },
            fillerStrength: fillerStrength, spokenLists: spokenLists, spokenCommands: spokenCommands,
            paragraphStrength: paragraphStrength)
    }
    #endif

    private func punctuated(_ segments: [TranscriptSegment]) async
        -> (String, PunctuationReport?, FillerRemoval.Report?, ListToggleOffer?) {
        let strength = fillerStrength
        let lists = spokenLists
        let paragraphing = paragraphStrength
        let commands = spokenCommands
        let toggle = listToggle
        func offer(_ render: (ListLayoutMode) -> (text: String, hasList: Bool)) -> ListToggleOffer? {
            ListToggle.offer(spokenLists: lists, toggleEnabled: toggle, render: render)
        }
        func pauseRender(_ mode: ListLayoutMode) -> (text: String, hasList: Bool) {
            let f = TranscriptFormatter.finish(TranscriptFormatter.pauseText(segments), fillers: strength,
                                               spokenLists: mode != .plain, paragraphing: paragraphing,
                                               spokenCommands: commands, looseLists: mode == .loose)
            return (f.text, f.hasList)
        }
        func pause(_ report: PunctuationReport?) -> (String, PunctuationReport?, FillerRemoval.Report?, ListToggleOffer?) {
            let f = TranscriptFormatter.formatReporting(segments, fillers: strength, spokenLists: lists,
                                                        paragraphing: paragraphing, spokenCommands: commands)
            return (f.text, report, f.fillers, offer(pauseRender))
        }
        guard let punctuator, let source = TranscriptFormatter.punctuationSource(segments) else {
            return pause(nil)
        }
        guard source.units >= TranscriptFormatter.punctuationMinUnits else {
            return pause(PunctuationReport(applied: false, fallback: .tooShort))
        }
        let started = clock.now
        let reply = await punctuator.punctuate(source.request)
        let millis = RequestTiming.millis(clock.now - started)
        switch reply {
        case .failed(let reason):
            return pause(PunctuationReport(applied: false, fallback: reason, millis: millis))
        case .suggestion(let output):
            let p = TranscriptFormatter.format(segments, modelOutput: output, fillers: strength, spokenLists: lists,
                                               paragraphing: paragraphing, spokenCommands: commands)
            let alternate = offer { mode in
                let q = TranscriptFormatter.format(segments, modelOutput: output, policy: TranscriptFormatter.defaultWhisperPolicy,
                                                   fillers: strength, spokenLists: mode != .plain,
                                                   paragraphing: paragraphing, spokenCommands: commands,
                                                   looseLists: mode == .loose)
                return (q.text, q.hasList)
            }
            return (p.text, PunctuationReport(applied: p.applied, fallback: p.fallback, millis: millis,
                                              marks: p.marks, alignedPercent: p.alignedPercent), p.fillers, alternate)
        }
    }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        for c in chunks { c.task?.cancel(); c.discardHeldSamples() }
        dropSpeculation()
        wake()
    }

    public static func merge(_ parts: [(offset: Double, segments: [TranscriptSegment])]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        for part in parts {
            var atJoin = true
            for s in part.segments {
                guard s.text.contains(where: { !$0.isWhitespace }) else { continue }
                let seg = TranscriptSegment(text: s.text, start: s.start + part.offset, end: s.end + part.offset)
                if atJoin, let prev = out.last, let joined = TranscriptFormatter.joinedAcrossChunks(prev, seg) {
                    out[out.count - 1] = joined
                } else {
                    out.append(seg)
                }
                atJoin = false
            }
        }
        return out
    }

    @MainActor final class Chunk {
        var index: Int
        let startFrame: Int
        private(set) var endFrame: Int
        let offsetSeconds: Double
        let isTail: Bool
        let isSpeculative: Bool
        var promptWithheld = false
        var promptSent = false
        var padding: SilencePadding = .none
        private(set) var held: SampleBox?
        var isHeld: Bool { held != nil }
        var adopted = false
        var result: SegmentTranscription?
        var task: Task<Void, Never>?
        var sentAt: Double?
        var startedAt: Double?
        var finishedAt: Double?
        var early: (millis: Int, timing: RequestTiming?)?
        #if DEBUG
        var segmentConfidences: [SegmentConfidence]?
        #endif
        init(index: Int, startFrame: Int, samples: SampleBox, offsetSeconds: Double, isTail: Bool, isSpeculative: Bool) {
            self.index = index
            self.startFrame = startFrame
            self.endFrame = startFrame + samples.samples.count
            self.held = samples
            self.offsetSeconds = offsetSeconds
            self.isTail = isTail
            self.isSpeculative = isSpeculative
        }
        func takeHeldSamples() -> SampleBox? {
            defer { held = nil }
            return held
        }
        func discardHeldSamples() {
            held?.zeroize()
            held = nil
        }
        func shortenHeldSamples(keeping: Int) {
            held?.keepPrefix(keeping)
            endFrame = startFrame + (held?.samples.count ?? 0)
        }
        var counts: Bool { !isSpeculative || adopted }
    }

    func send(_ samples: [Float], startFrame: Int, isTail: Bool) {
        let chunk = makeChunk(samples, startFrame: startFrame, isTail: isTail, speculative: false)
        chunks.append(chunk)
        if isTail || holdFrames == 0 { transmit(chunk) }
    }

    func makeChunk(_ samples: [Float], startFrame: Int, isTail: Bool, speculative: Bool) -> Chunk {
        Chunk(index: speculative ? -1 : chunks.count, startFrame: startFrame, samples: SampleBox(samples),
              offsetSeconds: Double(startFrame) / Double(sampleRate), isTail: isTail, isSpeculative: speculative)
    }

    func transmit(_ chunk: Chunk) {
        guard let box = chunk.takeHeldSamples() else { return }
        let speculative = chunk.isSpeculative
        if !speculative, let onChunkSending { box.samples.withUnsafeBufferPointer { onChunkSending($0) } }
        let chunkLevel = AudioLevelSummary(samples: box.samples, sampleRate: sampleRate)
        if !speculative { level = level.merged(with: chunkLevel) }
        let isOnlyChunk = chunks.allSatisfy { $0 === chunk }
        let padding = (chunk.isTail && isOnlyChunk)
            ? ShortUtterance.padding(forSeconds: chunkLevel.seconds, sampleRate: sampleRate) : SilencePadding.none
        chunk.padding = padding
        let basePrompt = padding.isNone ? prompt : shortPrompt
        let chunkPrompt = basePrompt.forChunk(chunkLevel)
        let withheld = chunkPrompt.isEmpty && !basePrompt.isEmpty
        chunk.promptWithheld = withheld
        chunk.promptSent = !chunkPrompt.isEmpty
        if withheld, !speculative { promptWithheldChunks += 1 }
        let transcriber = self.transcriber
        let attempt: TranscriptionAttempt = speculative ? .speculative : .regular
        let clock = self.clock, origin = self.origin
        chunk.sentAt = (clock.now - origin) / .seconds(1)
        chunk.task = Task { [weak self] in
            guard !Task.isCancelled else { box.zeroize(); return }
            let started = clock.now
            self?.started(chunk, at: (started - origin) / .seconds(1))
            var (result, timing) = await transcriber.transcribeSegmentsTimed(box.samples, prompt: chunkPrompt, attempt: attempt,
                                                                             padding: padding)
            if case .retryableFailure(_, let kind) = result, attempt == .regular,
               let backoff = self?.retryBackoff,
               Int(((clock.now - started) / .milliseconds(1)).rounded()) <= Self.retryMaxFirstAttemptMillis {
                try? await Task.sleep(for: backoff)
                if self?.mayRetry == true {
                    let retryStarted = clock.now
                    (result, timing) = await transcriber.transcribeSegmentsTimed(box.samples, prompt: chunkPrompt, attempt: .retry,
                                                                                 padding: padding)
                    let retryMillis = Int(((clock.now - retryStarted) / .milliseconds(1)).rounded())
                    var ok = false
                    if case .segments = result { ok = true }
                    if !Task.isCancelled {
                        self?.onChunkRetry?(RetryReport(index: chunk.index, succeeded: ok, firstError: kind, millis: retryMillis))
                    }
                }
            }
            if case .retryableFailure(let message, _) = result { result = .failed(message) }
            box.zeroize()
            let finished = clock.now
            let millis = Int(((finished - started) / .milliseconds(1)).rounded())
            self?.complete(chunk, result, millis: millis, timing: timing, finishedAt: (finished - origin) / .seconds(1))
        }
    }

    private func adopt(_ chunk: Chunk) {
        chunk.adopted = true
        chunk.index = chunks.count
        chunks.append(chunk)
        if chunk.promptWithheld { promptWithheldChunks += 1 }
        if let result = chunk.result, let early = chunk.early {
            chunk.result = nil
            chunk.early = nil
            complete(chunk, result, millis: early.millis, timing: early.timing, finishedAt: chunk.finishedAt)
        }
    }

    private func started(_ chunk: Chunk, at seconds: Double) { chunk.startedAt = seconds }

    private func complete(_ chunk: Chunk, _ result: SegmentTranscription, millis: Int,
                          timing: RequestTiming? = nil, finishedAt: Double? = nil) {
        guard !isCancelled else { return }
        guard chunk.counts else {
            guard speculative === chunk else { return }
            if case .failed = result { speculative = nil; return }
            chunk.result = result
            chunk.finishedAt = finishedAt
            chunk.early = (millis, timing)
            return
        }
        let wasFailed = hasFailed
        chunk.result = result
        #if DEBUG
        chunk.segmentConfidences = timing?.segmentConfidences
        #endif
        chunk.finishedAt = finishedAt
        let ok: Bool = { if case .segments = result { return true } else { return false } }()
        var report = ChunkReport(index: chunk.index, millis: millis, succeeded: ok, isTail: chunk.isTail)
        report.timing = timing
        report.speculative = chunk.isSpeculative
        if !chunk.padding.isNone { report.shortPaddingMillis = chunk.padding.totalMillis }
        if !chunk.isSpeculative, let sentAt = chunk.sentAt, let startedAt = chunk.startedAt, startedAt >= sentAt {
            report.startDelayMillis = Int(((startedAt - sentAt) * 1000).rounded())
        }
        if chunk.isTail, let startedAt = chunk.startedAt, let finishedAt {
            let uploadStartedAt = min(startedAt + Double(timing?.prepMillis ?? 0) / 1000, finishedAt)
            report.queuedMillis = LatencyTimeline.queuedMillis(
                tailStartedAt: uploadStartedAt, tailFinishedAt: finishedAt,
                earlierFinishedAt: chunks.filter { $0.index < chunk.index }.map(\.finishedAt))
        }
        onChunkFinished?(report)
        if case .failed(let message) = result, !wasFailed {
            firstFailure = message
            for c in chunks where c.result == nil { c.task?.cancel(); c.discardHeldSamples() }
            dropSpeculation()
        }
        wakeIfSettled()
    }

    private var mayRetry: Bool { !isCancelled && !hasFailed }

    private var isSettled: Bool {
        isCancelled || hasFailed || (isStopped && chunks.allSatisfy { $0.result != nil })
    }

    private func wakeIfSettled() { if isSettled { wake() } }

    private func wake() {
        let w = waiters
        waiters = []
        for c in w { c.resume() }
    }
}

@MainActor
final class SampleBox {
    private(set) var samples: [Float]
    init(_ samples: [Float]) { self.samples = samples }
    func zeroize() {
        AudioPipeline.zeroize(&samples)
        samples = []
    }
    func keepPrefix(_ keeping: Int) { StreamingTranscription.keepPrefix(&samples, count: keeping) }
}
