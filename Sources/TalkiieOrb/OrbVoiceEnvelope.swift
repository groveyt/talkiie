import Foundation

public struct OrbVoiceEnvelope: Equatable, Sendable {
    public static let noiseFloor = 0.04
    public static let minPeak = 0.22
    public static let peakRelease = 0.35
    public static let attack = 0.03, release = 0.18

    public static func normalized(rms: Float) -> Double {
        guard rms.isFinite, rms > 0 else { return 0 }
        let db = 20 * log10(Double(rms))
        return min(1, max(0, (db + 55) / 45))
    }

    public private(set) var peak = minPeak
    public private(set) var value = 0.0

    public init() {}

    public mutating func next(_ level: Double, dt: Double) -> Double {
        let v = level.isFinite ? min(1, max(0, level)) : 0
        let dt = dt.isFinite ? max(0, dt) : 0
        peak = max(v, max(Self.minPeak, peak - Self.peakRelease * dt))
        let target = min(1, max(0, (v - Self.noiseFloor) / (peak - Self.noiseFloor)))
        let tau = target > value ? Self.attack : Self.release
        value += (target - value) * min(1, dt / tau)
        return value
    }
}
