import Foundation

public final class AudioBuffer {
    public static let sampleRate = 16_000

    public static let maxSeconds: Double = 300

    public let capacityFrames: Int
    private let storage: UnsafeMutableBufferPointer<Float>
    public private(set) var frameCount: Int = 0

    public private(set) var zeroizeCount: Int = 0

    public init(maxSeconds: Double) {
        precondition(maxSeconds > 0)
        capacityFrames = Int(maxSeconds * Double(Self.sampleRate))
        storage = .allocate(capacity: capacityFrames)
        storage.initialize(repeating: 0)
    }

    deinit {
        zeroizeStorage()
        storage.deallocate()
    }

    public var isEmpty: Bool { frameCount == 0 }
    public var durationSeconds: Double { Double(frameCount) / Double(Self.sampleRate) }
    public var isFull: Bool { frameCount >= capacityFrames }

    public enum AppendResult: Equatable, Sendable {
        case appended(frames: Int)
        case rejectedWouldExceedCapacity(overflowFrames: Int)
    }

    @discardableResult
    public func append(_ chunk: [Float]) -> AppendResult {
        let after = frameCount + chunk.count
        if after > capacityFrames {
            return .rejectedWouldExceedCapacity(overflowFrames: after - capacityFrames)
        }
        for (i, v) in chunk.enumerated() { storage[frameCount + i] = v }
        frameCount = after
        return .appended(frames: chunk.count)
    }

    public func wipe() {
        zeroizeStorage()
        frameCount = 0
    }

    private func zeroizeStorage() {
        let bytes = capacityFrames * MemoryLayout<Float>.stride
        _ = memset_s(storage.baseAddress, bytes, 0, bytes)
        zeroizeCount += 1
    }

    public func snapshot() -> [Float] { Array(storage.prefix(frameCount)) }

    public func removePrefix(_ n: Int) -> [Float] {
        let k = max(0, min(n, frameCount))
        guard k > 0 else { return [] }
        let out = Array(storage.prefix(k))
        let rest = frameCount - k
        let base = storage.baseAddress!
        if rest > 0 { memmove(base, base + k, rest * MemoryLayout<Float>.stride) }
        let vacated = k * MemoryLayout<Float>.stride
        _ = memset_s(base + rest, vacated, 0, vacated)
        frameCount = rest
        return out
    }

    func rawStorage(upTo n: Int) -> [Float] {
        Array(storage.prefix(min(n, capacityFrames)))
    }
}
