public final class AudioPipeline {

    public private(set) var inputSampleRate: Double
    public let buffer: AudioBuffer
    private var resampler: LinearResampler

    public private(set) var droppedFrames: Int = 0

    public private(set) var baseFrame: Int = 0
    public var endFrame: Int { baseFrame + buffer.frameCount }

    public var ingestedTap: (([Float]) -> Void)?

    public init(inputSampleRate: Double, maxSeconds: Double) {
        precondition(inputSampleRate > 0, "輸入取樣率必須 > 0（沒有輸入裝置時是 0）")
        self.inputSampleRate = inputSampleRate
        self.buffer = AudioBuffer(maxSeconds: maxSeconds)
        self.resampler = LinearResampler(inputRate: inputSampleRate, outputRate: Double(AudioBuffer.sampleRate))
    }

    public enum IngestResult: Equatable, Sendable {
        case appended(frames: Int)
        case reachedCapacity(frames: Int, dropped: Int)
    }

    @discardableResult
    public func ingest(channels: [[Float]]) -> IngestResult {
        ingest(mono: Self.downmix(channels))
    }

    @discardableResult
    public func ingest(mono: [Float]) -> IngestResult {
        let out = resampler.process(mono)
        let room = buffer.capacityFrames - buffer.frameCount
        if out.count < room {
            buffer.append(out)
            ingestedTap?(out)
            return .appended(frames: out.count)
        }
        let fit = max(0, room)
        if fit > 0 {
            let kept = Array(out.prefix(fit))
            buffer.append(kept)
            ingestedTap?(kept)
        }
        let dropped = out.count - fit
        droppedFrames += dropped
        return .reachedCapacity(frames: fit, dropped: dropped)
    }

    public var isFull: Bool { buffer.isFull }

    public func changeInputRate(_ rate: Double) {
        precondition(rate > 0, "輸入取樣率必須 > 0")
        inputSampleRate = rate
        resampler = LinearResampler(inputRate: rate, outputRate: Double(AudioBuffer.sampleRate))
    }

    public func wipe() {
        buffer.wipe()
        resampler.reset()
        droppedFrames = 0
        baseFrame = 0
    }

    public func takePrefix(upTo frame: Int) -> (samples: [Float], startFrame: Int) {
        let start = baseFrame
        let n = max(0, min(frame, endFrame) - baseFrame)
        let out = buffer.removePrefix(n)
        baseFrame += out.count
        return (out, start)
    }

    public func copyPending() -> (samples: [Float], startFrame: Int) {
        (buffer.snapshot(), baseFrame)
    }

    public func takeTailAndWipe() -> (samples: [Float], startFrame: Int) {
        let start = baseFrame
        return (takeSnapshotAndWipe(), start)
    }

    public func takeSnapshotAndWipe() -> [Float] {
        let s = buffer.snapshot()
        wipe()
        return s
    }

    public static func downmix(_ channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        if channels.count == 1 { return first }
        let n = channels.map(\.count).min() ?? 0
        let scale = 1 / Float(channels.count)
        var out = [Float](repeating: 0, count: n)
        for ch in channels {
            for i in 0..<n { out[i] += ch[i] }
        }
        for i in 0..<n { out[i] *= scale }
        return out
    }

    public static func zeroize(_ samples: inout [Float]) {
        samples.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
    }
}

public struct LinearResampler: Sendable {
    public let inputRate: Double
    public let outputRate: Double
    private let step: Double
    private var consumed: Int = 0
    private var produced: Int = 0
    private var previous: Float = 0

    public init(inputRate: Double, outputRate: Double) {
        precondition(inputRate > 0 && outputRate > 0)
        self.inputRate = inputRate
        self.outputRate = outputRate
        self.step = inputRate / outputRate
    }

    public mutating func reset() {
        consumed = 0; produced = 0; previous = 0
    }

    public mutating func process(_ x: [Float]) -> [Float] {
        let n = x.count
        guard n > 0 else { return [] }
        var out: [Float] = []
        out.reserveCapacity(Int(Double(n) / step) + 2)
        while true {
            let pos = Double(produced) * step - Double(consumed)
            let i0 = Int(pos.rounded(.down))
            let i1 = i0 + 1
            if i1 >= n {
                if i0 == n - 1 && pos == Double(i0) {
                    out.append(x[i0]); produced += 1
                }
                break
            }
            let a = i0 < 0 ? previous : x[i0]
            let b = x[i1]
            let frac = Float(pos - Double(i0))
            out.append(a + (b - a) * frac)
            produced += 1
        }
        consumed += n
        previous = x[n - 1]
        return out
    }
}
