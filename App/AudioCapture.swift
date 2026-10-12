import AVFoundation
import AudioToolbox
import NaturalInputCore

@MainActor
final class AudioCapture {

    enum StartError: Error {
        case noInputDevice
        case engine(Error)
        case timedOut

        var logEvent: LogEvent {
            switch self {
            case .noInputDevice: return .startFailedNoInputDevice
            case .engine(let e): return .startFailedEngine(code: (e as NSError).code)
            case .timedOut: return .startFailedEngine(code: AudioCapture.timeoutCode)
            }
        }

        var message: String {
            switch self {
            case .noInputDevice: return "找不到麥克風輸入，錄音沒有開始"
            case .engine(let e): return "麥克風無法啟動（\(e.localizedDescription)），錄音沒有開始"
            case .timedOut: return "麥克風沒有回應（可能藍牙耳機正在切換），錄音沒有開始，請再按一次"
            }
        }
    }

    private var input: HALInput?
    private var pendingRebuild: EngineRebuildReason?
    struct DeviceCheck { var bound: Bool; var inputBluetooth: Bool; var defaultOutputBluetooth: Bool }
    private(set) static var lastDeviceCheck: DeviceCheck?
    private(set) var deviceChoiceFailed = false
    private(set) var pipeline: AudioPipeline?
    private var generation = 0
    private var reportedFull = false
    private let idleGuard = RecordingActivityGuard()

    var onCapacityReached: (() -> Void)?
    var onInterrupted: ((String) -> Void)?
    var onLevels: (([Float]) -> Void)?
    var onIngest: (([Float], AudioPipeline) -> Void)?
    var onFirstAudio: ((UInt64) -> Void)?
    private var reportedFirstAudio = false
    private var discardUntil: UInt64?
    private var discardedFrames = 0

    nonisolated static let levelHz: Double = 30

    var isRunning: Bool { pipeline != nil }

    func rebuildEngineOnNextStart(_ reason: EngineRebuildReason) {
        pendingRebuild = reason
    }

    func start() throws(StartError) {
        stopEngine()
        if let reason = pendingRebuild {
            pendingRebuild = nil
            Log.record(.engineRebuilt(reason))
        }
        deviceChoiceFailed = false
        let chosen = AudioInputDevices.resolvedDeviceID()
        guard let system = AudioInputDevices.systemDefaultID() ?? chosen else { throw .noInputDevice }
        generation += 1
        let gen = generation
        let handler = Self.makeBlockHandler(generation: gen, owner: self)

        var opened: HALInput?
        var failure: OSStatus = noErr
        if let chosen {
            switch openInput(device: chosen, handler: handler) {
            case .success(let h): opened = h
            case .failure(.timedOut): Log.record(.inputDeviceApplied(ok: false)); throw .timedOut
            case .failure(.status(let s)): failure = s
            }
            if opened == nil { deviceChoiceFailed = true }
        }
        if opened == nil {
            switch openInput(device: system, handler: handler) {
            case .success(let h): opened = h
            case .failure(.timedOut): Log.record(.inputDeviceApplied(ok: false)); throw .timedOut
            case .failure(.status(let s)): failure = s
            }
        }
        guard let input = opened else {
            Log.record(.inputDeviceApplied(ok: false))
            throw .engine(NSError(domain: NSOSStatusErrorDomain, code: Int(failure)))
        }
        Log.record(.inputDeviceApplied(ok: !deviceChoiceFailed))
        Self.lastDeviceCheck = DeviceCheck(bound: !deviceChoiceFailed, inputBluetooth: AudioInputDevices.isBluetooth(input.device),
                                           defaultOutputBluetooth: AudioInputDevices.systemDefaultOutputID()
                                               .map(AudioInputDevices.isBluetooth) ?? false)
        Log.record(.inputFormat(sampleRate: input.sampleRate, channels: input.channels, interleaved: false))

        pipeline = AudioPipeline(inputSampleRate: input.sampleRate, maxSeconds: AudioBuffer.maxSeconds)
        reportedFull = false
        reportedFirstAudio = false
        discardUntil = nil
        discardedFrames = 0
        input.onDeviceChange = { [weak self] change in
            MainActor.assumeIsolated { self?.deviceChanged(change) }
        }
        self.input = input
        idleGuard.begin()
    }

    nonisolated static let openTimeout: TimeInterval = 2.0
    nonisolated static let timeoutCode = -9_001
    nonisolated static let openInFlight = AtomicFlag()
    private let audioQueue = DispatchQueue(label: "talkiie.audio-io", qos: .userInitiated)

    enum OpenFailure: Error { case status(OSStatus), timedOut }

    private func openInput(device: AudioDeviceID, handler: @escaping HALInput.BlockHandler) -> Result<HALInput, OpenFailure> {
        guard !Self.openInFlight.isSet else { return .failure(.timedOut) }
        Self.openInFlight.set(true)
        let box = OpenBox()
        let done = DispatchSemaphore(value: 0)
        audioQueue.async {
            let r: Result<HALInput, OpenFailure>
            do {
                let h = try HALInput(device: device, onBlock: handler)
                do { try h.start(); r = .success(h) } catch { h.dispose(); r = .failure(.status((error as? HALInput.Failure)?.status ?? -1)) }
            } catch {
                r = .failure(.status((error as? HALInput.Failure)?.status ?? -1))
            }
            box.deliver(r)
            AudioCapture.openInFlight.set(false)
            done.signal()
        }
        if done.wait(timeout: .now() + Self.openTimeout) == .timedOut, box.abandon() {
            return .failure(.timedOut)
        }
        return box.take() ?? .failure(.timedOut)
    }

