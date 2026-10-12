import OSLog
import NaturalInputCore
import NaturalInputEgress

enum LogEvent {
    case hotkeyRegistered(Bool)
    case hotkeyChanged(ok: Bool, isDefault: Bool)
    case launchAtLogin(on: Bool, byUser: Bool, ok: Bool)
    case hotkeyPressed(wasRecording: Bool)
    case sleepOrLock
    case startRefusedNoMicrophonePermission
    case startRefusedTranscriptPending
    case startFailedNoInputDevice
    case startFailedEngine(code: Int)
    case recordingStarted
    case recordingStopped(RecordingStopReason)
    case refusedToStartSecureInput(SecureInputPolicy.Message)
    case recordingAborted
    case inputFormat(sampleRate: Double, channels: UInt32, interleaved: Bool)
    case configurationChange(sampleRate: Double, channels: UInt32, previousRate: Double)
    case inputLost
    case tapHotkey(mode: TapHotkey)
    case doubleTap
    case singleModifierTap
    case fnTapInterrupted(eventType: UInt)
    case inputMonitoringPreflight(allowed: Bool)
    case feedbackSent(ok: Bool, status: Int?)
    case fnKey(down: Bool, others: Bool, tapped: Bool)
    case engineRebuilt(EngineRebuildReason)
    case inputDeviceApplied(ok: Bool)
    case reconnectFailed(code: Int)
    case bufferFull
    case handoff(seconds: Double, peakDBFS: Double, rmsDBFS: Double, silent: Bool)
    case transcriptionFailed(unimplemented: Bool)
    case transcriptionSucceeded
    case engineStopped(millis: Int)
    case chunkCut(millis: Int, forced: Bool)
    case chunkTranscribed(index: Int, millis: Int, succeeded: Bool, tail: Bool,
                          prepMillis: Int?, networkMillis: Int?, parseMillis: Int?, queuedMillis: Int?,
                          shortPadMillis: Int? = nil)
    case chunkRetry(index: Int, succeeded: Bool, firstError: TranscriptionFailureKind, millis: Int)
    case punctuation(applied: Bool, fallback: PunctuationFallback?, millis: Int?, marks: Int?, alignedPercent: Int?)
    case personalDictionary(replacements: Int, fuzzy: Int, promptTerms: Int, promptWithheldChunks: Int,
                            promptManual: Int, promptLearned: Int, promptDropped: Int, promptGated: Int,
                            promptTokens: Int, spelling: Int)
    case dictionaryLearned(added: Int, refreshed: Int, promptOnly: Int)
    case fillerRemoval(strength: FillerStrength, spans: Int, characters: Int, guardRejected: Bool)
    case roundLatency(stopToTextMillis: Int, chunks: Int, tailSent: Bool, succeeded: Bool,
                      speculativeSends: Int = 0, tailFromSpeculation: Bool = false)
    case streamCancelled(chunksSent: Int)
    case transcriptionTimedOut
    case permissions(PermissionGuidance.State)
    case hudPresent(width: Int, height: Int)
    case auroraGlowScreen(source: AuroraScreenSource, width: Int, height: Int)
    case insertion(TranscriptDelivery.Outcome)
    case focusObserved(stage: FocusStage, diagnostics: FocusDiagnostics?, editability: Editability,
                       marked: MarkedTextState, secureField: Bool, sameAsFrozen: Bool?, source: FocusSource?)
    case focusMissing(FocusStage, FocusMiss, micros: Int)
    case accessibilityEnablement(FocusStage, AccessibilityEnablement.Report)
    case insertionStats(probes: Int, totalMillis: Int, maxProbeMicros: Int)
    case cursorSettle(CursorSettleReport)
    case insertionPacingSwitched(afterChunk: Int, settleBudgetMs: Int)
    case insertionBaselineCorrected(stale: Int)
    case insertionBaselineRebased(stale: Int, corrected: Int)
    case startRefusedInsertionInProgress
    case dictationReinsertRequested
    case dictationCopied
    case dictationHistoryCleared
    case fallbackPanel(FallbackPanelEvent)
    case recordingKeysRegistered(registered: Int, failed: Int)
    case recordingKeyPressed(RecordingKey)
    case stopKeyTapped
    case capsuleButton(CapsuleButton)
    case insertionShape(paragraphs: Int, shiftReturn: Bool)
    case insertionPacing(InsertionPacing)
    case menuBarCarousel(frames: Int)
    case roundTimeline(LatencyStages)
    case startRefusedNoConsent
    case startRefusedModelNotReady
    case localModelDownloadRequested
    case localModelPrepared(millis: Int?)
    case localModelPrepareFailed
    case licenseActivated
    case licenseRejected(code: Int)
    case licenseStoreFailed
    case consentAccepted(version: Int)
    case onboarding(OnboardingLogEvent)
    case featureNudge(FeatureNudgeLogEvent)
    case updater(UpdaterEvent)
    case chimePlayed(StartChime.Preset, preview: Bool)
    case chimeUnavailable(StartChime.Preset)
    case chimeWindowDiscarded(millis: Int)
    case usageStatsPruned(files: Int)
    case usageStatsWriteFailed
    case usageStatsDeleted
    case editCaptureKey(enabled: Bool, shortcut: EditCaptureShortcut, registered: Bool)
    case editCapture(EditCaptureLogResult)
    case editCorrectionsPruned(files: Int)
    case editCorrectionsDeleted
    case writtenStyle(mode: WrittenStyleMode, applied: Bool, fallback: RewriteFallback?, rejection: RewriteRejection?,
                      millis: Int?, changedPercent: Int?)
    case originalReinserted(mode: WrittenStyleMode?, recorded: Bool, offeredWords: Int)
    case keepWordsMarked(added: Int, total: Int)
    case listToggle(ListToggleLogEvent)
    case whisperWarmUp(idleSeconds: Int?, latencyMillis: Int, ok: Bool)
}

