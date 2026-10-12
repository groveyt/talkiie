import Foundation

extension StreamingTranscription {
    func speculateIfDue(_ pipeline: AudioPipeline) {}

    func usableSpeculation(tail: [Float], tailStart: Int) -> Chunk? { nil }
}

extension StreamingTranscription.Speculation {
    public static let mac = Self(minIntervalSeconds: 0, pauseSeconds: 0, maxUncoveredSeconds: 0)
}
