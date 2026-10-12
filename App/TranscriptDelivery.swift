import Foundation
import NaturalInputCore

enum TranscriptDelivery {

    enum Outcome: Equatable, Sendable {
        case inserted(RaceGuardCoverage)
        case refused(InsertionPolicy.Refusal)
        case aborted(sentUnits: Int, reason: InsertionAbortReason)
        case busy
    }

    static func paragraphs(_ text: String) -> [String] {
        text.components(separatedBy: TranscriptionOutcome.paragraphSeparator)
    }

    static func freezeTarget(stage: FocusStage = .freeze) -> FrozenTarget? {
        let inspector = LiveFocusInspector()
        let (first, source) = enablingAccessibility(inspector.lookupFocus(), inspector: inspector, stage: stage)
        let snapshot = settled(first.snapshot, inspector: inspector, retryStage: .freezeRetry)
        logFocus(snapshot.map(FocusLookup.found) ?? first, stage: stage, frozen: nil, source: source)
        return snapshot.map(FrozenTarget.init)
    }

    private static func settled(_ first: FocusSnapshot?, inspector: LiveFocusInspector,
                                retryStage: FocusStage) -> FocusSnapshot? {
        var snapshot = first
        if let initial = snapshot, FreezeRetryPolicy.shouldRetry(initial) {
            for _ in 0..<FreezeRetryPolicy.maxRetries {
                if let snapshot { logFocus(snapshot, stage: retryStage, frozen: nil, source: nil) }
                usleep(80_000)
                guard let next = inspector.currentFocus() else { break }
                let within = next.pid == initial.pid && inspector.isElement(next.element, within: initial.element)
                switch FreezeRetryPolicy.evaluate(initial: initial, next: next, nextIsWithinInitial: within) {
                case .acceptAndStop: snapshot = next
                case .acceptAndContinue: snapshot = next; continue
                case .rejectKeepInitial: snapshot = initial
                }
                break
            }
        }
        return snapshot
    }

    static func warmUpFocus() {
        Task.detached(priority: .utility) {
            let inspector = LiveFocusInspector()
            let (lookup, source) = enablingAccessibility(inspector.lookupFocus(), inspector: inspector, stage: .warmup)
            logFocus(lookup, stage: .warmup, frozen: nil, source: source)
        }
    }

    private static func enablingAccessibility(_ first: FocusLookup, inspector: LiveFocusInspector,
                                              stage: FocusStage) -> (FocusLookup, FocusSource) {
        let (lookup, report) = inspector.enableAccessibilityIfNeeded(after: first)
        guard let report else { return (first, .systemWide) }
        Log.record(.accessibilityEnablement(stage, report))
        return (lookup, report.settled ? .afterEnable : .systemWide)
    }

    static func logFocus(_ lookup: FocusLookup, stage: FocusStage, frozen: FrozenTarget?, source: FocusSource?) {
        switch lookup {
        case .found(let s): logFocus(s, stage: stage, frozen: frozen, source: source)
        case .missing(let miss, let micros): Log.record(.focusMissing(stage, miss, micros: micros))
        }
    }

    static func logFocus(_ s: FocusSnapshot, stage: FocusStage, frozen: FrozenTarget?, source: FocusSource?) {
        let same: Bool? = frozen.map { $0.pid == s.pid && $0.element == s.element }
        Log.record(.focusObserved(stage: stage, diagnostics: s.diagnostics, editability: s.editability,
                                  marked: s.markedText, secureField: s.isSecureField, sameAsFrozen: same,
                                  source: source))
    }

    final class Marks: @unchecked Sendable {
        private let lock = NSLock()
        private var _started: UInt64?
        private var _firstKeystroke: UInt64?
        private var _done: UInt64?

        func markStarted() { set(\._started) }
        func markKeystroke() { set(\._firstKeystroke) }
        func markDone() { set(\._done) }

        var started: UInt64? { lock.lock(); defer { lock.unlock() }; return _started }
        var firstKeystroke: UInt64? { lock.lock(); defer { lock.unlock() }; return _firstKeystroke }
        var done: UInt64? { lock.lock(); defer { lock.unlock() }; return _done }

        private func set(_ key: ReferenceWritableKeyPath<Marks, UInt64?>) {
            let now = LatencyTimeline.now()
            lock.lock(); defer { lock.unlock() }
            if self[keyPath: key] == nil { self[keyPath: key] = now }
        }
    }