enum EditCaptureLogResult {
    case saved(changed: Bool, alignedPercent: Int)
    case refused(EditCaptureRefusal)
}

enum UpdaterEvent {
    enum Refusal { case notConsented, busy, gate }
    case disabledInDebug
    case disabledNoPublicKey
    case notStartedNoConsent
    case started(automaticChecks: Bool)
    case startFailed
    case checkRefused(Refusal)
    case updateRejected
    case updateFound(build: Int?)
    case relaunchPostponed
    case relaunchResumed
    case aborted(code: Int)
    case releaseNotesRejected
    case reminderPending(build: Int?)
    case relaunchingIntoUpdate
    case whatsNewPending(releases: Int, window: Bool)
    case whatsNewShown(releases: Int)
    case whatsNewNoNotes
}

enum ListToggleLogEvent {
    enum Hidden: String { case timeout, moved, newRound, closed }
    case shown(ListToggleKind)
    case notShown(ListToggleKind, reason: ListToggleAbortReason?)
    case hidden(ListToggleKind, Hidden)
    case replaced(ListToggleKind, units: Int)
    case aborted(ListToggleKind, ListToggleAbortReason, collapsed: Bool, typedUnits: Int)
    case copied(ListToggleKind)
}

enum OnboardingLogEvent: Sendable {
    case audience(OnboardingPlan.Audience)
    case opened(OnboardingPlan.Step, reopened: Bool)
    case completed(skipped: Bool)
    case leftEarly(OnboardingPlan.Step)
    case refusedNoConsent
}

enum FeatureNudgeLogEvent: Sendable {
    case shown(NudgeFeature)
    case opened(NudgeFeature)
    case dismissed(NudgeFeature)
    case expired(NudgeFeature)
}

enum FallbackPanelEvent: Sendable {
    case shown
    case copied
}

enum Log {
    static let subsystem = Edition.logSubsystem
    private static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    private static let audio = Logger(subsystem: subsystem, category: "audio")
    private static let hud = Logger(subsystem: subsystem, category: "hud")
    private static let permission = Logger(subsystem: subsystem, category: "permission")
    private static let transcribe = Logger(subsystem: subsystem, category: "transcribe")
    private static let insert = Logger(subsystem: subsystem, category: "insert")
    private static let focus = Logger(subsystem: subsystem, category: "focus")
    private static let latency = Logger(subsystem: subsystem, category: "latency")
    private static let update = Logger(subsystem: subsystem, category: "update")

