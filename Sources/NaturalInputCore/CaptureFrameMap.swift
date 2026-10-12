public struct CaptureFrameMap: Sendable {
    private struct Block: Sendable {
        let start: Double
        let startFrame: Int
        let endFrame: Int
    }

    public static let keepSeconds: Double = 10

    private var blocks: [Block] = []

    public init() {}

    public mutating func record(capturedAt: UInt64, startFrame: Int, endFrame: Int) {
        guard capturedAt != 0, endFrame > startFrame else { return }
        blocks.append(Block(start: Double(capturedAt) / 1_000_000_000, startFrame: startFrame, endFrame: endFrame))
        let horizon = endFrame - Int(Self.keepSeconds * Double(AudioBuffer.sampleRate))
        if let first = blocks.first, first.endFrame < horizon { blocks.removeAll { $0.endFrame < horizon } }
    }

    public var lastSampleEndSeconds: Double? {
        guard let b = blocks.last else { return nil }
        return b.start + Double(b.endFrame - b.startFrame) / Double(AudioBuffer.sampleRate)
    }

    public func frame(before seconds: Double) -> Int? {
        guard !blocks.isEmpty else { return nil }
        let rate = Double(AudioBuffer.sampleRate)
        for b in blocks {
            if seconds <= b.start { return b.startFrame }
            let kept = Int(((seconds - b.start) * rate - 1e-6).rounded(.up))
            if kept < b.endFrame - b.startFrame { return b.startFrame + kept }
        }
        return blocks[blocks.count - 1].endFrame
    }
}
