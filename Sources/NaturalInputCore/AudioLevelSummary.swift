import Foundation

public struct AudioLevelSummary: Equatable, Sendable {
    public let seconds: Double
    public let peakDBFS: Double
    public let rmsDBFS: Double

    public static let silenceThresholdDBFS: Double = -50

    public init(samples: [Float], sampleRate: Int = AudioBuffer.sampleRate) {
        seconds = Double(samples.count) / Double(sampleRate)
        var peak: Float = 0
        var sumSquares: Double = 0
        for s in samples {
            let a = abs(s)
            if a > peak { peak = a }
            sumSquares += Double(s) * Double(s)
        }
        peakDBFS = Self.dB(Double(peak))
        rmsDBFS = samples.isEmpty ? -.infinity : Self.dB((sumSquares / Double(samples.count)).squareRoot())
    }

    private init(seconds: Double, peakDBFS: Double, rmsDBFS: Double) {
        self.seconds = seconds
        self.peakDBFS = peakDBFS
        self.rmsDBFS = rmsDBFS
    }

    public func merged(with other: AudioLevelSummary) -> AudioLevelSummary {
        let total = seconds + other.seconds
        guard total > 0 else { return self }
        func energy(_ s: AudioLevelSummary) -> Double {
            s.rmsDBFS.isFinite ? pow(10, s.rmsDBFS / 10) * s.seconds : 0
        }
        let meanSquare = (energy(self) + energy(other)) / total
        return AudioLevelSummary(seconds: total,
                                 peakDBFS: max(peakDBFS, other.peakDBFS),
                                 rmsDBFS: meanSquare > 0 ? 10 * log10(meanSquare) : -.infinity)
    }

    public var isSilent: Bool { peakDBFS < Self.silenceThresholdDBFS }

    public var text: String {
        let secs = String(format: "%.1f", seconds)
        if seconds == 0 { return "沒有收到任何音訊，請檢查麥克風" }
        let peak = peakDBFS.isFinite ? String(format: "%.0f", peakDBFS) : "-∞"
        return isSilent
            ? "收到 \(secs) 秒，但幾乎是靜音（峰值 \(peak) dBFS），請檢查麥克風"
            : "收到 \(secs) 秒，音量峰值 \(peak) dBFS"
    }

    private static func dB(_ x: Double) -> Double { x > 0 ? 20 * log10(x) : -.infinity }
}
