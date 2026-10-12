import Foundation

public struct SpeechChunker: Sendable {
    public enum CutReason: String, Sendable, Equatable {
        case pause, forced
    }

    public struct Cut: Equatable, Sendable {
        public let frame: Int
        public let reason: CutReason
        public let frames: Int
    }

    public static let sampleRate = AudioBuffer.sampleRate

    public static let minChunkSeconds: Double = 15
    public static let minPauseSeconds: Double = 0.7
    public static let maxChunkSeconds: Double = 25
    public static let forcedSearchSeconds: Double = maxChunkSeconds - minChunkSeconds
    public static let quietSpanWindows = 5
    public static let minSpeechSeconds: Double = 0.5
    public static let minTailSpeechSeconds: Double = 0.1
    public static let speechMarginDB: Double = 12
    public static let thresholdMinDBFS: Double = -50
    public static let thresholdMaxDBFS: Double = -30
    public static let noisePercentile: Double = 0.10

    private struct Window {
        let start: Int
        let end: Int
        let db: Double
        let speech: Bool
        let audible: Bool
    }

    public private(set) var lastCutFrame = 0
    private var endFrame = 0
    private var windows: [Window] = []
    private var histogram = [Int](repeating: 0, count: 121)
    private var histogramTotal = 0
    private var quietRunStart: Int?
    private var speechFrames = 0
    private var audibleFrames = 0
    public private(set) var lastSpeechEndFrame: Int?

    public init() {}

    public var thresholdDBFS: Double {
        guard histogramTotal > 0 else { return Self.thresholdMinDBFS }
        let target = Int((Double(histogramTotal) * Self.noisePercentile).rounded(.up))
        var seen = 0
        var floorDB = 0.0
        for (i, n) in histogram.enumerated() {
            seen += n
            if seen >= max(1, target) { floorDB = Double(i - 120); break }
        }
        return min(Self.thresholdMaxDBFS, max(Self.thresholdMinDBFS, floorDB + Self.speechMarginDB))
    }

    public static let silenceMarginDB: Double = 6
    public static let silenceWindowFrames = frames(1.0 / 30)

    public var silenceThresholdDBFS: Double { thresholdDBFS - Self.silenceMarginDB }

    public func isSilent(_ samples: ArraySlice<Float>) -> Bool {
        let limit = silenceThresholdDBFS
        let w = max(1, Self.silenceWindowFrames)
        var i = samples.startIndex
        while i < samples.endIndex {
            let end = min(samples.endIndex, i + w)
            var sum: Float = 0
            for j in i..<end { let v = samples[j].isFinite ? samples[j] : 1; sum += v * v }
            let rms = (sum / Float(end - i)).squareRoot()
            if Self.dB(rms) >= limit { return false }
            i = end
        }
        return true
    }

    public var hasSpeechSinceLastCut: Bool { speechFrames >= Self.frames(Self.minSpeechSeconds) }

    public func shouldSendTail(chunksSent: Int) -> Bool {
        chunksSent == 0 || audibleFrames >= Self.frames(Self.minTailSpeechSeconds)
    }

    public mutating func observe(levels: [Float], endFrame newEnd: Int) -> Cut? {
        let from = endFrame
        let span = max(0, newEnd - from)
        endFrame = max(endFrame, newEnd)
        guard !levels.isEmpty, span > 0 else { return nil }
        var cut: Cut?
        for (i, rms) in levels.enumerated() {
            let ws = from + span * i / levels.count
            let we = from + span * (i + 1) / levels.count
            guard we > ws else { continue }
            let db = Self.dB(rms)
            histogram[Int(db.rounded()) + 120] += 1
            histogramTotal += 1
            let threshold = thresholdDBFS
            let speech = db >= threshold
            let audible = db >= threshold - Self.silenceMarginDB
            windows.append(Window(start: ws, end: we, db: db, speech: speech, audible: audible))
            if audible { audibleFrames += we - ws }
            if speech {
                speechFrames += we - ws
                lastSpeechEndFrame = we
                quietRunStart = nil
            } else if quietRunStart == nil {
                quietRunStart = ws
            }
            if cut == nil, let c = decide(at: we) {
                apply(c)
                cut = c
            }
        }
        return cut
    }

    private func decide(at now: Int) -> Cut? {
        guard hasSpeechSinceLastCut else { return nil }
        let minChunk = Self.frames(Self.minChunkSeconds)
        if let q = quietRunStart, now - q >= Self.frames(Self.minPauseSeconds) {
            let mid = q + (now - q) / 2
            if mid - lastCutFrame >= minChunk {
                return Cut(frame: mid, reason: .pause, frames: mid - lastCutFrame)
            }
        }
        guard now - lastCutFrame >= Self.frames(Self.maxChunkSeconds) else { return nil }
        let earliest = max(lastCutFrame + minChunk, now - Self.frames(Self.forcedSearchSeconds))
        let candidates = windows.filter { $0.start >= earliest }
        let k = min(Self.quietSpanWindows, candidates.count)
        guard k > 0 else { return nil }
        var best = 0
        var bestSum = Double.infinity
        for i in 0...(candidates.count - k) {
            let s = candidates[i..<(i + k)].reduce(0) { $0 + $1.db }
            if s < bestSum { bestSum = s; best = i }
        }
        let mid = (candidates[best].start + candidates[best + k - 1].end) / 2
        return Cut(frame: mid, reason: .forced, frames: mid - lastCutFrame)
    }

    private mutating func apply(_ c: Cut) {
        lastCutFrame = c.frame
        windows.removeAll { $0.end <= c.frame }
        speechFrames = windows.filter(\.speech).reduce(0) { $0 + ($1.end - max($1.start, c.frame)) }
        audibleFrames = windows.filter(\.audible).reduce(0) { $0 + ($1.end - max($1.start, c.frame)) }
        if let q = quietRunStart { quietRunStart = max(q, c.frame) }
    }

    static func frames(_ seconds: Double) -> Int { Int(seconds * Double(sampleRate)) }

    static func dB(_ rms: Float) -> Double {
        guard rms.isFinite, rms > 0 else { return -120 }
        return max(-120, min(0, 20 * log10(Double(rms))))
    }
}
