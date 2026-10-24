import Foundation
import NaturalInputCore
import whisper

public actor LocalWhisper: Transcriber, SegmentTranscriber {
    public static let failureMessage = "本機轉錄失敗，這段口述沒有轉錄"
    public static let sampleRate = 16_000
    public static let promptBeamSize: Int32 = 1
    public static let defaultIdleUnload: Duration = .seconds(180)

    public nonisolated let model: LocalWhisperModel
    public nonisolated let threads: Int32
    public internal(set) var idleUnloadAfter: Duration?
    private let skipPreflight: Bool

    private let queue: DispatchSerialQueue
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private var handle: WhisperHandle?
    private var useGeneration: UInt64 = 0
    var idleTask: Task<Void, Never>?

    public private(set) var lastLoad: LocalWhisperLoadReport?
    public private(set) var loadCount = 0
    public private(set) var lastRunReusedEncoder = false
    public private(set) var lastRunUsedPrompt = false

    public var isLoaded: Bool { handle != nil }

    var promptBeamSizeInUse: Int32 = LocalWhisper.promptBeamSize
    func setPromptBeamSizeForBench(_ n: Int32) { promptBeamSizeInUse = n }

    public init(model: LocalWhisperModel, threads: Int32 = 4,
                idleUnloadAfter: Duration? = LocalWhisper.defaultIdleUnload) {
        self.init(model: model, threads: threads, idleUnloadAfter: idleUnloadAfter, skipPreflight: false)
    }

    init(model: LocalWhisperModel, threads: Int32, idleUnloadAfter: Duration?, skipPreflight: Bool) {
        self.model = model
        self.threads = threads
        self.idleUnloadAfter = idleUnloadAfter
        self.skipPreflight = skipPreflight
        self.queue = DispatchSerialQueue(label: "talkiie.local-whisper", qos: .userInitiated)
    }

    @discardableResult
    public func prepare() throws(LocalWhisperError) -> LocalWhisperLoadReport? {
        useGeneration &+= 1
        defer { scheduleIdleUnload() }
        return try loadIfNeeded()
    }

    public func unload() {
        idleTask?.cancel()
        idleTask = nil
        handle = nil
    }

    @discardableResult
    private func loadIfNeeded() throws(LocalWhisperError) -> LocalWhisperLoadReport? {
        if handle != nil { return nil }
        if !skipPreflight { try model.preflight() }

        unsetenv("GGML_BACKTRACE_LLDB")
        unsetenv("GGML_METAL_CAPTURE_COMPUTE")
        WhisperLogTap.shared.install()

        var cp = whisper_context_default_params()
        cp.use_gpu = true
        cp.flash_attn = true
        cp.gpu_device = 0
        cp.dtw_token_timestamps = false

        let clock = ContinuousClock()
        let t0 = clock.now
        guard let ctx = whisper_init_from_file_with_params_no_state(model.modelURL.path, cp) else {
            throw .modelLoadFailed
        }
        let t1 = clock.now
        WhisperLogTap.shared.resetCoreML()
        guard let state = whisper_init_state(ctx) else {
            whisper_free(ctx)
            throw WhisperLogTap.shared.coreMLFailed ? .coreMLLoadFailed : .stateInitFailed
        }
        let t2 = clock.now
        handle = WhisperHandle(ctx: ctx, state: state)
        let report = LocalWhisperLoadReport(modelMillis: RequestTiming.millis(t1 - t0) ?? 0,
                                            stateMillis: RequestTiming.millis(t2 - t1) ?? 0)
        lastLoad = report
        loadCount += 1
        return report
    }

    func scheduleIdleUnload() {
        idleTask?.cancel()
        guard let after = idleUnloadAfter else { idleTask = nil; return }
        let generation = useGeneration
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: after)
            guard !Task.isCancelled else { return }
            await self?.unloadIfIdle(since: generation)
        }
    }

    private func unloadIfIdle(since generation: UInt64) {
        guard generation == useGeneration else { return }
        handle = nil
        idleTask = nil
    }

    public func transcribe(_ samples: [Float]) async -> TranscriptionOutcome {
        switch transcribeSegmentsTimedSync(samples, prompt: .empty).0 {
        case .segments(let segments): return .text(TranscriptFormatter.format(segments))
        case .failed(let message), .retryableFailure(let message, _): return .failed(message)
        }
    }

    public func transcribeSegments(_ samples: [Float]) async -> SegmentTranscription {
        transcribeSegmentsTimedSync(samples, prompt: .empty).0
    }

    public func transcribeSegmentsTimed(_ samples: [Float]) async -> (SegmentTranscription, RequestTiming?) {
        transcribeSegmentsTimedSync(samples, prompt: .empty)
    }

    public func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt) async -> (SegmentTranscription, RequestTiming?) {
        transcribeSegmentsTimedSync(samples, prompt: prompt)
    }

    public func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt,
                                        attempt: TranscriptionAttempt, padding: SilencePadding) async -> (SegmentTranscription, RequestTiming?) {
        transcribeSegmentsTimedSync(samples, prompt: prompt, padding: padding)
    }

    private func transcribeSegmentsTimedSync(_ samples: [Float], prompt: TranscriptionPrompt,
                                             padding: SilencePadding = .none) -> (SegmentTranscription, RequestTiming?) {
        useGeneration &+= 1
        defer { scheduleIdleUnload() }
        if Task.isCancelled { return (.failed(Self.failureMessage), nil) }

        let clock = ContinuousClock()
        let started = clock.now
        do {
            try loadIfNeeded()
        } catch {
            return (.failed(error.userMessage), nil)
        }
        guard let handle else { return (.failed(Self.failureMessage), nil) }

        let chunk = HallucinationFilter.Chunk(level: AudioLevelSummary(samples: samples, sampleRate: Self.sampleRate),
                                              prompt: prompt)

        let n = samples.count + padding.leadingFrames + padding.trailingFrames
        let buf = UnsafeMutablePointer<Float>.allocate(capacity: max(n, 1))
        buf.initialize(repeating: 0, count: n)
        samples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress { (buf + padding.leadingFrames).update(from: base, count: src.count) }
        }
        defer {
            buf.update(repeating: 0, count: n)
            buf.deallocate()
        }
        let language = strdup("auto")
        defer { free(language) }
        let promptText = prompt.isEmpty ? nil : strdup(prompt.text)
        defer { free(promptText) }
        let params = Self.fullParams(threads: threads, language: language, promptBeamSize: promptBeamSizeInUse,
                                     prompt: promptText, maxContext: Int32(prompt.maxContext))

        lastRunUsedPrompt = params.initial_prompt != nil
        let inferenceStarted = clock.now
        WhisperLogTap.shared.resetReuse()
        let rc = whisper_full_with_state(handle.ctx, handle.state, params, buf, Int32(n))
        lastRunReusedEncoder = WhisperLogTap.shared.reusedEncoder
        guard rc == 0 else { return (.failed(Self.failureMessage), nil) }

        let parseStarted = clock.now
        let candidates = Self.candidates(handle)
        let filtered = HallucinationFilter.filter(candidates, chunk: chunk)
        var timing = RequestTiming(prepMillis: RequestTiming.millis(inferenceStarted - started),
                                   networkMillis: RequestTiming.millis(parseStarted - inferenceStarted),
                                   parseMillis: RequestTiming.millis(clock.now - parseStarted),
                                   hallucinationDrops: filtered.drops)
        #if DEBUG
        timing.segmentConfidences = SegmentConfidence.make(candidates: candidates, chunk: chunk, padding: padding)
        #endif
        return (.segments(padding.unshifted(filtered.segments)), timing)
    }

    static func fullParams(threads: Int32, language: UnsafePointer<CChar>?,
                           promptBeamSize: Int32 = LocalWhisper.promptBeamSize,
                           prompt: UnsafePointer<CChar>? = nil, maxContext: Int32 = 0) -> whisper_full_params {
        let useBeam = prompt != nil && promptBeamSize > 1
        var p = whisper_full_default_params(useBeam ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY)
        p.strategy = useBeam ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
        p.n_threads = threads
        p.n_max_text_ctx = prompt == nil ? 0 : maxContext
        p.offset_ms = 0
        p.duration_ms = 0
        p.translate = false
        p.no_context = true
        p.no_timestamps = false
        p.single_segment = false
        p.print_special = false
        p.print_progress = false
        p.print_realtime = false
        p.print_timestamps = false
        p.token_timestamps = true
        p.thold_pt = 0.01
        p.max_len = 60
        p.split_on_word = false
        p.debug_mode = false
        p.audio_ctx = 0
        p.tdrz_enable = false
        p.initial_prompt = prompt
        p.carry_initial_prompt = false
        p.prompt_tokens = nil
        p.prompt_n_tokens = 0
        p.language = language
        p.detect_language = false
        p.suppress_nst = false
        p.temperature = 0
        p.temperature_inc = 0.2
        p.entropy_thold = 2.4
        p.logprob_thold = -1
        p.no_speech_thold = 0.6
        p.greedy.best_of = useBeam ? promptBeamSize : 2
        p.beam_search.beam_size = useBeam ? promptBeamSize : -1
        p.vad = false
        p.new_segment_callback = nil
        p.progress_callback = nil
        p.encoder_begin_callback = nil
        p.abort_callback = nil
        p.logits_filter_callback = nil
        return p
    }

    private static func candidates(_ h: WhisperHandle) -> [HallucinationFilter.Candidate] {
        let eot = whisper_token_eot(h.ctx)
        let count = whisper_full_n_segments_from_state(h.state)
        var out: [HallucinationFilter.Candidate] = []
        out.reserveCapacity(Int(max(count, 0)))
        for i in 0..<max(count, 0) {
            let text = whisper_full_get_segment_text_from_state(h.state, i).map { String(cString: $0) } ?? ""
            let t0 = Double(whisper_full_get_segment_t0_from_state(h.state, i)) * 0.01
            let t1 = Double(whisper_full_get_segment_t1_from_state(h.state, i)) * 0.01
            let nTokens = whisper_full_n_tokens_from_state(h.state, i)
            var logprob: Float = 0
            for j in 0..<max(nTokens, 0) {
                let token = whisper_full_get_token_data_from_state(h.state, i, j)
                if token.id >= eot { continue }
                logprob += token.plog
            }
            let avg = nTokens > 0 ? Double(logprob) / Double(nTokens) : Double.nan
            let noSpeech = Double(whisper_full_get_segment_no_speech_prob_from_state(h.state, i))
            var cand = HallucinationFilter.Candidate(
                segment: TranscriptSegment(text: text, start: t0, end: t1),
                noSpeechProb: noSpeech.isFinite ? noSpeech : nil,
                avgLogprob: avg.isFinite ? avg : nil,
                compressionRatio: nil)
            #if DEBUG
            cand.tokenCount = Int(max(nTokens, 0))
            #endif
            out.append(cand)
        }
        return out
    }
}

private final class WhisperHandle: @unchecked Sendable {
    let ctx: OpaquePointer
    let state: OpaquePointer

    init(ctx: OpaquePointer, state: OpaquePointer) {
        self.ctx = ctx
        self.state = state
    }

    deinit {
        whisper_free_state(state)
        whisper_free(ctx)
    }
}

private final class WhisperLogTap: @unchecked Sendable {
    static let shared = WhisperLogTap()

    private let lock = NSLock()
    private var _coreMLFailed = false
    private var _reusedEncoder = false

    var coreMLFailed: Bool { lock.withLock { _coreMLFailed } }
    var reusedEncoder: Bool { lock.withLock { _reusedEncoder } }
    func resetCoreML() { lock.withLock { _coreMLFailed = false } }
    func resetReuse() { lock.withLock { _reusedEncoder = false } }

    func install() {
        whisper_log_set({ _, text, _ in
            guard let text else { return }
            WhisperLogTap.shared.observe(text)
        }, nil)
    }

    private func observe(_ text: UnsafePointer<CChar>) {
        if strstr(text, "failed to load Core ML model") != nil { lock.withLock { _coreMLFailed = true } }
        if strstr(text, "reusing encoder output") != nil { lock.withLock { _reusedEncoder = true } }
    }
}