    static func record(_ e: LogEvent) {
        #if DEBUG && RESEARCH_CAPTURE
        ResearchCapture.shared.observe(e)
        #endif
        switch e {
        case .tapHotkey(let mode):
            hotkey.notice("tap hotkey mode=\(mode.rawValue, privacy: .public)")
        case .doubleTap:
            hotkey.notice("double tap")
        case .singleModifierTap:
            hotkey.notice("single modifier tap")
        case .fnKey(let down, let others, let tapped):
            hotkey.notice("fn \(down ? "down" : "up", privacy: .public) others=\(others, privacy: .public) tapped=\(tapped, privacy: .public)")
        case .feedbackSent(let ok, let status):
            update.notice("feedback sent ok=\(ok, privacy: .public) status=\(status ?? -1, privacy: .public)")
        case .inputMonitoringPreflight(let allowed):
            hotkey.notice("input monitoring preflight allowed=\(allowed, privacy: .public)")
        case .fnTapInterrupted(let type):
            hotkey.notice("fn tap interrupted by event type \(type, privacy: .public)")
        case .hotkeyRegistered(let ok):
            if ok { hotkey.notice("registered main hotkey") } else { hotkey.error("register failed main hotkey") }
        case .hotkeyChanged(let ok, let isDefault):
            hotkey.notice("main hotkey changed ok=\(ok, privacy: .public) default=\(isDefault, privacy: .public)")
        case .launchAtLogin(let on, let byUser, let ok):
            permission.notice("launch at login on=\(on, privacy: .public) byUser=\(byUser, privacy: .public) ok=\(ok, privacy: .public)")
        case .hotkeyPressed(let wasRecording):
            hotkey.notice("pressed wasRecording=\(wasRecording, privacy: .public)")
        case .sleepOrLock:
            hotkey.info("sleepOrLock")
        case .startRefusedNoMicrophonePermission:
            permission.error("start refused: microphone not granted")
        case .startRefusedTranscriptPending:
            hotkey.notice("start refused: previous transcription pending")
        case .startFailedNoInputDevice:
            audio.error("start failed: no input device")
        case .startFailedEngine(let code):
            audio.error("start failed: engine error \(code, privacy: .public)")
        case .recordingStarted:
            audio.notice("recording started")
        case .recordingStopped(let r):
            audio.notice("recording stopped reason=\(r.rawValue, privacy: .public) sendsAudio=\(r.sendsAudio, privacy: .public)")
        case .refusedToStartSecureInput(let m):
            hotkey.notice("refused to start: secure input (\(String(describing: m), privacy: .public))")
        case .recordingAborted:
            audio.error("recording aborted and wiped")
        case .inputDeviceApplied(let ok):
            audio.notice("input device applied ok=\(ok, privacy: .public)")
        case .engineRebuilt(let reason):
            audio.notice("engine rebuilt reason=\(reason.rawValue, privacy: .public)")
        case .inputFormat(let rate, let ch, let inter):
            audio.notice("input format \(rate, format: .fixed(precision: 0), privacy: .public)Hz ch=\(ch, privacy: .public) interleaved=\(inter, privacy: .public)")
        case .configurationChange(let rate, let ch, let prev):
            audio.notice("configuration change \(prev, format: .fixed(precision: 0), privacy: .public)Hz → \(rate, format: .fixed(precision: 0), privacy: .public)Hz ch=\(ch, privacy: .public)")
        case .inputLost:
            audio.error("input lost after configuration change")
        case .reconnectFailed(let code):
            audio.error("reconnect failed: engine error \(code, privacy: .public)")
        case .bufferFull:
            audio.notice("buffer reached capacity")
        case .handoff(let s, let peak, let rms, let silent):
            transcribe.notice("handoff \(s, format: .fixed(precision: 2), privacy: .public)s peak=\(peak, format: .fixed(precision: 1), privacy: .public)dBFS rms=\(rms, format: .fixed(precision: 1), privacy: .public)dBFS silent=\(silent, privacy: .public)")
        case .transcriptionFailed(let unimplemented):
            transcribe.notice("transcription failed unimplemented=\(unimplemented, privacy: .public)")
        case .chunkCut(let ms, let forced):
            transcribe.notice("chunk cut \(ms, privacy: .public)ms reason=\(forced ? "forced" : "pause", privacy: .public)")
        case .chunkTranscribed(let index, let ms, let ok, let tail, let prep, let net, let parse, let queued, let shortPad):
            func v(_ n: Int?) -> String { n.map(String.init) ?? "-" }
            transcribe.notice("chunk \(index, privacy: .public) latency \(ms, privacy: .public)ms succeeded=\(ok, privacy: .public) tail=\(tail, privacy: .public) prep=\(v(prep), privacy: .public) \(Edition.tailWorkKey.rawValue, privacy: .public)=\(v(net), privacy: .public) parse=\(v(parse), privacy: .public) queued=\(v(queued), privacy: .public) shortPad=\(v(shortPad), privacy: .public)ms")
        case .chunkRetry(let index, let ok, let firstError, let ms):
            transcribe.notice("chunk \(index, privacy: .public) retry result=\(ok ? "ok" : "failed", privacy: .public) firstErr=\(firstError.rawValue, privacy: .public) latency=\(ms, privacy: .public)ms")
        case .punctuation(let applied, let fallback, let ms, let marks, let aligned):
            func v(_ n: Int?) -> String { n.map(String.init) ?? "-" }
            transcribe.notice("punctuation applied=\(applied, privacy: .public) fallback=\(fallback?.rawValue ?? "-", privacy: .public) latency=\(v(ms), privacy: .public)ms marks=\(v(marks), privacy: .public) aligned=\(v(aligned), privacy: .public)%")
        case .fillerRemoval(let strength, let spans, let chars, let rejected):
            transcribe.notice("filler removal strength=\(strength.rawValue, privacy: .public) spans=\(spans, privacy: .public) chars=\(chars, privacy: .public) guardRejected=\(rejected, privacy: .public)")
        case .roundLatency(let ms, let chunks, let tailSent, let ok, let specSends, let specUsed):
            transcribe.notice("stop→text \(ms, privacy: .public)ms chunks=\(chunks, privacy: .public) tailSent=\(tailSent, privacy: .public) succeeded=\(ok, privacy: .public) spec=\(specUsed ? 1 : 0, privacy: .public)/\(specSends, privacy: .public)")
        case .personalDictionary(let n, let fuzzy, let terms, let withheld, let manual, let learned, let dropped, let gated,
                                 let tokens, let spelling):
            transcribe.notice("personal dictionary replacements=\(n, privacy: .public) fuzzy=\(fuzzy, privacy: .public) spelling=\(spelling, privacy: .public) promptTerms=\(terms, privacy: .public) manual=\(manual, privacy: .public) learned=\(learned, privacy: .public) dropped=\(dropped, privacy: .public) gated=\(gated, privacy: .public) tokens=\(tokens, privacy: .public)/\(TranscriptionPrompt.whisperPromptLimit, privacy: .public) promptWithheldChunks=\(withheld, privacy: .public)")
        case .streamCancelled(let n):
            transcribe.notice("round cancelled after \(n, privacy: .public) chunk(s) already sent\(Edition.Copy.chunksSentLogSuffix, privacy: .public)")
        case .engineStopped(let ms):
            audio.notice("engine stopped in \(ms, privacy: .public)ms")
        case .transcriptionSucceeded:
            transcribe.notice("transcription succeeded")
        case .transcriptionTimedOut:
            transcribe.error("transcription timed out")
        case .permissions(let s):
            permission.notice("permissions \(String(describing: s), privacy: .public)")
        case .hudPresent(let w, let h):
            hud.debug("present \(w, privacy: .public)x\(h, privacy: .public)")
        case .auroraGlowScreen(let source, let w, let h):
            hud.debug("aurora glow screen source=\(source.rawValue, privacy: .public) \(w, privacy: .public)x\(h, privacy: .public)")
        case .insertion(let outcome):
            switch outcome {
            case .inserted(let coverage):
                insert.notice("sent (unverified) raceGuard=\(coverage == .enforced ? "enforced" : "unverified", privacy: .public)")
            case .refused(let reason):
                insert.notice("refused reason=\(String(describing: reason), privacy: .public)")
            case .aborted(let sentUnits, let reason):
                insert.error("aborted reason=\(String(describing: reason), privacy: .public) partial=\(sentUnits > 0, privacy: .public)")
            case .busy:
                insert.notice("skipped: previous insertion in progress")
            }
        case .focusObserved(let stage, let d, let editability, let marked, let secure, let same, let source):
            let desc = d?.descendantRole.map { $0.rawValue } ?? "-"
            let descFocused = d?.descendantFocused.map { $0 ? "yes" : "no" } ?? "-"
            let sameText = same.map { $0 ? "yes" : "no" } ?? "-"
            focus.notice("\(stage.rawValue, privacy: .public) app=\(d?.app.rawValue ?? "?", privacy: .public) role=\(d?.role.rawValue ?? "?", privacy: .public)/\(d?.subrole.rawValue ?? "?", privacy: .public) editable=\(String(describing: editability), privacy: .public) descendant=\(desc, privacy: .public) descendantFocused=\(descFocused, privacy: .public) searched=\(d?.nodesSearched ?? -1, privacy: .public) lookup=\(d?.lookupMicros ?? -1, privacy: .public)us timeouts=\(d?.axTimeouts ?? -1, privacy: .public) source=\(source?.rawValue ?? "-", privacy: .public) range=\(d?.rangeReadable ?? false, privacy: .public) marked=\(String(describing: marked), privacy: .public) secure=\(secure, privacy: .public) sameAsFrozen=\(sameText, privacy: .public)")
        case .focusMissing(let stage, let miss, let micros):
            focus.notice("\(stage.rawValue, privacy: .public) no focus \(FocusLogText.miss(miss), privacy: .public) after=\(micros / 1_000, privacy: .public)ms")
        case .accessibilityEnablement(let stage, let report):
            focus.notice("\(stage.rawValue, privacy: .public) \(FocusLogText.enablement(report), privacy: .public)")
        case .insertionStats(let probes, let ms, let maxProbe):
            insert.notice("stats probes=\(probes, privacy: .public) total=\(ms, privacy: .public)ms maxProbe=\(maxProbe, privacy: .public)us")
        case .cursorSettle(let r):
            let final = r.finalOffset.map(String.init) ?? "unreadable"
            let outcome = r.caughtUp ? "caughtUp" : r.withinBreakSlack ? "breakSlack" : (r.polls == 0 ? "moved" : "gaveUp")
            insert.notice("cursor settle retries=\(r.polls, privacy: .public) first=\(r.firstOffset, privacy: .public) final=\(final, privacy: .public) outcome=\(outcome, privacy: .public)")
        case .insertionBaselineCorrected(let stale):
            insert.notice("cursor baseline corrected stale=\(stale, privacy: .public) reason=emptyFieldPlaceholder")
        case .insertionBaselineRebased(let stale, let corrected):
            insert.notice("cursor baseline corrected stale=\(stale, privacy: .public) now=\(corrected, privacy: .public) reason=staleReading")
        case .insertionPacingSwitched(let afterChunk, let budgetMs):
            insert.notice("insert pacing switched reason=lag afterChunk=\(afterChunk, privacy: .public) settleBudget=\(budgetMs, privacy: .public)ms")
        case .startRefusedInsertionInProgress:
            hotkey.notice("start refused: insertion in progress")
        case .dictationReinsertRequested:
            insert.notice("reinsert requested from recent dictation")
        case .dictationCopied:
            insert.notice("recent dictation copied to clipboard by user")
        case .fallbackPanel(let event):
            switch event {
            case .shown:
                insert.notice("fallback panel shown")
            case .copied:
                insert.notice("fallback panel: copied to clipboard by user")
            }
        case .dictationHistoryCleared:
            insert.notice("recent dictation cleared")
        case .recordingKeysRegistered(let registered, let failed):
            if failed == 0 {
                hotkey.notice("recording keys registered=\(registered, privacy: .public)")
            } else {
                hotkey.error("recording keys registered=\(registered, privacy: .public) failed=\(failed, privacy: .public)")
            }
        case .recordingKeyPressed(let key):
            hotkey.info("recording key \(key.label, privacy: .public)")
        case .stopKeyTapped:
            hotkey.info("stop key tapped")
        case .capsuleButton(let b):
            hud.info("capsule button \(b == .confirm ? "confirm" : "cancel", privacy: .public)")
        case .insertionPacing(let p):
            insert.notice("\(p.logText, privacy: .public)")
        case .insertionShape(let n, let shiftReturn):
            insert.notice("paragraphs=\(n, privacy: .public) separator=\(shiftReturn ? "shiftReturn" : "space", privacy: .public)")
        case .menuBarCarousel(let frames):
            if frames > 0 { hud.notice("menu bar carousel frames=\(frames, privacy: .public)") }
            else { hud.error("menu bar carousel unavailable; processing shows the idle glyph") }
        case .roundTimeline(let stages):
            latency.notice("timeline(ms) \(stages.compactDescription(tailWork: Edition.tailWorkKey), privacy: .public)")
        case .startRefusedNoConsent:
            hotkey.notice("start refused: first-run consent not given")
        case .startRefusedModelNotReady:
            hotkey.notice("start refused: local speech model not ready")
        case .localModelDownloadRequested:
            transcribe.notice("local model download requested")
        case .localModelPrepared(let ms):
            transcribe.notice("local model prepared load=\(ms.map(String.init) ?? "-", privacy: .public)ms")
        case .localModelPrepareFailed:
            transcribe.error("local model prepare failed")
        case .licenseActivated:
            permission.notice("license activated")
        case .licenseRejected(let code):
            permission.notice("license rejected code=\(code, privacy: .public)")
        case .licenseStoreFailed:
            permission.error("license store failed")
        case .consentAccepted(let version):
            permission.notice("consent accepted version=\(version, privacy: .public)")
        case .onboarding(let event):
            permission.notice("onboarding \(String(describing: event), privacy: .public)")
        case .featureNudge(let event):
            permission.notice("feature nudge \(String(describing: event), privacy: .public)")
        case .updater(let event):
            update.notice("\(String(describing: event), privacy: .public)")
        case .chimePlayed(let preset, let preview):
            audio.info("start chime preset=\(preset.rawValue, privacy: .public) preview=\(preview, privacy: .public)")
        case .chimeUnavailable(let preset):
            audio.error("start chime unavailable preset=\(preset.rawValue, privacy: .public)")
        case .chimeWindowDiscarded(let ms):
            audio.info("discarded \(ms, privacy: .public)ms of capture under the start chime")
        case .usageStatsPruned(let files):
            insert.notice("usage stats pruned files=\(files, privacy: .public)")
        case .usageStatsWriteFailed:
            insert.error("usage stats write failed")
        case .usageStatsDeleted:
            insert.notice("usage stats deleted by user")
        case .editCaptureKey(let enabled, let shortcut, let registered):
            hotkey.notice("edit capture enabled=\(enabled, privacy: .public) shortcut=\(shortcut.rawValue, privacy: .public) registered=\(registered, privacy: .public)")
        case .editCapture(.saved(let changed, let aligned)):
            insert.notice("edit capture saved changed=\(changed, privacy: .public) aligned=\(aligned, privacy: .public)%")
        case .editCapture(.refused(let reason)):
            insert.notice("edit capture refused reason=\(reason.rawValue, privacy: .public)")
        case .editCorrectionsPruned(let files):
            insert.notice("edit corrections pruned files=\(files, privacy: .public)")
        case .editCorrectionsDeleted:
            insert.notice("edit corrections deleted by user")
        case .writtenStyle(let mode, let applied, let fallback, let rejection, let ms, let changed):
            func v(_ n: Int?) -> String { n.map(String.init) ?? "-" }
            transcribe.notice("written style mode=\(mode.rawValue, privacy: .public) applied=\(applied, privacy: .public) fallback=\(fallback?.rawValue ?? "-", privacy: .public) rejection=\(rejection?.rawValue ?? "-", privacy: .public) latency=\(v(ms), privacy: .public)ms changed=\(v(changed), privacy: .public)%")
        case .originalReinserted(let mode, let recorded, let offered):
            insert.notice("original reinserted mode=\(mode?.rawValue ?? "-", privacy: .public) recorded=\(recorded, privacy: .public) offeredWords=\(offered, privacy: .public)")
        case .whisperWarmUp(let idle, let ms, let ok):
            transcribe.notice("whisper warmUp idle=\(idle.map(String.init) ?? "-", privacy: .public) latency=\(ms, privacy: .public) result=\(ok ? "ok" : "failed", privacy: .public)")
        case .listToggle(let event):
            switch event {
            case .shown(let kind):
                insert.notice("list toggle shown kind=\(kind.rawValue, privacy: .public)")
            case .notShown(let kind, let reason):
                insert.notice("list toggle notShown kind=\(kind.rawValue, privacy: .public) reason=\(reason?.rawValue ?? "noSpot", privacy: .public)")
            case .hidden(let kind, let why):
                insert.notice("list toggle hidden kind=\(kind.rawValue, privacy: .public) reason=\(why.rawValue, privacy: .public)")
            case .replaced(let kind, let units):
                insert.notice("list toggle result=replaced kind=\(kind.rawValue, privacy: .public) units=\(units, privacy: .public)")
            case .aborted(let kind, let reason, let collapsed, let typed):
                insert.notice("list toggle result=aborted kind=\(kind.rawValue, privacy: .public) reason=\(reason.rawValue, privacy: .public) collapsed=\(collapsed, privacy: .public) typedUnits=\(typed, privacy: .public)")
            case .copied(let kind):
                insert.notice("list toggle copied kind=\(kind.rawValue, privacy: .public)")
            }
        case .keepWordsMarked(let added, let total):
            insert.notice("keep words marked added=\(added, privacy: .public) total=\(total, privacy: .public)")
        case .dictionaryLearned(let added, let refreshed, let promptOnly):
            insert.notice("personal dictionary learned added=\(added, privacy: .public) refreshed=\(refreshed, privacy: .public) promptOnly=\(promptOnly, privacy: .public)")
        }
    }
}

