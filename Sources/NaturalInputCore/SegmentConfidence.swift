#if DEBUG
import Foundation

public struct SegmentConfidence: Codable, Equatable, Sendable {
    public var chunk: Int
    public var startMs: Int
    public var endMs: Int
    public var avgLogprob: Double?
    public var noSpeechProb: Double?
    public var compressionRatio: Double?
    public var tokenCount: Int?
    public var dropped: Bool

    public init(chunk: Int, startMs: Int, endMs: Int, avgLogprob: Double?, noSpeechProb: Double?,
                compressionRatio: Double? = nil, tokenCount: Int? = nil, dropped: Bool) {
        self.chunk = chunk; self.startMs = startMs; self.endMs = endMs
        self.avgLogprob = avgLogprob; self.noSpeechProb = noSpeechProb
        self.compressionRatio = compressionRatio; self.tokenCount = tokenCount; self.dropped = dropped
    }

    public static func make(candidates: [HallucinationFilter.Candidate], chunk: HallucinationFilter.Chunk,
                            padding: SilencePadding) -> [SegmentConfidence] {
        candidates.map { c in
            let shifted = padding.unshifted([c.segment])[0]
            return SegmentConfidence(
                chunk: 0, startMs: Int((shifted.start * 1000).rounded()), endMs: Int((shifted.end * 1000).rounded()),
                avgLogprob: c.avgLogprob.flatMap { $0.isFinite ? $0 : nil },
                noSpeechProb: c.noSpeechProb.flatMap { $0.isFinite ? $0 : nil },
                compressionRatio: c.compressionRatio.flatMap { $0.isFinite ? $0 : nil },
                tokenCount: c.tokenCount,
                dropped: HallucinationFilter.reason(for: c, chunk: chunk) != nil)
        }
    }

    public func placed(chunk index: Int, offsetSeconds: Double) -> SegmentConfidence {
        var s = self
        s.chunk = index
        let o = Int((offsetSeconds * 1000).rounded())
        s.startMs += o; s.endMs += o
        return s
    }
}

public struct RoundConfidence: Codable, Equatable, Sendable {
    public var minAvgLogprob: Double?
    public var meanAvgLogprob: Double?
    public var maxNoSpeechProb: Double?
    public var segmentCount: Int
    public var droppedCount: Int

    public init(minAvgLogprob: Double?, meanAvgLogprob: Double?, maxNoSpeechProb: Double?,
                segmentCount: Int, droppedCount: Int) {
        self.minAvgLogprob = minAvgLogprob; self.meanAvgLogprob = meanAvgLogprob
        self.maxNoSpeechProb = maxNoSpeechProb
        self.segmentCount = segmentCount; self.droppedCount = droppedCount
    }

    public init(_ segments: [SegmentConfidence]) {
        let kept = segments.filter { !$0.dropped }
        let scored = kept.compactMap { s in s.avgLogprob.map { (lp: $0, w: Double(max(0, s.endMs - s.startMs))) } }
        minAvgLogprob = scored.map(\.lp).min()
        let totalWeight = scored.reduce(0) { $0 + $1.w }
        if scored.isEmpty {
            meanAvgLogprob = nil
        } else if totalWeight > 0 {
            meanAvgLogprob = scored.reduce(0) { $0 + $1.lp * $1.w } / totalWeight
        } else {
            meanAvgLogprob = scored.reduce(0) { $0 + $1.lp } / Double(scored.count)
        }
        maxNoSpeechProb = kept.compactMap(\.noSpeechProb).max()
        segmentCount = segments.count
        droppedCount = segments.count - kept.count
    }
}
#endif
