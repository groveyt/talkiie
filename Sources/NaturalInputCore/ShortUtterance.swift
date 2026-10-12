import Foundation

public enum ShortUtterance {
    public static let maxSeconds = 1.5
    public static let padSeconds = 0.4
    public static let promptMinimumTerms = 1
    public static let fuzzyThreshold = 0.75

    public static func isShort(seconds: Double) -> Bool { seconds > 0 && seconds <= maxSeconds }

    public static func padding(forSeconds seconds: Double, sampleRate: Int = AudioBuffer.sampleRate) -> SilencePadding {
        guard isShort(seconds: seconds) else { return .none }
        let frames = Int((padSeconds * Double(sampleRate)).rounded())
        return SilencePadding(leadingFrames: frames, trailingFrames: frames, sampleRate: sampleRate)
    }
}

public struct SilencePadding: Equatable, Sendable {
    public static let none = SilencePadding(leadingFrames: 0, trailingFrames: 0, sampleRate: AudioBuffer.sampleRate)

    public let leadingFrames: Int
    public let trailingFrames: Int
    public let sampleRate: Int

    public init(leadingFrames: Int, trailingFrames: Int, sampleRate: Int) {
        self.leadingFrames = max(0, leadingFrames)
        self.trailingFrames = max(0, trailingFrames)
        self.sampleRate = sampleRate
    }

    public var isNone: Bool { leadingFrames == 0 && trailingFrames == 0 }

    public var totalMillis: Int {
        Int((Double(leadingFrames + trailingFrames) * 1000 / Double(sampleRate)).rounded())
    }

    public func padded(_ samples: [Float]) -> [Float] {
        guard !isNone else { return samples }
        var out = [Float](repeating: 0, count: leadingFrames + samples.count + trailingFrames)
        out.replaceSubrange(leadingFrames..<(leadingFrames + samples.count), with: samples)
        return out
    }

    public func unshifted(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard leadingFrames > 0 else { return segments }
        let lead = Double(leadingFrames) / Double(sampleRate)
        return segments.map { TranscriptSegment(text: $0.text, start: max(0, $0.start - lead), end: max(0, $0.end - lead)) }
    }
}
