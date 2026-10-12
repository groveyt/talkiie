import Foundation

public protocol KeyEventPosting {
    func post(utf16 units: [UInt16]) -> Bool
    func postShiftReturn() -> Bool
}

public struct FocusIdentity<Element: Equatable>: Equatable {
    public let pid: Int32
    public let element: Element
    public init(pid: Int32, element: Element) {
        self.pid = pid
        self.element = element
    }
}

extension FocusIdentity: Sendable where Element: Sendable {}

public protocol InsertionProbing {
    associatedtype Element: Equatable
    func isSecureInputEnabled() -> Bool
    func currentFocus() -> FocusIdentity<Element>?
    func cursorLocation() -> Int?
}

public enum InsertionResult: Equatable, Sendable {
    case sent(units: Int, raceGuard: RaceGuardCoverage)
    case aborted(sentUnits: Int, reason: InsertionAbortReason)
}

public enum RaceGuardCoverage: Equatable, Sendable {
    case enforced
    case unverified
}

public enum InsertionAbortReason: Equatable, Sendable {
    case secureInput
    case focusAppChanged
    case focusElementChanged
    case cursorMoved
    case postFailed

    public var text: String {
        switch self {
        case .secureInput:         return "插入途中 Secure Input 被開啟，已停止"
        case .focusAppChanged:     return "插入途中切換到別的 app，已停止"
        case .focusElementChanged: return "插入途中游標換到別的輸入框，已停止"
        case .cursorMoved:         return "插入途中游標位置跟預期不符（可能有人同時打字，或 app 漏收了字），已停止"
        case .postFailed:          return "無法送出按鍵事件，已停止"
        }
    }
}

public struct Inserter<Probe: InsertionProbing> {
    public static var defaultInterChunkDelayMs: Int { 12 }

    let poster: KeyEventPosting
    let probe: Probe
    let interChunkDelayMs: Int
    let chunkUnits: Int
    let settlePolls: Int
    let settleDelayMs: Int
    let onCursorSettle: ((CursorSettleReport) -> Void)?
    let onPacingSwitched: ((Int, Int) -> Void)?
    let onBaselineCorrected: ((Int) -> Void)?
    let onBaselineRebased: ((Int, Int) -> Void)?
    let sleep: (Int) -> Void

    public init(poster: KeyEventPosting,
                probe: Probe,
                interChunkDelayMs: Int = Inserter.defaultInterChunkDelayMs,
                chunkUnits: Int = UnicodeChunker.defaultMaxUnits,
                settlePolls: Int = CursorSettle.maxPolls,
                settleDelayMs: Int = CursorSettle.pollDelayMs,
                onCursorSettle: ((CursorSettleReport) -> Void)? = nil,
                onPacingSwitched: ((Int, Int) -> Void)? = nil,
                onBaselineCorrected: ((Int) -> Void)? = nil,
                onBaselineRebased: ((Int, Int) -> Void)? = nil,
                sleep: @escaping (Int) -> Void = { ms in usleep(useconds_t(max(0, ms)) * 1000) }) {
        self.poster = poster
        self.probe = probe
        self.interChunkDelayMs = interChunkDelayMs
        self.chunkUnits = chunkUnits
        self.settlePolls = settlePolls
        self.settleDelayMs = settleDelayMs
        self.onCursorSettle = onCursorSettle
        self.onPacingSwitched = onPacingSwitched
        self.onBaselineCorrected = onBaselineCorrected
        self.onBaselineRebased = onBaselineRebased
        self.sleep = sleep
    }

    public func insert(_ text: String, into target: FocusIdentity<Probe.Element>) -> InsertionResult {
        let chunks = UnicodeChunker.chunks(InsertionText.sanitized(text), maxUnits: chunkUnits)
        return run(chunks.map(Step.text), into: target)
    }

    public func insert(paragraphs: [String], separator: ParagraphSeparator,
                       into target: FocusIdentity<Probe.Element>) -> InsertionResult {
        let cleaned = InsertionText.paragraphs(paragraphs)
        switch separator {
        case .space:
            return insert(cleaned.joined(separator: " "), into: target)
        case .shiftReturn:
            var steps: [Step] = []
            for (i, paragraph) in cleaned.enumerated() {
                if i > 0 { steps.append(.shiftReturn) }
                steps += UnicodeChunker.chunks(paragraph, maxUnits: chunkUnits).map(Step.text)
            }
            return run(steps, into: target)
        }
    }

    private enum Step {
        case text([UInt16])
        case shiftReturn

        var units: Int {
            switch self {
            case .text(let u): return u.count
            case .shiftReturn: return 1
            }
        }
    }

