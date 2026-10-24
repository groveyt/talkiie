import AppKit
import NaturalInputCore
import NaturalInputEgress

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    static var hotkeyLabel: String { shared.hotkey.label }
    static var hotkeyStartPhrase: String { FnHotkeyMonitor.mode.startPhrase(hotkey: shared.hotkey.label) }

    enum Phase: Equatable {
        case idle
        case recording(since: Date)
        case sending(since: Date)
    }

    @Published private(set) var phase: Phase = .idle {
        didSet {
            syncMenuBar()
            if phase != .idle { ThemeTrialPreview.shared.stop() }
        }
    }
    private(set) var deliveringNewTranscript = false { didSet { syncMenuBar() } }

    var menuBarState: MenuBarState {
        switch phase {
        case .recording: return .recording
        case .sending: return .processing
        case .idle: return deliveringNewTranscript ? .processing : .idle
        }
    }

    private func syncMenuBar() { MenuBarIcon.shared.update(menuBarState) }
    private var sendWatchdog: Task<Void, Never>?

    private var hotkeyMonitor: HotkeyMonitor?
    @Published private(set) var hotkeyRegistered = false
    @Published private(set) var hotkey = HotkeyCombo.load()
    @Published private(set) var lastRemoteFailure: Date?
    @Published private(set) var editCaptureKeyRegistered = false
    private var policy = HotkeyPolicy()
    private let capture = AudioCapture()
    private var fnMonitor: FnHotkeyMonitor?
    private var consecutiveEmptyRounds = 0
    private var secureInputPoll: Timer?
    static let pollInterval: TimeInterval = 0.25
    private let transcriber = AppModel.makeTranscriber()
    private lazy var whisperWarmer = AppModel.makeWarmer(for: transcriber)
    private let punctuator = AppModel.makePunctuator()
    private let rewriter = AppModel.makeRewriter()
    private var roundWrittenStyle: WrittenStyleMode?

    private var streaming: StreamingTranscription?
    private var timeline: RoundTimeline?
    private var sendingTimeline: RoundTimeline?
    #if DEBUG && RESEARCH_CAPTURE
    private var researchAudio: [Float] = []
    #endif

    nonisolated static var egressLogDirectory: URL {
        #if DEBUG
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--egress-log-dir"), i + 1 < args.count {
            return URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        #endif
        return Edition.dataDirectory
    }

    private var transmitting = false

    private var sendingNotice: String?

    @Published private(set) var history = DictationHistory()
    private(set) var inserting = false
    static let reinsertDelaySeconds: Double = 0.35

    var recentDictations: [DictationHistory.Entry] { Array(history.recentEntries(history.limit).reversed()) }

    static let sendTimeoutSeconds: Double = 30

    @Published private(set) var permissions = AppModel.readPermissions(accessibilityPrompted: false)
    private var accessibilityPrompted = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSMenu.didBeginTrackingNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPermissions() }
            })
        }

        capture.onCapacityReached = { [weak self] in
            self?.feed(.captureFull(secure: HotkeyMonitor.currentSecureInput()))
        }
        capture.onInterrupted = { [weak self] message in self?.abortRecording(message) }
        BopomofoLexicon.preload()
        capture.onLevels = { levels in RecordingHUD.capsule.push(rms: levels) }
        capture.onIngest = { [weak self] levels, pipeline in self?.streamIngested(levels, pipeline) }
        capture.onFirstAudio = { [weak self] at in self?.timeline?.mark(.firstAudio, at: at) }
        RecordingHUD.onButton = { [weak self] button in self?.capsuleButton(button) }
        RecordingHUD.onDeliveryAction = { [weak self] action, text in
            switch action {
            case .reinsert: self?.reinsert(text)
            case .copy:
                self?.copyToClipboard(text)
                RecordingHUD.showNotice("已複製到剪貼簿", seconds: 1.5)
            }
        }
        FallbackPanel.onAction = { action, text in
            switch action {
            case .copy:
                Log.record(.fallbackPanel(.copied))
                Clipboard.copy(text)
                FallbackPanel.close()
                RecordingHUD.showNotice("已複製到剪貼簿", seconds: 1.5)
            case .close: FallbackPanel.close()
            }
        }
        hotkeyMonitor = makeHotkeyMonitor(hotkey)
        hotkeyRegistered = hotkeyMonitor != nil
        fnMonitor = FnHotkeyMonitor { [weak self] in self?.hotkeyEvent(.hotkeyPressed) }
        fnMonitor?.onStopKeyTap = { [weak self] in self?.stopKeyTapped() }
        Log.record(.hotkeyRegistered(hotkeyRegistered))
        syncEditCaptureKey()
    }

    private func makeHotkeyMonitor(_ combo: HotkeyCombo) -> HotkeyMonitor? {
        let monitor = HotkeyMonitor(combo: combo) { [weak self] event in self?.hotkeyEvent(event) }
        monitor?.onRecordingKey = { [weak self] key in self?.recordingKeyPressed(key) }
        monitor?.onEditCaptureKey = { [weak self] in self?.editCaptureKeyPressed() }
        return monitor
    }

    func setHotkey(_ new: HotkeyCombo) -> String? {
        if let problem = new.problem { return problem.message }
        guard phase == .idle, policy.state == .idle else { return "口述進行中，結束之後再換" }
        if new == hotkey && hotkeyRegistered { return nil }
        let old = hotkey
        let ok: Bool
        if let monitor = hotkeyMonitor {
            ok = monitor.rebind(to: new) == noErr
        } else if let monitor = makeHotkeyMonitor(new) {
            hotkeyMonitor = monitor
            syncEditCaptureKey()
            ok = true
        } else {
            ok = false
        }
        Log.record(.hotkeyChanged(ok: ok, isDefault: new == .standard))
        guard ok else {
            hotkeyRegistered = hotkeyMonitor?.isMainRegistered ?? false
            return "\(new.label) 無法使用（可能被其他 app 佔用），仍然用 \(old.label)"
        }
        hotkey = new
        new.save()
        hotkeyRegistered = true
        return nil
    }

    func suspendHotkeys(_ suspend: Bool) {
        guard let monitor = hotkeyMonitor else { return }
        if suspend {
            monitor.suspendMain()
            monitor.unregisterEditCaptureKey()
        } else {
            monitor.resumeMain()
            syncEditCaptureKey()
        }
        hotkeyRegistered = monitor.isMainRegistered || suspend
    }

    func syncEditCaptureKey() {
        let enabled = EditCaptureSettings.isEnabled
        if enabled, let monitor = hotkeyMonitor {
            editCaptureKeyRegistered = monitor.registerEditCaptureKey(EditCaptureSettings.shortcut) == noErr
        } else {
            hotkeyMonitor?.unregisterEditCaptureKey()
            editCaptureKeyRegistered = false
        }
        Log.record(.editCaptureKey(enabled: enabled, shortcut: EditCaptureSettings.shortcut, registered: editCaptureKeyRegistered))
    }

    private func editCaptureKeyPressed() {
        EditCaptureController.shared.pressed(inserting: inserting)
    }

    private static func monotonicNow() -> Double { ProcessInfo.processInfo.systemUptime }

    private func hotkeyEvent(_ event: HotkeyMonitor.Event) {
        let pressedAt = LatencyTimeline.now()
        switch event {
        case .hotkeyPressed:
            Log.record(.hotkeyPressed(wasRecording: policy.state != .idle))
            guard ConsentStore.allowsCapture else {
                Log.record(.startRefusedNoConsent)
                ConsentWindow.shared.presentIfNeeded()
                return
            }
            if policy.state == .idle, let refusal = Edition.recordingStartRefusal() {
                Log.record(.startRefusedModelNotReady)
                RecordingHUD.showNotice(refusal)
                return
            }
            var awaitingTranscript = false
            if case .sending = phase { awaitingTranscript = true }
            if inserting, policy.state == .idle {
                Log.record(.startRefusedInsertionInProgress)
                RecordingHUD.showNotice(DeliveryContent.startBlockedNote)
                return
            }
            if case .refuse(let message) = TranscriptionPendingGate.decide(recorderState: policy.state,
                                                                          awaitingTranscript: awaitingTranscript,
                                                                          message: Edition.Copy.transcriptionPendingNotice) {
                Log.record(.startRefusedTranscriptPending)
                RecordingHUD.showSending(notice: message, transmitting: transmitting)
                return
            }
            if policy.state == .idle, permissions.microphone != .granted {
                refreshPermissions()
                if permissions.microphone != .granted {
                    Log.record(.startRefusedNoMicrophonePermission)
                    RecordingHUD.showNotice("麥克風權限未開啟，錄音沒有開始（選單列 Talkiie →「設定…」→「權限」）")
                    return
                }
            }
            feed(.hotkeyPressed(now: Self.monotonicNow(), secure: HotkeyMonitor.currentSecureInput()), at: pressedAt)
        case .sleepOrLock:
            Log.record(.sleepOrLock)
            feed(.sleepOrLock)
        }
    }

    private func recordingKeyPressed(_ key: RecordingKey) {
        let pressedAt = LatencyTimeline.now()
        Log.record(.recordingKeyPressed(key))
        feed(key.policyEvent(secure: HotkeyMonitor.currentSecureInput()), at: pressedAt)
    }

    private func stopKeyTapped() {
        guard case .recording = policy.state else { return }
        let pressedAt = LatencyTimeline.now()
        Log.record(.stopKeyTapped)
        feed(.confirmKey(secure: HotkeyMonitor.currentSecureInput()), at: pressedAt)
    }

    func capsuleButton(_ button: CapsuleButton) {
        let clickedAt = LatencyTimeline.now()
        Log.record(.capsuleButton(button))
        #if DEBUG
        debugCapsuleClicks += 1
        #endif
        guard case .recording = policy.state else { return }
        switch button {
        case .confirm:
            let target = TranscriptDelivery.freezeTarget()
            #if DEBUG
            debugLastClickFrozen = target
            #endif
            feed(.confirmKey(secure: HotkeyMonitor.currentSecureInput()), at: clickedAt, frozenAtClick: target)
        case .cancel:
            feed(.cancelKey)
        }
    }

    private func feed(_ event: HotkeyPolicy.Event, at: UInt64 = LatencyTimeline.now(),
                      frozenAtClick: FrozenTarget?? = nil) {
        let action = policy.handle(event)
        switch action {
        case .none:
            break
        case .startRecording:
            let roundTimeline = RoundTimeline(pressedAt: at)
            timeline = nil
            do {
                try capture.start()
            } catch {
                policy = HotkeyPolicy()
                capture.wipe()
                endRecordingKeys()
                Log.record(error.logEvent)
                RecordingHUD.showNotice(error.message)
                return
            }
            roundTimeline.mark(.engineRunning)
            timeline = roundTimeline
            playStartChime(after: action)
            beginRecordingSession()
        case .stopRecording(let reason):
            Log.record(.recordingStopped(reason))
            let roundTimeline = timeline
            timeline = nil
            roundTimeline?.mark(.stopPressed, at: at)
            endRecordingKeys()
            stopSecureInputPoll()
            let target = reason.sendsAudio ? (frozenAtClick ?? TranscriptDelivery.freezeTarget()) : nil
            let stopStarted = DispatchTime.now().uptimeNanoseconds
            roundTimeline?.mark(.targetFrozen, at: stopStarted)
            capture.stopEngine()
            let engineStoppedAt = DispatchTime.now().uptimeNanoseconds
            roundTimeline?.mark(.engineStopped, at: engineStoppedAt)
            Log.record(.engineStopped(millis: Int((engineStoppedAt - stopStarted) / 1_000_000)))
            if StartChime.shouldPlayStop(enabled: StartChimePlayer.isEnabled, reason: reason) {
                StartChimePlayer.shared.playStop()
            }
            if reason.sendsAudio {
                let round = streaming ?? startStreamingRound(timeline: roundTimeline)
                var none: [Float] = []
                let summary = capture.pipeline.map { round.stop(pipeline: $0) }
                    ?? round.stop(tail: &none, startFrame: 0)
                roundTimeline?.handedOff(summary)
                capture.wipe()
                recordingStopped(reason)
                transcribe(round, summary, stoppedAt: stopStarted, target: target, timeline: roundTimeline)
            } else {
                capture.wipe()
                cancelStreaming()
                recordingStopped(reason)
                UsageStatsRecorder.record(UsageRound(result: .cancelled))
            }
        case .refuseToStart(let message):
            Log.record(.refusedToStartSecureInput(message))
            RecordingHUD.showNotice(message.text)
        }
    }

    private func playStartChime(after action: HotkeyPolicy.Action) {
        guard StartChime.shouldPlay(enabled: StartChimePlayer.isEnabled, action: action,
                                    captureStarted: capture.isRunning) else { return }
        let preset = StartChimePlayer.preset
        guard let playedAt = StartChimePlayer.shared.play(preset),
              let until = StartChime.discardUntil(playedAt: playedAt, preset: preset) else { return }
        capture.discardAudio(until: until)
    }

    private func beginRecordingSession() {
        startStreamingRound(timeline: timeline)
        startSecureInputPoll()
        Log.record(.recordingStarted)
        if UsageStatsRecorder.enabled { whisperWarmer?.pressed(allowsCapture: ConsentStore.allowsCapture) }
        TranscriptDelivery.warmUpFocus()
        var caption = registerRecordingKeys()
        if capture.deviceChoiceFailed {
            let note = "選的麥克風無法使用，這次用的是系統設定的麥克風"
            caption = caption.map { "\(note)；\($0)" } ?? note
        }
        recordingStarted(caption: caption)
    }

    static var stopTrigger: StopTrigger {
        StopTrigger.resolve(stored: UserDefaults.standard.string(forKey: StopTrigger.defaultsKey))
    }

    private func registerRecordingKeys() -> String? {
        fnMonitor?.beginRecordingStopWatch()
        guard let monitor = hotkeyMonitor else { return nil }
        let failures = monitor.registerRecordingKeys(stopTrigger: Self.stopTrigger)
        Log.record(.recordingKeysRegistered(registered: monitor.registeredRecordingKeys.count, failed: failures.count))
        return Self.recordingKeyCaption(failed: failures.map(\.key))
    }

    static func recordingKeyCaption(failed: [RecordingKey]) -> String? {
        guard !failed.isEmpty else { return nil }
        let named = RecordingKey.allCases.filter(failed.contains)
        var names = named.map(\.label)
        let otherCount = failed.count - named.count
        if otherCount > 0 { names.append("其他 \(otherCount) 個鍵") }
        let fallback = failed.contains(.escape) ? "請點 ✕ 取消" : "請點 ✓ 或再按 \(hotkeyStartPhrase) 結束"
        return "\(names.joined(separator: "、")) 無法使用（可能被其他 app 佔用），\(fallback)"
    }

    private func endRecordingKeys() {
        hotkeyMonitor?.unregisterRecordingKeys()
        fnMonitor?.endRecordingStopWatch()
    }

    private func startSecureInputPoll() {
        stopSecureInputPoll()
        let t = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.feed(.tick(now: Self.monotonicNow(), secure: HotkeyMonitor.currentSecureInput()))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        secureInputPoll = t
    }

    private func stopSecureInputPoll() {
        secureInputPoll?.invalidate()
        secureInputPoll = nil
    }

    private func abortRecording(_ message: String) {
        guard case .recording = policy.state else { return }
        Log.record(.recordingAborted)
        timeline = nil
        policy = HotkeyPolicy()
        endRecordingKeys()
        stopSecureInputPoll()
        capture.stopEngine()
        capture.wipe()
        cancelStreaming()
        phase = .idle
        RecordingHUD.showNotice(message)
        UsageStatsRecorder.record(UsageRound(result: .cancelled))
    }

    @discardableResult
    private func startStreamingRound(timeline: RoundTimeline?) -> StreamingTranscription {
        streaming?.cancel()
        let round = StreamingTranscription(transcriber: transcriber, punctuator: punctuator,
                                           dictionary: PersonalDictionaryStore.current)
        #if DEBUG && RESEARCH_CAPTURE
        AudioPipeline.zeroize(&researchAudio)
        researchAudio = []
        if ResearchCapture.shared.isEnabled {
            round.onChunkSending = { [weak self] chunk in self?.researchAudio.append(contentsOf: chunk) }
        }
        #endif
        var researchOn = false
        #if DEBUG && RESEARCH_CAPTURE
        researchOn = ResearchCapture.shared.isEnabled
        #endif
        round.speculation = Edition.speculativeTailAllowed
            ? SpeculativeTailSetting.policy(fromDefaults: UserDefaults.standard.object(forKey: SpeculativeTailSetting.defaultsKey),
                                            researchCapture: researchOn)
            : nil
        round.onChunkFinished = { report in
            Log.record(.chunkTranscribed(index: report.index, millis: report.millis,
                                         succeeded: report.succeeded, tail: report.isTail,
                                         prepMillis: report.timing?.prepMillis,
                                         networkMillis: report.timing?.networkMillis,
                                         parseMillis: report.timing?.parseMillis,
                                         queuedMillis: report.queuedMillis,
                                         shortPadMillis: report.shortPaddingMillis))
            timeline?.chunkFinished(report)
        }
        round.onChunkRetry = { r in
            Log.record(.chunkRetry(index: r.index, succeeded: r.succeeded, firstError: r.firstError, millis: r.millis))
        }
        round.onPersonalDictionary = { r in
            Log.record(.personalDictionary(replacements: r.replacements, fuzzy: r.fuzzyReplacements,
                                           promptTerms: r.promptTerms, promptWithheldChunks: r.promptWithheldChunks,
                                           promptManual: r.promptManual, promptLearned: r.promptLearned,
                                           promptDropped: r.promptDropped, promptGated: r.promptGated,
                                           promptTokens: r.promptTokens, spelling: r.spellingReplacements))
        }
        round.onPunctuation = { report in
            Log.record(.punctuation(applied: report.applied, fallback: report.fallback, millis: report.millis,
                                    marks: report.marks, alignedPercent: report.alignedPercent))
            timeline?.punctuated(report)
        }
        round.fillerStrength = FillerRemoval.strength(
            fromDefaults: UserDefaults.standard.string(forKey: FillerRemoval.defaultsKey))
        round.spokenLists = SpokenList.enabled(fromDefaults: UserDefaults.standard.object(forKey: SpokenList.defaultsKey))
        round.listToggle = ListToggle.enabled(fromDefaults: UserDefaults.standard.object(forKey: ListToggle.defaultsKey))
        round.spokenCommands = SpokenCommands.enabled(
            fromDefaults: UserDefaults.standard.object(forKey: SpokenCommands.defaultsKey))
        round.paragraphStrength = SemanticParagraphs.strength(
            fromDefaults: UserDefaults.standard.string(forKey: SemanticParagraphs.defaultsKey))
        roundWrittenStyle = Edition.offersWrittenStyle
            ? WrittenStyle.roundMode(enabled: UserDefaults.standard.object(forKey: WrittenStyle.enabledDefaultsKey),
                                     mode: UserDefaults.standard.string(forKey: WrittenStyle.modeDefaultsKey))
            : nil
        if let mode = roundWrittenStyle {
            let rewriter = self.rewriter
            Task.detached(priority: .utility) { await WrittenStyleRound.warmUp(mode: mode, rewriter: rewriter) }
        }
        round.onFillerRemoval = { report in
            Log.record(.fillerRemoval(strength: report.strength, spans: report.spans,
                                      characters: report.characters, guardRejected: report.guardRejected))
        }
        streaming = round
        return round
    }

    private func streamIngested(_ levels: [Float], _ pipeline: AudioPipeline) {
        guard case .recording = policy.state, let round = streaming else { return }
        if let cut = round.ingested(levels: levels, pipeline: pipeline) {
            Log.record(.chunkCut(millis: cut.frames * 1000 / AudioBuffer.sampleRate, forced: cut.reason == .forced))
        }
    }

    private func cancelStreaming() {
        guard let round = streaming else { return }
        streaming = nil
        #if DEBUG && RESEARCH_CAPTURE
        AudioPipeline.zeroize(&researchAudio)
        researchAudio = []
        #endif
        if round.chunksSent > 0 { Log.record(.streamCancelled(chunksSent: round.chunksSent)) }
        round.cancel()
    }

    private func transcribe(_ round: StreamingTranscription, _ summary: StreamingTranscription.StopSummary,
                            stoppedAt: UInt64, target: FrozenTarget?, timeline: RoundTimeline?) {
        sendingTimeline = timeline
        guard case .sending(let since) = phase, streaming === round else { round.cancel(); return }
        let level = summary.level
        Log.record(.handoff(seconds: level.seconds, peakDBFS: level.peakDBFS, rmsDBFS: level.rmsDBFS, silent: level.isSilent))
        guard !summary.isEmpty else {
            cancelStreaming()
            capture.rebuildEngineOnNextStart(.noAudioLastRound)
            consecutiveEmptyRounds += 1
            UsageStatsRecorder.record(UsageRound(
                result: .failed, recordingMillis: timeline?.value.millis(from: .hotkeyPressed, to: .stopPressed)))
            transcriptionFailed(consecutiveEmptyRounds == 1
                ? "麥克風沒有送出任何聲音，這段沒有送出。已重新接上麥克風，請再說一次"
                : "麥克風還是沒有聲音。請從選單列結束 Talkiie 再重新打開，並檢查 系統設定 → 聲音 → 輸入")
            return
        }
        consecutiveEmptyRounds = 0
        if summary.inFlight > 0 { transmissionStarted() }
        #if DEBUG && RESEARCH_CAPTURE
        let researchRound = summary.chunksSent > 0
            ? ResearchCapture.shared.roundSent(researchAudio, scriptLineID: ReadScriptWindow.armedLineID()) : nil
        AudioPipeline.zeroize(&researchAudio)
        researchAudio = []
        #endif
        Task { [weak self] in
            let outcome = await round.outcome()
            timeline?.mark(.textReady)
            let current = self.map { $0.phase == .sending(since: since) && $0.streaming === round } ?? false
            let delivers: Bool = { if current, case .text(let t)? = outcome, !t.isEmpty { return true } else { return false } }()
            let finishedTimeline = outcome != nil && !delivers ? timeline?.finish() : nil
            #if DEBUG && RESEARCH_CAPTURE
            if let outcome {
                ResearchCapture.shared.roundTranscribed(researchRound, outcome, timeline: finishedTimeline,
                                                        texts: round.debugTexts, provenance: round.debugProvenance,
                                                        confidence: round.debugConfidence,
                                                        speaker: Self.speaker, transcriptionPath: Self.transcriptionPath)
            }
            #endif
            _ = finishedTimeline
            let isText: Bool = { if case .text = outcome { return true } else { return false } }()
            Log.record(.roundLatency(stopToTextMillis: Int((DispatchTime.now().uptimeNanoseconds - stoppedAt) / 1_000_000),
                                     chunks: summary.chunksSent, tailSent: summary.tailSent, succeeded: isText,
                                     speculativeSends: summary.speculativeSends,
                                     tailFromSpeculation: summary.tailFromSpeculation))
            guard let outcome, let self, current else { return }
            self.streaming = nil
            switch outcome {
            case .text(let text):
                if text.isEmpty { UsageStatsRecorder.record(UsageRound(result: .failed, stages: finishedTimeline)) }
                Log.record(.transcriptionSucceeded)
                self.lastRemoteFailure = nil
                let converted = TraditionalChinese.convert(text)
                timeline?.mark(.converted)
                let listOffer = round.listToggleOffer.map {
                    ListToggleOffer(kind: $0.kind, alternate: TraditionalChinese.convert($0.alternate))
                }
                guard let mode = self.roundWrittenStyle, !converted.isEmpty else {
                    self.transcriptionFinished(converted, listOffer: listOffer, target: target, timeline: timeline)
                    return
                }
                let budget = Self.sendTimeoutSeconds - Date().timeIntervalSince(since)
                let keepWords = WrittenStyleKeepWordsStore.current
                let rewriter = self.rewriter
                let task = Task.detached(priority: .userInitiated) {
                    await WrittenStyleRound.run(converted, mode: mode, keepWords: keepWords, rewriter: rewriter, budget: budget)
                }
                self.transcriptionFinished(converted, listOffer: listOffer, rewrite: PendingRewrite(mode: mode, task: task),
                                           target: target, timeline: timeline)
            case .failed(let message):
                Log.record(.transcriptionFailed(unimplemented: message == UnimplementedTranscriber.message))
                if Edition.isRemoteUnreachable(message) { self.lastRemoteFailure = Date() }
                UsageStatsRecorder.record(UsageRound(result: .failed, stages: finishedTimeline))
                self.transcriptionFailed(message + "\n" + level.text)
            }
        }
    }

    private static func readPermissions(accessibilityPrompted: Bool) -> PermissionGuidance.State {
        PermissionGuidance.State(microphone: Permissions.microphoneStatus(),
                                 accessibilityTrusted: Permissions.accessibilityTrusted(),
                                 accessibilityPrompted: accessibilityPrompted)
    }

    func refreshPermissions() {
        let new = Self.readPermissions(accessibilityPrompted: accessibilityPrompted)
        if new != permissions {
            if permissions.microphone != .granted, new.microphone == .granted {
                capture.rebuildEngineOnNextStart(.permissionGranted)
            }
            Log.record(.permissions(new))
            permissions = new
        }
    }

    func perform(_ action: PermissionGuidance.Action) {
        switch action {
        case .requestMicrophone:
            Permissions.requestMicrophone { _ in
                Task { @MainActor in AppModel.shared.refreshPermissions() }
            }
        case .openMicrophoneSettings:
            Permissions.openSettings(.microphone)
        case .promptAccessibility:
            Permissions.promptAccessibility()
            accessibilityPrompted = true
            refreshPermissions()
        case .openAccessibilitySettings:
            Permissions.openSettings(.accessibility)
        }
    }

    func recordingStarted(caption: String? = nil) {
        ListToggleController.shared.newRoundStarted()
        let since = Date()
        phase = .recording(since: since)
        RecordingHUD.showRecording(since: since, caption: caption)
    }

    func recordingStopped(_ reason: RecordingStopReason) {
        if reason.sendsAudio {
            let since = Date()
            phase = .sending(since: since)
            sendingNotice = reason.hudMessage
            transmitting = false
            RecordingHUD.showSending(notice: reason.hudMessage, transmitting: false)
            sendWatchdog?.cancel()
            sendWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.sendTimeoutSeconds))
                guard !Task.isCancelled, let self, self.phase == .sending(since: since) else { return }
                Log.record(.transcriptionTimedOut)
                if Edition.timeoutMeansRemoteUnreachable { self.lastRemoteFailure = Date() }
                let stages = self.sendingTimeline?.finish(timedOut: true)
                UsageStatsRecorder.record(UsageRound(result: .failed, stages: stages))
                self.transcriptionFailed(Edition.Copy.timeoutMessage)
            }
        } else {
            phase = .idle
            if let message = reason.hudMessage {
                RecordingHUD.showNotice(message)
            } else {
                RecordingHUD.hide()
            }
        }
    }

    func transcriptionFinished(_ text: String, listOffer: ListToggleOffer? = nil, rewrite: PendingRewrite? = nil,
                               target: FrozenTarget?, timeline: RoundTimeline? = nil) {
        finishRound(with: text) {
            await self.deliverNewTranscript(text, listOffer: listOffer, rewrite: rewrite, to: target, timeline: timeline)
        }
    }

    struct PendingRewrite {
        let mode: WrittenStyleMode
        let task: Task<WrittenStyleResult, Never>
    }

    private func finishRound(with text: String, deliver: @escaping @MainActor () async -> Void) {
        deliveringNewTranscript = !text.isEmpty
        guard endRound(with: text) else { return }
        Task {
            await deliver()
            self.deliveringNewTranscript = false
        }
    }

    private func endRound(with text: String) -> Bool {
        sendWatchdog?.cancel(); sendWatchdog = nil
        streaming = nil
        phase = .idle
        sendingNotice = nil
        transmitting = false
        guard !text.isEmpty else {
            RecordingHUD.showNotice(Edition.Copy.emptyTranscriptNotice)
            return false
        }
        return true
    }

    @discardableResult
    func deliverNewTranscript(_ text: String, listOffer: ListToggleOffer? = nil, rewrite: PendingRewrite? = nil,
                              to target: FrozenTarget?,
                              timeline: RoundTimeline? = nil) async -> TranscriptDelivery.Outcome {
        let serial = history.record(text, listAlternate: listOffer?.alternate, listKind: listOffer?.kind)
        let marks = timeline.map { _ in TranscriptDelivery.Marks() }
        let round = ListToggleController.shared.roundSerial
        let spot = (listOffer != nil || rewrite != nil) ? TranscriptDelivery.SpotBox() : nil
        let outcome = await deliver(text, to: target, marks: marks, spot: spot)
        if let marks { timeline?.delivered(marks) }
        let insertedFully: Bool = { if case .inserted = outcome { return true } else { return false } }()
        let stages: LatencyStages?
        if let rewrite {
            stages = timeline?.snapshot()
            Task {
                let result = await rewrite.task.value
                timeline?.rewritten(result.report)
                timeline?.finish()
                self.afterInsertion(text, serial: serial, round: round, insertedFully: insertedFully, spot: spot?.spot,
                                    listOffer: listOffer, rewrite: (rewrite.mode, result))
            }
        } else {
            stages = timeline?.finish()
            afterInsertion(text, serial: serial, round: round, insertedFully: insertedFully, spot: spot?.spot,
                           listOffer: listOffer, rewrite: nil)
        }
        if timeline != nil {
            let inserted: Bool = { if case .inserted = outcome { return true } else { return false } }()
            UsageStatsRecorder.record(UsageRound(result: inserted ? .inserted : .notInserted,
                                                 characters: inserted ? UsageStats.characterCount(text) : 0,
                                                 stages: stages))
            if inserted { FeatureNudgeCenter.shared.afterSuccessfulInsertion() }
        }
        #if DEBUG && RESEARCH_CAPTURE
        ResearchCapture.shared.roundDelivered(outcome, insertedText: text, timeline: stages)
        #endif
        _ = stages
        return outcome
    }

    private func afterInsertion(_ inserted: String, serial: Int?, round: Int, insertedFully: Bool,
                                spot: InsertionSpot<FocusedElementIdentity>?, listOffer: ListToggleOffer?,
                                rewrite: (mode: WrittenStyleMode, result: WrittenStyleResult)?) {
        let alternate = rewrite.flatMap { WrittenStyleSwap.alternate($0.result, inserted: inserted) }
        if let alternate, let serial, let mode = rewrite?.mode { history.attachRewritten(alternate, mode: mode, to: serial) }
        let choice = WrittenStyleSwap.choose(insertedFully: insertedFully,
                                             newRoundStarted: ListToggleController.shared.roundSerial != round,
                                             idle: phase == .idle, rewrite: alternate, list: listOffer)
        func logWrittenStyle(offered: Bool) {
            guard let r = rewrite?.result.report else { return }
            Log.record(.writtenStyle(mode: r.mode, passed: alternate != nil, offered: offered, fallback: r.fallback,
                                     rejection: r.rejection, millis: r.millis, changedPercent: r.changedPercent))
        }
        switch choice {
        case .writtenStyle(let rewritten)?:
            if let listOffer { Log.record(.listToggle(.notShown(listOffer.kind, reason: nil))) }
            ListToggleController.shared.offer(.writtenStyle, alternate: rewritten, spot: spot,
                                              onShown: { logWrittenStyle(offered: $0) },
                                              onReplaced: { [weak self] in
                                                  guard let self, let serial else { return }
                                                  self.history.applyRewritten(to: serial)
                                              })
        case .list(let offer)?:
            logWrittenStyle(offered: false)
            ListToggleController.shared.offer(.list(offer.kind), alternate: offer.alternate, spot: spot)
        case nil:
            logWrittenStyle(offered: false)
            if let listOffer { Log.record(.listToggle(.notShown(listOffer.kind, reason: nil))) }
        }
    }

    private func deliver(_ text: String, to target: FrozenTarget?,
                         marks: TranscriptDelivery.Marks? = nil,
                         announceSuccess: Bool = true,
                         spot: TranscriptDelivery.SpotBox? = nil) async -> TranscriptDelivery.Outcome {
        let outcome: TranscriptDelivery.Outcome
        if inserting {
            outcome = .busy
        } else {
            inserting = true
            let trace = EditCaptureController.shared.makeTrace()
            outcome = await TranscriptDelivery.deliver(text, to: target, marks: marks, trace: trace, spot: spot)
            inserting = false
            EditCaptureController.shared.deliveryFinished(outcome, trace: trace)
        }
        Log.record(.insertion(outcome))
        if case .refused(.accessibilityNotTrusted) = outcome { refreshPermissions() }
        if announceSuccess || !DeliveryContent(outcome).succeeded { presentDelivery(outcome, text: text) }
        return outcome
    }

    func replaceForListToggle(_ spot: InsertionSpot<FocusedElementIdentity>,
                              with text: String) async -> ListToggleResult {
        guard !inserting, phase == .idle else {
            return .aborted(.cursorMoved, collapsedSelection: false, typedUnits: 0)
        }
        inserting = true
        defer { inserting = false }
        return await TranscriptDelivery.replaceForListToggle(spot, with: text)
    }

    private func presentDelivery(_ outcome: TranscriptDelivery.Outcome, text: String) {
        guard phase == .idle else { return }
        if !text.isEmpty, let reason = Self.fallbackPanelReason(outcome) {
            RecordingHUD.hide()
            FallbackPanel.show(text: text, reason: reason)
            Log.record(.fallbackPanel(.shown))
            return
        }
        RecordingHUD.showDelivery(outcome, text: text)
    }

    static func fallbackPanelReason(_ outcome: TranscriptDelivery.Outcome) -> String? {
        switch outcome {
        case .refused(let reason):
            return DeliveryFallback.presentation(refusal: reason) == .textPanel ? reason.message : nil
        case .aborted(let sentUnits, let reason):
            return DeliveryFallback.presentation(abortedAfter: sentUnits, reason: reason) == .textPanel ? reason.text : nil
        case .inserted, .busy:
            return nil
        }
    }

    func reinsert(_ text: String) {
        Log.record(.dictationReinsertRequested)
        Task {
            try? await Task.sleep(for: .seconds(Self.reinsertDelaySeconds))
            _ = await self.deliver(text, to: TranscriptDelivery.freezeTarget(stage: .reinsert), announceSuccess: false)
        }
    }

    func insertOriginal(_ entry: DictationHistory.Entry) {
        guard let original = entry.original else { return reinsert(entry.text) }
        reinsert(original)
        let offered = WrittenStyleKeepWords.deletedWords(original: original, rewritten: entry.text)
        var recorded = false
        if EditCaptureSettings.isEnabled, let mode = entry.rewriteMode {
            recorded = true
            let record = RewriteRevertRecord(capturedAt: Date(), mode: mode, original: original, rewritten: entry.text)
            let retention = EditCaptureSettings.retention
            Task { _ = await EditCorrectionStore.shared.appendRevert(record, retention: retention) }
        }
        Log.record(.originalReinserted(mode: entry.rewriteMode, recorded: recorded, offeredWords: offered.count))
        if !offered.isEmpty {
            Task {
                try? await Task.sleep(for: .seconds(Self.reinsertDelaySeconds + 0.4))
                RevertMarksPanel.show(words: offered)
            }
        }
    }

    func copyToClipboard(_ text: String) {
        Log.record(.dictationCopied)
        Clipboard.copy(text)
    }

    func clearHistory() {
        history.clear()
        FallbackPanel.close()
        RevertMarksPanel.close()
        EditCaptureController.shared.forget()
        Log.record(.dictationHistoryCleared)
    }

    func transmissionStarted() {
        guard case .sending = phase else { return }
        transmitting = true
        RecordingHUD.showSending(notice: sendingNotice, transmitting: true)
    }

    func transcriptionFailed(_ message: String) {
        sendWatchdog?.cancel(); sendWatchdog = nil
        cancelStreaming()
        phase = .idle
        sendingNotice = nil
        transmitting = false
        RecordingHUD.showNotice(message)
    }

    static func elapsed(since: Date, now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(since)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    #if DEBUG
    var debugMainHotkeyRegistered: Bool? { hotkeyMonitor?.isMainRegistered }
    var debugEditCaptureKeyRegistered: Bool? { hotkeyMonitor?.isEditCaptureKeyRegistered }
    func debugPressEditCaptureKey() -> EditCaptureRefusal? { EditCaptureController.shared.pressed(inserting: inserting) }

    func selfTestTranscribe(_ samples: [Float]) async -> TranscriptionOutcome {
        await transcriber.transcribe(samples)
    }
    func selfTestStreamingRound() -> StreamingTranscription {
        StreamingTranscription(transcriber: transcriber)
    }
    func debugPreviewRecording() { recordingStarted() }

    private(set) var debugCapsuleClicks = 0
    var debugLastClickFrozen: FrozenTarget?
    var debugRegisteredRecordingKeys: Set<RecordingKey>? { hotkeyMonitor?.registeredRecordingKeys }
    var debugRecorderIsIdle: Bool { policy.state == .idle }

    func debugBeginSimulatedRecording() -> Bool {
        let clear = SecureInputPolicy.State(systemSecureInputEnabled: false, focusIsSecureTextField: false,
                                            isRecording: false)
        guard case .startRecording = policy.handle(.hotkeyPressed(now: Self.monotonicNow(), secure: clear)) else {
            return false
        }
        timeline = nil
        beginRecordingSession()
        return true
    }
    func debugAbortRecording() { abortRecording("selftest：模擬音訊裝置中斷") }
    func debugFeedRecordingKey(_ key: RecordingKey) { recordingKeyPressed(key) }
    func debugPressHotkey() { hotkeyEvent(.hotkeyPressed) }
    func debugFinishRound(_ text: String, simulated outcome: TranscriptDelivery.Outcome) {
        finishRound(with: text) {
            self.history.record(text)
            self.presentDelivery(outcome, text: text)
        }
    }
    func debugPreviewTranscriptionDone() {
        debugFinishRound("這是 HUD 預覽用的假轉錄文字。", simulated: .inserted(.enforced))
    }
    func debugPreviewTranscriptionFailed() { transcriptionFailed(Edition.transcriptionFailureMessage) }
    #endif
}