#if DEBUG
enum SelfTestLine {
    case transcript(characters: Int)
    case emptyTranscript
    case remoteUnreachable
    case unexpectedFailure
    case usage
    case unreadableFixture
    case streamRun(run: Int, singleMillis: Int, singleCharacters: Int?, streamMillis: Int, streamCharacters: Int?,
                   chunks: Int, cutsDuringRecording: Int, forcedCuts: Int, tailSent: Bool, sameText: Bool,
                   tailPrepMillis: Int?, tailNetworkMillis: Int?, tailParseMillis: Int?, tailQueuedMillis: Int?)

    static func emit(_ line: SelfTestLine) {
        switch line {
        case .streamRun(let run, let singleMs, let singleChars, let streamMs, let streamChars,
                        let chunks, let cuts, let forced, let tailSent, let same, let prep, let net, let parse, let queued):
            func c(_ n: Int?) -> String { n.map { "\($0)" } ?? "FAILED" }
            func v(_ n: Int?) -> String { n.map { "\($0)" } ?? "-" }
            print("STREAM run=\(run) single_stop_to_text_ms=\(singleMs) single_chars=\(c(singleChars)) "
                  + "stream_stop_to_text_ms=\(streamMs) stream_chars=\(c(streamChars)) chunks=\(chunks) "
                  + "cuts_while_recording=\(cuts) forced=\(forced) tail_sent=\(tailSent) same_text=\(same) "
                  + "tail_prep_ms=\(v(prep)) tail_net_ms=\(v(net)) tail_parse_ms=\(v(parse)) tail_queued_ms=\(v(queued))")
        case .transcript(let n):
            print("TRANSCRIPT:\(n) characters (text withheld; shown only on screen in the app)")
        case .emptyTranscript:
            print("transcribe-selftest: 轉錄結果是空字串")
        case .remoteUnreachable:
            print("transcribe-selftest: \(Edition.transcriptionFailureMessage)")
        case .unexpectedFailure:
            print("transcribe-selftest: 轉錄失敗（非 MiniTranscriber 的已知訊息）")
        case .usage:
            print("用法：Talkiie --transcribe-selftest|--stream-selftest <16kHz mono wav> --egress-log-dir <dir>")
        case .unreadableFixture:
            print("transcribe-selftest: 讀不了 wav（必須是 16 kHz mono）")
        }
        fflush(stdout)
    }
}
#endif