    private func disposeInBackground(_ h: HALInput?) {
        guard let h else { return }
        audioQueue.async { h.dispose() }
    }

    private func deviceChanged(_ change: HALInput.DeviceChange) {
        guard let pipeline, let old = input else { return }
        switch change {
        case .gone:
            Log.record(.inputLost)
            onInterrupted?("麥克風在錄音中斷線，錄音已停止並清除")
        case .formatChanged:
            generation += 1
            let gen = generation
            disposeInBackground(old)
            input = nil
            switch openInput(device: old.device, handler: Self.makeBlockHandler(generation: gen, owner: self)) {
            case .success(let fresh):
                Log.record(.configurationChange(sampleRate: fresh.sampleRate, channels: fresh.channels,
                                                previousRate: pipeline.inputSampleRate))
                if fresh.sampleRate != pipeline.inputSampleRate { pipeline.changeInputRate(fresh.sampleRate) }
                fresh.onDeviceChange = { [weak self] c in MainActor.assumeIsolated { self?.deviceChanged(c) } }
                input = fresh
            case .failure(let f):
                if case .status(let s) = f { Log.record(.reconnectFailed(code: Int(s))) }
                else { Log.record(.reconnectFailed(code: Self.timeoutCode)) }
                onInterrupted?("麥克風格式改變後無法重新啟動，錄音已停止並清除")
            }
        }
    }

    func stopEngine() {
        generation += 1
        disposeInBackground(input)
        input = nil
        idleGuard.end()
    }

    func discardAudio(until: UInt64) {
        guard pipeline != nil else { return }
        discardUntil = until
        discardedFrames = 0
    }

    func wipe() {
        pipeline?.wipe()
        pipeline = nil
    }

    func takeSnapshotAndWipe() -> [Float] {
        defer { pipeline = nil }
        return pipeline?.takeSnapshotAndWipe() ?? []
    }

    nonisolated private static func makeBlockHandler(generation gen: Int, owner: AudioCapture) -> HALInput.BlockHandler {
        let ref = WeakCaptureRef(owner)
        return { mono, sampleRate, capturedAt in
            let levels = rmsWindows(mono, windowSize: Int(sampleRate / levelHz))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { ref.value?.receive(mono, levels: levels, generation: gen, capturedAt: capturedAt) }
            }
        }
    }

    nonisolated static func rmsWindows(_ samples: [Float], windowSize: Int) -> [Float] {
        let w = max(1, windowSize)
        var out: [Float] = []
        var i = 0
        while i < samples.count {
            let end = min(samples.count, i + w)
            if end - i < w, !out.isEmpty, (end - i) * 2 < w { break }
            var sum: Float = 0
            for j in i..<end { let v = samples[j].isFinite ? samples[j] : 0; sum += v * v }
            out.append((sum / Float(end - i)).squareRoot())
            i = end
        }
        return out
    }

    private func receive(_ mono: [Float], levels: [Float], generation gen: Int, capturedAt: UInt64) {
        guard generation == gen, let pipeline else { return }
        if !reportedFirstAudio {
            reportedFirstAudio = true
            onFirstAudio?(capturedAt)
        }
        var mono = mono, levels = levels
        if let until = discardUntil {
            let drop = StartChime.leadingFramesToDiscard(blockStart: capturedAt, sampleRate: pipeline.inputSampleRate,
                                                         frames: mono.count, until: until)
            discardedFrames += drop
            if drop < mono.count {
                discardUntil = nil
                Log.record(.chimeWindowDiscarded(millis: Int(Double(discardedFrames) * 1000 / pipeline.inputSampleRate)))
            }
            if drop > 0 {
                let kept = Array(mono[drop...])
                AudioPipeline.zeroize(&mono)
                mono = kept
                levels = mono.isEmpty ? []
                    : Self.rmsWindows(mono, windowSize: Int(pipeline.inputSampleRate / Self.levelHz))
            }
            if mono.isEmpty { return }
        }
        if !levels.isEmpty { onLevels?(levels) }
        let ingested = pipeline.ingest(mono: mono)
        onIngest?(levels, pipeline)
        if case .reachedCapacity = ingested, !reportedFull {
            reportedFull = true
            Log.record(.bufferFull)
            onCapacityReached?()
        }
    }
}

private final class WeakCaptureRef: @unchecked Sendable {
    weak var value: AudioCapture?
    init(_ value: AudioCapture) { self.value = value }
}

enum EngineRebuildReason: String {
    case permissionGranted
    case noAudioLastRound
    case inputDeviceChanged
}

private final class OpenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<HALInput, AudioCapture.OpenFailure>?
    private var abandoned = false

    func deliver(_ r: Result<HALInput, AudioCapture.OpenFailure>) {
        lock.lock(); defer { lock.unlock() }
        if abandoned { if case .success(let h) = r { h.dispose() }; return }
        result = r
    }

    func abandon() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if result != nil { return false }
        abandoned = true
        return true
    }

    func take() -> Result<HALInput, AudioCapture.OpenFailure>? {
        lock.lock(); defer { lock.unlock() }
        return result
    }
}

final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
}