    struct MarkingPoster: KeyEventPosting {
        let base: KeyEventPosting
        let marks: Marks?

        func post(utf16 units: [UInt16]) -> Bool {
            let ok = base.post(utf16: units)
            if ok { marks?.markKeystroke() }
            return ok
        }

        func postShiftReturn() -> Bool {
            let ok = base.postShiftReturn()
            if ok { marks?.markKeystroke() }
            return ok
        }
    }

    final class Trace: @unchecked Sendable {
        private let lock = NSLock()
        private var _record: InsertionRecord?
        var record: InsertionRecord? { lock.lock(); defer { lock.unlock() }; return _record }
        fileprivate func set(_ r: InsertionRecord?) { lock.lock(); _record = r; lock.unlock() }
    }

    final class SpotBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _spot: InsertionSpot<FocusedElementIdentity>?
        var spot: InsertionSpot<FocusedElementIdentity>? { lock.lock(); defer { lock.unlock() }; return _spot }
        fileprivate func set(_ s: InsertionSpot<FocusedElementIdentity>?) { lock.lock(); _spot = s; lock.unlock() }
    }

    private final class BaselineFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var _start: Int? = nil
        var correctedStart: Int? { lock.lock(); defer { lock.unlock() }; return _start }
        func set(_ start: Int) { lock.lock(); _start = start; lock.unlock() }
    }

    static func deliver(_ text: String, to target: FrozenTarget?, marks: Marks? = nil,
                        trace: Trace? = nil, spot: SpotBox? = nil) async -> Outcome {
        await Task.detached(priority: .userInitiated) {
            let inspector = LiveFocusInspector()
            let trusted = inspector.accessibilityTrusted()
            let lookup: FocusLookup = trusted ? inspector.lookupFocus() : .missing(.notTrusted, micros: 0)
            let source = FocusSource.systemWide
            var state = InsertionPolicy.State(accessibilityTrusted: trusted,
                                              systemSecureInputEnabled: inspector.systemSecureInputEnabled(),
                                              focus: lookup.snapshot,
                                              frozenTarget: target)
            if InsertionPolicy.targetRule == .currentFocus, let first = state.focus, FreezeRetryPolicy.shouldRetry(first) {
                state = InsertionPolicy.State(accessibilityTrusted: state.accessibilityTrusted,
                                              systemSecureInputEnabled: inspector.systemSecureInputEnabled(),
                                              focus: settled(first, inspector: inspector, retryStage: .preInsertRetry),
                                              frozenTarget: target)
            }
            logFocus(state.focus.map(FocusLookup.found) ?? lookup, stage: .preInsert, frozen: target, source: source)
            let into: FrozenTarget
            switch InsertionPolicy.resolve(state) {
            case .refuse(let reason): return Outcome.refused(reason)
            case .insert(let t): into = t
            }
            let stats = ProbeStats()
            let pacing = InsertionWarmUpLedger.shared.pacing(pid: into.pid)
            Log.record(.insertionPacing(pacing))
            let baseline = BaselineFlag()
            let inserter = Inserter(poster: MarkingPoster(base: CGEventKeyPoster(), marks: marks),
                                    probe: LiveInsertionProbe(inspector: inspector, stats: stats),
                                    interChunkDelayMs: pacing.interChunkDelayMs,
                                    chunkUnits: pacing.chunkUnits,
                                    onCursorSettle: { Log.record(.cursorSettle($0)) },
                                    onPacingSwitched: { afterChunk, settleBudgetMs in
                                        Log.record(.insertionPacingSwitched(afterChunk: afterChunk,
                                                                            settleBudgetMs: settleBudgetMs))
                                    },
                                    onBaselineCorrected: { baseline.set(0); Log.record(.insertionBaselineCorrected(stale: $0)) },
                                    onBaselineRebased: { stale, corrected in
                                        baseline.set(corrected)
                                        Log.record(.insertionBaselineRebased(stale: stale, corrected: corrected))
                                    })
            let startedAt = DispatchTime.now().uptimeNanoseconds
            let paragraphs = Self.paragraphs(text)
            let containerText = state.focus?.diagnostics?.descendantRole == .textArea ? "AXTextArea" : nil
            let separator = ParagraphBreakPolicy.separator(forBundleID: into.bundleID, focusedRole: state.focus?.role,
                                                           containerTextRole: containerText)
            Log.record(.insertionShape(paragraphs: paragraphs.count, shiftReturn: separator == .shiftReturn))
            marks?.markStarted()
            let result = inserter.insert(paragraphs: paragraphs, separator: separator,
                                         into: FocusIdentity(pid: into.pid, element: into.element))
            marks?.markDone()
            Log.record(.insertionStats(probes: stats.count,
                                       totalMillis: Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000),
                                       maxProbeMicros: stats.maxMicros))
            switch result {
            case .sent(_, let coverage):
                InsertionWarmUpLedger.shared.noteCleanRound(pid: into.pid)
                if let trace, let focus = state.focus, let start = baseline.correctedStart ?? focus.selectionLocation {
                    trace.set(InsertionRecord(pid: into.pid, element: into.element,
                                              textElement: focus.textElement ?? focus.element, role: focus.role,
                                              app: KnownApp(bundleID: into.bundleID), startUTF16: start,
                                              insertedText: InsertionRecord.typedText(paragraphs: paragraphs,
                                                                                      separator: separator),
                                              insertedAt: Date()))
                }
                if let spot, ListToggle.offers(separator: separator), let read = state.focus?.selectionLocation {
                    spot.set(InsertionSpot(target: FocusIdentity(pid: into.pid, element: into.element),
                                           start: baseline.correctedStart ?? read,
                                           typedText: InsertionRecord.typedText(paragraphs: paragraphs,
                                                                                separator: separator)))
                }
                return Outcome.inserted(coverage)
            case .aborted(let sentUnits, let reason):
                return Outcome.aborted(sentUnits: sentUnits, reason: reason)
            }
        }.value
    }
}