#if DEBUG
enum InsertSelfTestLine {
    case help
    case usage
    case outcome(TranscriptDelivery.Outcome)

    static func emit(_ line: InsertSelfTestLine) {
        switch line {
        case .help:
            print("""
            用法（DEBUG build）：
              Talkiie --insert-selftest <text>     對目前焦點走一次 InsertionPolicy + Inserter；插入 exit 0，拒絕／中止 exit 1
                                                  （text 裡字面的 \\n 是段落分隔：一般 app 送 Shift+Return，終端機改空白）
              Talkiie --transcribe-selftest <wav> --egress-log-dir <dir>
              Talkiie --stream-selftest <wav> --egress-log-dir <dir> [--stream-selftest-runs N]
              Talkiie --hud-selftest [<存膠囊 PNG 的資料夾>] [--hud-selftest-hold <秒>]
              Talkiie --menubar-selftest
              Talkiie --settings-selftest [<存 PNG 的資料夾>]
              Talkiie --settings-snapshots <資料夾> [--tabs a,b] [--expand-examples] [--dictionary-sample]
              Talkiie --research-selftest [--research-selftest-badge-png <path>]
            """)
        case .usage:
            print("insert-selftest: 用法 Talkiie --insert-selftest <非空文字>")
        case .outcome(.inserted(let coverage)):
            print("insert-selftest: SENT（未驗證）raceGuard=\(coverage == .enforced ? "enforced" : "unverified")")
        case .outcome(.refused(let reason)):
            print("insert-selftest: REFUSED \(String(describing: reason)) —— \(reason.message)")
        case .outcome(.aborted(let sentUnits, let reason)):
            print("insert-selftest: ABORTED \(String(describing: reason)) partial=\(sentUnits > 0) —— \(reason.text)")
        case .outcome(.busy):
            print("insert-selftest: BUSY")
        }
        fflush(stdout)
    }
}
#endif

