import Foundation

public enum StartChime {
    public enum Preset: String, CaseIterable, Sendable {
        case marimba
        case round
        case smooth
        case light
        case chime
        case bloop
        case typeless
        case glimmer
        case cascade

        public var title: String {
            switch self {
            case .marimba: return "柔和木琴"
            case .round: return "圓潤（暖一點）"
            case .smooth: return "圓滑（兩個音連成一聲）"
            case .light: return "輕盈（短、輕）"
            case .chime: return "鐘聲"
            case .bloop: return "單音「啵」"
            case .typeless: return "仿 Typeless"
            case .glimmer, .cascade: return plusTitle
            }
        }

        public var requiresPlus: Bool {
            switch self {
            case .marimba, .round, .smooth, .light, .chime, .bloop, .typeless: return false
            case .glimmer, .cascade: return true
            }
        }

        public static func pickerOptions(unlocked: Bool, offersPlus: Bool) -> [Preset] {
            allCases.filter { !$0.requiresPlus || unlocked || offersPlus }
        }
    }

    public static func effectivePreset(stored: String?, unlocked: Bool) -> Preset {
        guard let stored, let preset = Preset(rawValue: stored) else { return defaultPreset }
        if preset.requiresPlus && !unlocked { return defaultPreset }
        return preset
    }

    public enum Melody {
        public static let first = 392.00
        public static let up = 523.25
        public static let down = 293.66
    }

    public static let defaultPreset: Preset = .marimba

    public static let sampleRate: Double = 48_000
    public static let peakDBFS: Double = -18

    public static let enabledDefaultsKey = "startChimeEnabled"
    public static let enabledByDefault = true
    public static let presetDefaultsKey = "startChimePreset"

    public struct Note: Equatable, Sendable {
        public var start: Double
        public var length: Double
        public var frequency: Double
        public var endFrequency: Double
        public var gain: Double
        public var secondHarmonic: Double
        public var attack: Double
        public var decayPower: Double

        public init(start: Double, length: Double, frequency: Double, endFrequency: Double? = nil,
                    gain: Double = 1, secondHarmonic: Double, attack: Double, decayPower: Double) {
            self.start = start
            self.length = length
            self.frequency = frequency
            self.endFrequency = endFrequency ?? frequency
            self.gain = gain
            self.secondHarmonic = secondHarmonic
            self.attack = attack
            self.decayPower = decayPower
        }

        public var end: Double { start + length }
    }

    public static func notes(_ preset: Preset) -> [Note] {
        switch preset {
        case .marimba:
            return [Note(start: 0, length: 0.085, frequency: Melody.first, gain: 0.85,
                         secondHarmonic: 0.12, attack: 0.004, decayPower: 3),
                    Note(start: 0.060, length: 0.095, frequency: Melody.up, gain: 1,
                         secondHarmonic: 0.10, attack: 0.004, decayPower: 3)]
        case .chime:
            return [Note(start: 0, length: 0.110, frequency: Melody.first, gain: 0.9,
                         secondHarmonic: 0.18, attack: 0.008, decayPower: 2),
                    Note(start: 0.055, length: 0.125, frequency: Melody.up, gain: 1,
                         secondHarmonic: 0.15, attack: 0.008, decayPower: 2)]
        case .bloop:
            return [Note(start: 0, length: 0.130, frequency: Melody.first, endFrequency: Melody.up, gain: 1,
                         secondHarmonic: 0.20, attack: 0.010, decayPower: 2.5)]
        case .round:
            return [Note(start: 0, length: 0.110, frequency: Melody.first, gain: 0.9,
                         secondHarmonic: 0.22, attack: 0.012, decayPower: 2),
                    Note(start: 0.050, length: 0.130, frequency: Melody.up, gain: 1,
                         secondHarmonic: 0.20, attack: 0.012, decayPower: 2)]
        case .smooth:
            return [Note(start: 0, length: 0.130, frequency: Melody.first, gain: 0.85,
                         secondHarmonic: 0.06, attack: 0.025, decayPower: 1.6),
                    Note(start: 0.050, length: 0.130, frequency: Melody.up, gain: 1,
                         secondHarmonic: 0.05, attack: 0.025, decayPower: 1.6)]
        case .typeless:
            return [Note(start: 0, length: 0.280, frequency: Melody.first, gain: 0.95,
                         secondHarmonic: 0.02, attack: 0.004, decayPower: 3),
                    Note(start: 0.150, length: 0.150, frequency: Melody.up, gain: 1,
                         secondHarmonic: 0.02, attack: 0.004, decayPower: 2.5)]
        case .light:
            return [Note(start: 0, length: 0.060, frequency: Melody.first, gain: 0.8,
                         secondHarmonic: 0.04, attack: 0.003, decayPower: 4),
                    Note(start: 0.045, length: 0.075, frequency: Melody.up, gain: 1,
                         secondHarmonic: 0.03, attack: 0.003, decayPower: 4)]
        case .glimmer, .cascade:
            return plusNotes(preset)
        }
    }