@MainActor
final class RoundTimeline {
    private(set) var value = LatencyTimeline()
    private var finished: LatencyStages?

    init(pressedAt: UInt64) { value.mark(.hotkeyPressed, at: pressedAt) }

    func mark(_ m: LatencyMark, at t: UInt64 = LatencyTimeline.now()) { value.mark(m, at: t) }

    func chunkFinished(_ report: StreamingTranscription.ChunkReport) { value.record(report) }

    func punctuated(_ report: PunctuationReport) { value.record(report) }

    func rewritten(_ report: RewriteReport) { value.record(report) }

    func snapshot() -> LatencyStages { finished ?? value.stages() }

    func handedOff(_ summary: StreamingTranscription.StopSummary) {
        value.mark(.tailHandedOff)
        value.chunksSent = summary.chunksSent
        value.tailSent = summary.tailSent
    }

    func delivered(_ marks: TranscriptDelivery.Marks) {
        if let t = marks.started { value.mark(.insertionStarted, at: t) }
        if let t = marks.firstKeystroke { value.mark(.firstKeystroke, at: t) }
        if let t = marks.done { value.mark(.insertionDone, at: t) }
    }

    @discardableResult
    func finish(timedOut: Bool = false) -> LatencyStages {
        if let finished { return finished }
        var stages = value.stages()
        if timedOut { stages.timedOut = true }
        finished = stages
        Log.record(.roundTimeline(stages))
        return stages
    }
}

#if DEBUG
enum RecordingStopReasonMenu {
    static let all = RecordingStopReason.allCases
}
#endif