#if DEBUG
enum HUDSelfTestLine {
    case keysSkippedHotkeyUnavailable
    case clickSkippedNoAccessibility
    case clickSkippedScreenLocked
    case click(reachedButton: Bool, focusKept: Bool, sameField: Bool?)
    case passed

    static func emit(_ line: HUDSelfTestLine) {
        switch line {
        case .keysSkippedHotkeyUnavailable:
            print("hud-selftest: SKIP 錄音鍵註冊檢查（熱鍵沒註冊成功，可能另一個 Talkiie 正在跑）")
        case .clickSkippedNoAccessibility:
            print("hud-selftest: SKIP 真的點擊 ✓（這個 Talkiie 沒有輔助使用權限，無法合成點擊）")
        case .clickSkippedScreenLocked:
            print("hud-selftest: SKIP 真的點擊 ✓（螢幕鎖定中，點擊到不了任何 app）")
        case .click(let reached, let kept, let same):
            let field = same.map { $0 ? "yes" : "no" } ?? "n/a（點擊前沒有焦點欄位）"
            print("hud-selftest: click ✓ reachedButton=\(reached) focusKept=\(kept) sameField=\(field)")
        case .passed:
            print("hud-selftest: PASS（聆聽／思考／成功／取消／結束／中斷）")
        }
        fflush(stdout)
    }
}
#endif

