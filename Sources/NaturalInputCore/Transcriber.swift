public protocol Transcriber: Sendable {
    func transcribe(_ samples: [Float]) async -> TranscriptionOutcome
}

public enum TranscriptionOutcome: Equatable, Sendable {
    case text(String)
    case failed(String)
}

public struct UnimplementedTranscriber: Transcriber {
    public static let message = "轉錄尚未實作（M3），這段口述已丟棄"

    public init() {}

    public func transcribe(_ samples: [Float]) async -> TranscriptionOutcome {
        .failed(Self.message)
    }
}

extension UnimplementedTranscriber: SegmentTranscriber {
    public func transcribeSegments(_ samples: [Float]) async -> SegmentTranscription {
        .failed(Self.message)
    }
}

public protocol SegmentTranscriber: Sendable {
    func transcribeSegments(_ samples: [Float]) async -> SegmentTranscription
    func transcribeSegmentsTimed(_ samples: [Float]) async -> (SegmentTranscription, RequestTiming?)
    func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt) async -> (SegmentTranscription, RequestTiming?)
    func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt,
                                 attempt: TranscriptionAttempt) async -> (SegmentTranscription, RequestTiming?)
    func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt,
                                 attempt: TranscriptionAttempt, padding: SilencePadding) async -> (SegmentTranscription, RequestTiming?)
}

public enum TranscriptionAttempt: String, Sendable, Equatable {
    case regular
    case speculative
    case retry
}

public enum TranscriptionFailureKind: String, Sendable, Equatable {
    case transport
    case serverError
}

extension SegmentTranscriber {
    public func transcribeSegmentsTimed(_ samples: [Float]) async -> (SegmentTranscription, RequestTiming?) {
        (await transcribeSegments(samples), nil)
    }

    public func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt) async -> (SegmentTranscription, RequestTiming?) {
        await transcribeSegmentsTimed(samples)
    }

    public func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt,
                                        attempt: TranscriptionAttempt) async -> (SegmentTranscription, RequestTiming?) {
        await transcribeSegmentsTimed(samples, prompt: prompt)
    }

    public func transcribeSegmentsTimed(_ samples: [Float], prompt: TranscriptionPrompt,
                                        attempt: TranscriptionAttempt, padding: SilencePadding) async -> (SegmentTranscription, RequestTiming?) {
        await transcribeSegmentsTimed(samples, prompt: prompt, attempt: attempt)
    }
}

public enum SegmentTranscription: Equatable, Sendable {
    case segments([TranscriptSegment])
    case failed(String)
    case retryableFailure(String, TranscriptionFailureKind)
}