    private func run(_ steps: [Step], into target: FocusIdentity<Probe.Element>) -> InsertionResult {
        var sent = 0
        var coverage = RaceGuardCoverage.enforced
        var start: Int? = nil
        var lastChunkUnits = 0
        var breakSlack = 0
        var lastWasBreak = false
        var roundPacing = RoundPacingState()
        var baselineUnconfirmed = false
        var guardCheckedOnce = false

        for (index, step) in steps.enumerated() {
            if index > 0 { sleep(roundPacing.interChunkDelayMs(base: interChunkDelayMs)) }

            if probe.isSecureInputEnabled() {
                return .aborted(sentUnits: sent, reason: .secureInput)
            }
            guard let focus = probe.currentFocus(), focus.pid == target.pid else {
                return .aborted(sentUnits: sent, reason: .focusAppChanged)
            }
            guard focus.element == target.element else {
                return .aborted(sentUnits: sent, reason: .focusElementChanged)
            }

            let settlePollsNow = roundPacing.settlePolls(base: settlePolls)
            let (check, firstOffset, wasLagging) = checkCursor(start: start, sent: sent, lastChunkUnits: lastChunkUnits,
                                                     slack: breakSlack, confirmSlack: !lastWasBreak,
                                                     settlePolls: settlePollsNow)
            let wasUnconfirmed = baselineUnconfirmed
            if start != nil { baselineUnconfirmed = false }
            let isFirstGuardCheck = start != nil && !guardCheckedOnce
            if start != nil { guardCheckedOnce = true }
            switch check {
            case .unreadable:
                coverage = .unverified
            case .ok(let location):
                if wasLagging, roundPacing.noteLag() {
                    onPacingSwitched?(index, roundPacing.settlePolls(base: settlePolls) * settleDelayMs)
                }
                if let s = start, breakSlack > 0, !lastWasBreak {
                    start = s + (location - (s + sent))
                    breakSlack = 0
                }
                if start == nil {
                    if index == 0 {
                        start = location
                        baselineUnconfirmed = location > 0
                    } else {
                        coverage = .unverified
                        start = settledCursor(from: location).map { $0 - sent }
                    }
                }
            case .moved(let last):
                if wasUnconfirmed, let s = start, s > 0, last == sent,
                   settledCursor(from: last) == sent {
                    start = 0
                    onBaselineCorrected?(s)
                    break
                }
                if isFirstGuardCheck, let s = start, firstOffset == -lastChunkUnits,
                   let settled = settledCursor(from: last), settled == last, settled - sent >= 0 {
                    start = settled - sent
                    onBaselineRebased?(s, settled - sent)
                    break
                }
                return .aborted(sentUnits: sent, reason: .cursorMoved)
            }

            switch step {
            case .text(let chunk):
                guard poster.post(utf16: chunk) else {
                    return .aborted(sentUnits: sent, reason: .postFailed)
                }
            case .shiftReturn:
                guard poster.postShiftReturn() else {
                    return .aborted(sentUnits: sent, reason: .postFailed)
                }
            }
            sent += step.units
            lastChunkUnits = step.units
            if case .shiftReturn = step {
                if start != nil { breakSlack = (lastWasBreak ? breakSlack : 0) + CursorSettle.breakSlack }
                lastWasBreak = true
            } else {
                lastWasBreak = false
            }
        }
        return .sent(units: sent, raceGuard: coverage)
    }

    private enum CursorCheck { case ok(Int), unreadable, moved(Int) }

    private func settledCursor(from first: Int) -> Int? {
        var location = first
        for _ in 0..<max(1, settlePolls) {
            sleep(settleDelayMs)
            guard let again = probe.cursorLocation() else { return nil }
            if again == location { return location }
            location = again
        }
        return nil
    }

    private func checkCursor(start: Int?, sent: Int, lastChunkUnits: Int,
                             slack: Int = 0, confirmSlack: Bool = false,
                             settlePolls: Int) -> (CursorCheck, firstOffset: Int, wasLagging: Bool) {
        guard var location = probe.cursorLocation() else { return (.unreadable, 0, false) }
        guard let start else { return (.ok(location), 0, false) }
        let expected = start + sent
        let firstOffset = location - expected
        var polls = 0
        var verdict = CursorSettle.verdict(location: location, expected: expected,
                                           lastStepUnits: lastChunkUnits, slack: slack)
        let wasLagging = verdict == .lagging
        let budget = wasLagging ? max(settlePolls, CursorSettle.extendedMaxPolls) : settlePolls
        var previous: Int? = nil
        while polls < budget,
              verdict == .lagging
                || (confirmSlack && slack > 0 && verdict == .match && location != expected && previous != location) {
            previous = location
            sleep(settleDelayMs)
            polls += 1
            guard let again = probe.cursorLocation() else {
                onCursorSettle?(CursorSettleReport(polls: polls, firstOffset: firstOffset, finalOffset: nil))
                return (.unreadable, firstOffset, wasLagging)
            }
            location = again
            verdict = CursorSettle.verdict(location: location, expected: expected,
                                           lastStepUnits: lastChunkUnits, slack: slack)
        }
        if confirmSlack, slack > 0, verdict == .match, location != expected, previous != location {
            verdict = .elsewhere
        }
        if firstOffset != 0 {
            onCursorSettle?(CursorSettleReport(polls: polls, firstOffset: firstOffset, finalOffset: location - expected,
                                               withinBreakSlack: verdict == .match && location != expected))
        }
        return (verdict == .match ? .ok(location) : .moved(location), firstOffset, wasLagging)
    }
}

public enum CursorSettle {
    public static let pollDelayMs = 50
    public static let maxPolls = 4
    public static let extendedMaxPolls = 10

    public enum Verdict: Equatable, Sendable {
        case match
        case lagging
        case elsewhere
    }

    public static let breakSlack = 1

    public static func verdict(location: Int, expected: Int, lastStepUnits: Int, slack: Int = 0) -> Verdict {
        if location <= expected, location >= expected - slack { return .match }
        if location >= expected - slack - lastStepUnits, location < expected - slack { return .lagging }
        return .elsewhere
    }
}

public struct CursorSettleReport: Equatable, Sendable {
    public let polls: Int
    public let firstOffset: Int
    public let finalOffset: Int?
    public let withinBreakSlack: Bool

    public init(polls: Int, firstOffset: Int, finalOffset: Int?, withinBreakSlack: Bool = false) {
        self.polls = polls
        self.firstOffset = firstOffset
        self.finalOffset = finalOffset
        self.withinBreakSlack = withinBreakSlack
    }

    public var caughtUp: Bool { finalOffset == 0 }
}