#if DEBUG
enum FallbackSelfTestLine {
    case passed(shortHeight: Int, longHeight: Int)
    case failed(check: Int)

    static func emit(_ line: FallbackSelfTestLine) {
        switch line {
        case .passed(let short, let long):
            print("fallback-selftest: PASS（救援面板：短句 \(short) 高、長句 \(long) 高、不搶焦點、Esc 關閉並清掉文字）")
        case .failed(let check):
            print("fallback-selftest: FAIL 檢查 \(check)（見 App/FallbackPanel.swift 的 FallbackSelfTest）")
        }
        fflush(stdout)
    }
}

enum ListToggleSelfTestLine {
    case passed(heights: [Int])
    case failed(check: Int)

    static func emit(_ line: ListToggleSelfTestLine) {
        switch line {
        case .passed(let heights):
            let h = heights.map(String.init).joined(separator: "/")
            print("list-toggle-selftest: PASS（切換項目編號面板：移除／改成／處理中／放棄 四種狀態 \(h) 高、不搶焦點、收得起來）")
        case .failed(let check):
            print("list-toggle-selftest: FAIL 檢查 \(check)（見 App/ListTogglePanel.swift 的 ListToggleSelfTest）")
        }
        fflush(stdout)
    }
}

enum MenuBarSelfTestLine {
    case passed(frames: Int)
    case failed(check: Int)

    static func emit(_ line: MenuBarSelfTestLine) {
        switch line {
        case .passed(let frames):
            print("menubar-selftest: PASS（\(frames) 格輪播；待命／錄音／處理中／成功／失敗／取消／空結果／減少動態效果）")
        case .failed(let check):
            print("menubar-selftest: FAIL 檢查 \(check)（見 App/TalkiieApp.swift 的 MenuBarSelfTest）")
        }
        fflush(stdout)
    }
}
#endif

#if DEBUG
enum ThemeShotsLine {
    case done(themes: Int)
    case auroraDone

    static func emit(_ line: ThemeShotsLine) {
        switch line {
        case .done(let n): print("theme-shots: 已輸出 \(n) 種佈景")
        case .auroraDone: print("aurora-shots: 已輸出樣本")
        }
        fflush(stdout)
    }
}

enum SettingsSelfTestLine {
    case pane(tab: Int, width: Int, height: Int)
    case passed(tabs: Int)
    case failed(tab: Int, width: Int, height: Int)
    case consentMissing(index: Int)
    case plusVisible(tab: Int, term: Int)
    case textWalkBlind(tab: Int, rows: Int, screens: Int)