    public static func stopNotes(_ preset: Preset) -> [Note] {
        notes(preset).map { n in
            var n = n
            if n.frequency == Melody.up { n.frequency = Melody.down }
            if n.endFrequency == Melody.up { n.endFrequency = Melody.down }
            return n
        }
    }

    public static var stopNotes: [Note] { stopNotes(defaultPreset) }

    public static func shouldPlayStop(enabled: Bool, reason: RecordingStopReason) -> Bool {
        enabled && reason.sendsAudio
    }

    public static func duration(_ preset: Preset) -> Double { duration(notes(preset)) }

    static func duration(_ notes: [Note]) -> Double { notes.map(\.end).max() ?? 0 }

    public static func sampleCount(_ preset: Preset, sampleRate: Double = sampleRate) -> Int {
        sampleCount(duration(preset), sampleRate: sampleRate)
    }

    static func sampleCount(_ seconds: Double, sampleRate: Double) -> Int {
        seconds > 0 ? Int((seconds * sampleRate).rounded()) + 1 : 0
    }

    public static func render(_ preset: Preset, sampleRate: Double = sampleRate) -> [Float] {
        render(notes: notes(preset), sampleRate: sampleRate)
    }

    public static func render(notes: [Note], sampleRate: Double = sampleRate,
                              peakDBFS: Double = peakDBFS) -> [Float] {
        let count = sampleCount(duration(notes), sampleRate: sampleRate)
        guard count > 0 else { return [] }
        var mix = [Double](repeating: 0, count: count)
        for note in notes {
            var phase = 0.0
            let first = max(0, Int((note.start * sampleRate).rounded(.up)))
            let last = min(count - 1, Int((note.end * sampleRate).rounded(.down)))
            guard first <= last else { continue }
            for i in first...last {
                let t = Double(i) / sampleRate - note.start
                let env = envelope(t, length: note.length, attack: note.attack, decayPower: note.decayPower)
                mix[i] += note.gain * env * (sin(phase) + note.secondHarmonic * sin(2 * phase))
                phase += 2 * Double.pi * frequency(of: note, at: t) / sampleRate
            }
        }
        let peak = mix.reduce(0) { max($0, abs($1)) }
        guard peak > 0 else { return mix.map { Float($0) } }
        let scale = pow(10, peakDBFS / 20) / peak
        return mix.map { Float($0 * scale) }
    }

    public static func envelope(_ t: Double, length: Double, attack: Double, decayPower: Double) -> Double {
        guard t >= 0, t <= length, length > 0 else { return 0 }
        let a = min(max(attack, 0), length)
        if t < a { return 0.5 * (1 - cos(Double.pi * t / a)) }
        let release = length - a
        guard release > 0 else { return 1 }
        let r = min(1, (t - a) / release)
        return pow(0.5 * (1 + cos(Double.pi * r)), decayPower)
    }

    static func frequency(of note: Note, at t: Double) -> Double {
        guard note.endFrequency != note.frequency else { return note.frequency }
        let x = min(1, max(0, t / (note.length / 2)))
        let s = x * x * (3 - 2 * x)
        return note.frequency + (note.endFrequency - note.frequency) * s
    }

    public static func wavData(_ samples: [Float], sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let dataBytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        for s in samples {
            let v = s.isFinite ? max(-1, min(1, s)) : 0
            u16(UInt16(bitPattern: Int16((v * 32767).rounded())))
        }
        return d
    }

    public static func shouldPlay(enabled: Bool, action: HotkeyPolicy.Action, captureStarted: Bool) -> Bool {
        guard enabled, captureStarted, case .startRecording = action else { return false }
        return true
    }

    public enum CaptureOverlap: Equatable, Sendable {
        case simultaneous
        case discardChimeWindow(tailMillis: Int)
    }

    public static let captureOverlap: CaptureOverlap = .discardChimeWindow(tailMillis: 40)

    public static func discardUntil(playedAt: UInt64, preset: Preset,
                                    overlap: CaptureOverlap = captureOverlap) -> UInt64? {
        guard case .discardChimeWindow(let tail) = overlap else { return nil }
        let nanos = (duration(preset) * 1_000_000_000).rounded() + Double(max(0, tail)) * 1_000_000
        return playedAt + UInt64(nanos)
    }

    public static func leadingFramesToDiscard(blockStart: UInt64, sampleRate: Double, frames: Int,
                                              until: UInt64) -> Int {
        guard frames > 0, sampleRate > 0, until > blockStart else { return 0 }
        let seconds = Double(until - blockStart) / 1_000_000_000
        let n = (seconds * sampleRate).rounded(.up)
        return n >= Double(frames) ? frames : Int(n)
    }
}
