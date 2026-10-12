import AVFoundation
import NaturalInputCore

@MainActor
final class StartChimePlayer {
    static let shared = StartChimePlayer()

    private var players: [StartChime.Preset: AVAudioPlayer] = [:]

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: StartChime.enabledDefaultsKey) as? Bool ?? StartChime.enabledByDefault
    }

    @MainActor static var preset: StartChime.Preset {
        StartChime.effectivePreset(stored: UserDefaults.standard.string(forKey: StartChime.presetDefaultsKey),
                                   unlocked: Edition.plusUnlocked)
    }

    #if DEBUG
    private(set) var debugPlays = 0

    func debugAllPresetsLoad() -> Bool {
        StartChime.Preset.allCases.allSatisfy { preset in
            guard let p = player(for: preset) else { return false }
            return abs(p.duration - StartChime.duration(preset)) < 0.002 && p.numberOfChannels == 1
        }
    }
    #endif

    func prepare() {
        _ = player(for: Self.preset)
    }

    @discardableResult
    func play(_ preset: StartChime.Preset = StartChimePlayer.preset, preview: Bool = false) -> UInt64? {
        guard let p = player(for: preset) else {
            Log.record(.chimeUnavailable(preset))
            return nil
        }
        if p.isPlaying { p.stop() }
        p.currentTime = 0
        let at = LatencyTimeline.now()
        guard p.play() else {
            Log.record(.chimeUnavailable(preset))
            return nil
        }
        #if DEBUG
        debugPlays += 1
        #endif
        Log.record(.chimePlayed(preset, preview: preview))
        return at
    }

    private var stopPlayers: [StartChime.Preset: AVAudioPlayer] = [:]

    func playStop(_ preset: StartChime.Preset = StartChimePlayer.preset) {
        if stopPlayers[preset] == nil {
            let rate = Int(StartChime.sampleRate)
            let samples = StartChime.render(notes: StartChime.stopNotes(preset), sampleRate: StartChime.sampleRate)
            let p = try? AVAudioPlayer(data: StartChime.wavData(samples, sampleRate: rate),
                                       fileTypeHint: AVFileType.wav.rawValue)
            p?.prepareToPlay()
            stopPlayers[preset] = p
        }
        guard let p = stopPlayers[preset] else { Log.record(.chimeUnavailable(preset)); return }
        if p.isPlaying { p.stop() }
        p.currentTime = 0
        _ = p.play()
    }

    private var previewStop: DispatchWorkItem?

    func preview(_ preset: StartChime.Preset) {
        previewStop?.cancel()
        play(preset, preview: true)
        let work = DispatchWorkItem { [weak self] in self?.playStop(preset) }
        previewStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    private func player(for preset: StartChime.Preset) -> AVAudioPlayer? {
        if let p = players[preset] { return p }
        let rate = Int(StartChime.sampleRate)
        let samples = StartChime.render(preset, sampleRate: StartChime.sampleRate)
        guard let p = try? AVAudioPlayer(data: StartChime.wavData(samples, sampleRate: rate),
                                         fileTypeHint: AVFileType.wav.rawValue) else { return nil }
        p.prepareToPlay()
        players[preset] = p
        return p
    }
}