    static func emit(_ line: SettingsSelfTestLine) {
        switch line {
        case .pane(let tab, let w, let h):
            print("settings-selftest: 第 \(tab + 1) 頁 \(w)×\(h)")
        case .passed(let tabs):
            print("settings-selftest: PASS（\(tabs) 頁都排得出來）")
        case .failed(let tab, let w, let h):
            print("settings-selftest: FAIL 第 \(tab + 1) 頁 \(w)×\(h)（見 App/SettingsWindow.swift 的 SettingsSelfTest）")
        case .consentMissing(let index):
            print("settings-selftest: FAIL 同意頁少了第 \(index + 1) 項必要揭露（exit 42，見 App/SettingsWindow.swift 的 ConsentDisclosureCheck）")
        case .plusVisible(let tab, let term):
            if tab < 0 {
                print("settings-selftest: FAIL \(term == 1 ? "佈景" : "提示音")清單列出了鎖著的付費選項（exit 43，見 PlusVisibilityCheck）")
            } else {
                print("settings-selftest: FAIL 第 \(tab + 1) 頁出現 Talkiie Plus 的第 \(term + 1) 個禁用字眼（exit 43，見 PlusVisibilityCheck）")
            }
        case .textWalkBlind(let tab, let rows, let screens):
            let t = SettingsTab.allCases.indices.contains(tab) ? SettingsTab.allCases[tab] : nil
            let sentinel = t.flatMap(PlusVisibilityCheck.sentinel(for:)) ?? "?"
            print("settings-selftest: FAIL 第 \(tab + 1) 頁（\(t?.rawValue ?? "?")）讀不到哨兵字眼「\(sentinel)」："
                  + "讀到 \(rows) 行、往下捲了 \(screens) 屏（exit 44，斷言失敗：環境已確認正常——螢幕沒鎖、在 GUI session。"
                  + "常見原因：頁面變高、哨兵在捲不到的地方，或哨兵字眼改了）")
        }
        fflush(stdout)
    }
}

enum SelfTestEnvironmentLine {
    enum Test: String {
        case settings = "settings-selftest"
        case onboarding = "onboarding-selftest"
        case fallback = "fallback-selftest"
    }

    static func emit(test: Test, blocker: SelfTestEnvironment.Blocker, during: Bool) {
        let why: String
        switch blocker {
        case .noGUISession: why = "拿不到 GUI session（ssh／daemon 起的行程，沒有 window server）"
        case .notOnConsole: why = "這個 session 不在螢幕前（別的使用者在前景）"
        case .screenLocked: why = "螢幕鎖定中"
        }
        print("\(test.rawValue): ENVIRONMENT \(why)\(during ? "（斷言失敗時才發現：跑到一半被鎖）" : "")"
              + "——exit \(SelfTestEnvironment.exitCode)：這台機器現在跑不了，**不是通過**；解鎖（螢幕共享）或在有 GUI 的 session 重跑")
        fflush(stdout)
    }
}

enum SettingsSnapshotsLine {
    case usage
    case saved(count: Int)

    static func emit(_ line: SettingsSnapshotsLine) {
        switch line {
        case .usage:
            print("settings-snapshots: 用法 Talkiie --settings-snapshots <資料夾> [--tabs a,b] [--expand-examples] [--dictionary-sample]")
        case .saved(let count):
            print("settings-snapshots: 存了 \(count) 張")
        }
        fflush(stdout)
    }
}
#endif

#if DEBUG
enum OnboardingSelfTestLine {
    case passed(checks: Int, shots: Int)
    case failed(check: Int)

    static func emit(_ line: OnboardingSelfTestLine) {
        switch line {
        case .passed(let checks, let shots):
            print("onboarding-selftest: PASS（\(checks) 項：沒同意打不開／新安裝完整導覽／老用戶只跳一次／選單進度／功能提示／功能地圖；\(shots) 張截圖）")
        case .failed(let check):
            print("onboarding-selftest: FAIL 檢查 \(check)（見 App/OnboardingSelfTest.swift；exit \(50 + check)）")
        }
        fflush(stdout)
    }
}
#endif

#if DEBUG && RESEARCH_CAPTURE
enum ResearchSelfTestLine {
    case passed(checks: Int, redPixels: Int)
    case failed(check: Int)

    static func emit(_ line: ResearchSelfTestLine) {
        switch line {
        case .passed(let checks, let red):
            print("research-selftest: PASS（\(checks) 項：關著零寫入／取消不存／WAV 與 round.json／權限／失敗照存／180 天保留／全部刪除／膠囊 REC 標示 \(red) 紅點／真的資料夾未被碰）")
        case .failed(let check):
            print("research-selftest: FAIL 檢查 \(check)（見 App/ResearchCapture.swift 的 ResearchSelfTest）")
        }
        fflush(stdout)
    }
}
#endif

enum FocusStage: String, Sendable {
    case freeze, freezeRetry, warmup, preInsert, preInsertRetry, reinsert, selftest
}