extension TranscriptDelivery {
    static func listToggleStillAtEnd(_ spot: InsertionSpot<FocusedElementIdentity>) async -> ListToggleAbortReason? {
        await Task.detached(priority: .utility) {
            let inspector = LiveFocusInspector()
            guard inspector.accessibilityTrusted() else { return .focusChanged }
            let probe = LiveInsertionProbe(inspector: inspector)
            return ListToggleReplacer(keys: CGEventKeyPoster(), probe: probe).stillAtEnd(spot)
        }.value
    }

    static func replaceForListToggle(_ spot: InsertionSpot<FocusedElementIdentity>,
                                     with text: String) async -> ListToggleResult {
        await Task.detached(priority: .userInitiated) {
            let inspector = LiveFocusInspector()
            guard inspector.accessibilityTrusted() else {
                return .aborted(.focusChanged, collapsedSelection: false, typedUnits: 0)
            }
            let probe = LiveInsertionProbe(inspector: inspector)
            let pacing = InsertionWarmUpLedger.shared.pacing(pid: spot.target.pid)
            let inserter = Inserter(poster: CGEventKeyPoster(), probe: probe,
                                    interChunkDelayMs: pacing.interChunkDelayMs, chunkUnits: pacing.chunkUnits,
                                    onCursorSettle: { Log.record(.cursorSettle($0)) })
            let replacer = ListToggleReplacer(keys: CGEventKeyPoster(), probe: probe)
            return replacer.replace(spot) {
                inserter.insert(paragraphs: paragraphs(text), separator: .shiftReturn, into: spot.target)
            }
        }.value
    }
}

struct LiveInsertionProbe: SelectionProbing {
    let inspector: LiveFocusInspector
    var stats: ProbeStats? = nil

    func isSecureInputEnabled() -> Bool { inspector.systemSecureInputEnabled() }

    func currentFocus() -> FocusIdentity<FocusedElementIdentity>? {
        observe().map { FocusIdentity(pid: $0.pid, element: $0.element) }
    }

    func cursorLocation() -> Int? { observe()?.selectionLocation }

    func selectedRange() -> SelectionRange? {
        guard let s = observe(), let location = s.selectionLocation, let length = s.selectionLength else { return nil }
        return SelectionRange(location: location, length: length)
    }

    private func observe() -> FocusSnapshot? {
        let s = inspector.currentFocus()
        if let micros = s?.diagnostics?.lookupMicros { stats?.add(micros) }
        return s
    }
}

final class ProbeStats: @unchecked Sendable {
    private(set) var count = 0
    private(set) var maxMicros = 0
    func add(_ micros: Int) { count += 1; maxMicros = max(maxMicros, micros) }
}
