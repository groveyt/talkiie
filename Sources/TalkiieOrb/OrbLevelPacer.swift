import Foundation

public struct OrbLevelPacer: Equatable, Sendable {
    public static let hz = 30.0
    public static let maxPending = 6
    public static let decay = 0.8

    private var pending: [Double] = []
    private var last = 0.0
    private var envelope = OrbVoiceEnvelope()

    public init() {}

    public mutating func push(_ levels: [Double]) {
        pending.append(contentsOf: levels.map { $0.isFinite ? min(1, max(0, $0)) : 0 })
        if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
    }

    public mutating func tick() -> Double {
        let next = pending.isEmpty ? last * Self.decay : pending.removeFirst()
        last = next < 0.01 ? 0 : next
        return envelope.next(next, dt: 1 / Self.hz)
    }

    public mutating func reset() { self = OrbLevelPacer() }
}
