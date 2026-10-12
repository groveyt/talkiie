import Foundation

public enum AccessibilityEnablement {

    public enum Attribute: String, CaseIterable, Sendable {
        case manualAccessibility
        case enhancedUserInterface
    }

    public enum Trigger: String, Sendable {
        case noFocus
        case containerWithoutText
    }

    public static let enhancedUserInterfaceForChromiumBrowsers = false
    public static let chromiumBrowsers: Set<KnownApp> = [.chrome, .arc]

    public static let settlePollMillis = 50
    public static let settleMaxPolls = 6

    public static func needsEnhancedFallback(trigger: Trigger, steps: [Step], app: KnownApp, isElectron: Bool) -> Bool {
        guard enhancedFallbackApps.contains(app), trigger == .noFocus, isElectron,
              !steps.contains(where: { $0.settled || $0.attribute == .enhancedUserInterface }) else { return false }
        return steps.contains { $0.attribute == .manualAccessibility && $0.axError == AXErrorCode.attributeUnsupported }
    }

    public static let enhancedFallbackApps: Set<KnownApp> = [.chatGPT]

    public static func trigger(for lookup: FocusLookup) -> Trigger? {
        switch lookup {
        case .missing(let miss, _):
            switch miss {
            case .notTrusted: return nil
            case .noFocusedElement, .noProcess, .roleUnreadable:
                if miss.isTimeout || miss.axError == AXErrorCode.apiDisabled { return nil }
                return .noFocus
            }
        case .found(let s):
            return FreezeRetryPolicy.shouldRetry(s) ? .containerWithoutText : nil
        }
    }

    public static func attributes(for app: KnownApp,
                                  allowEnhanced: Bool = enhancedUserInterfaceForChromiumBrowsers) -> [Attribute] {
        allowEnhanced && chromiumBrowsers.contains(app) ? [.manualAccessibility, .enhancedUserInterface]
                                                        : [.manualAccessibility]
    }

    public struct Step: Equatable, Sendable {
        public let attribute: Attribute
        public let axError: Int32
        public let polls: Int
        public let settled: Bool

        public init(attribute: Attribute, axError: Int32, polls: Int, settled: Bool) {
            self.attribute = attribute; self.axError = axError; self.polls = polls; self.settled = settled
        }
    }

    public enum Outcome: Equatable, Sendable {
        case noTargetApp
        case alreadyAttempted
        case attempted([Step])
    }

    public struct Report: Equatable, Sendable {
        public let trigger: Trigger
        public let app: KnownApp
        public let outcome: Outcome

        public var settled: Bool {
            if case .attempted(let steps) = outcome { return steps.contains { $0.settled } }
            return false
        }
    }

    public static func enableIfNeeded<E: AccessibilityEnablementEnvironment>(
        after first: FocusLookup, _ env: E, ledger: AccessibilityEnablementLedger,
        warmUp: InsertionWarmUpLedger? = nil,
        allowEnhanced: Bool = enhancedUserInterfaceForChromiumBrowsers
    ) -> (lookup: FocusLookup, report: Report?) {
        guard let reason = trigger(for: first) else {
            if let s = first.snapshot { ledger.noteFocusReady(pid: s.pid) }
            return (first, nil)
        }
        let container = first.snapshot
        guard let pid = container?.pid ?? env.frontmostPID() else {
            return (first, Report(trigger: reason, app: .none, outcome: .noTargetApp))
        }
        let app = env.knownApp(pid: pid)
        guard ledger.claim(pid: pid) else {
            return (first, Report(trigger: reason, app: app, outcome: .alreadyAttempted))
        }

        var steps: [Step] = []
        var result = first
        var plan = attributes(for: app, allowEnhanced: allowEnhanced)
        var index = 0
        attempts: while index < plan.count {
            let attribute = plan[index]
            index += 1
            let err = env.enable(attribute, pid: pid)
            var polls = 0
            var settled = false
            var movedAway = false
            if err == AXErrorCode.success
                || (attribute == .enhancedUserInterface && err == AXErrorCode.notImplemented) {
                warmUp?.noteEnabled(pid: pid)
                while polls < settleMaxPolls {
                    env.sleep(millis: settlePollMillis)
                    polls += 1
                    let next = env.lookup()
                    guard let s = next.snapshot else { continue }
                    guard s.pid == pid, container.map({ env.isElement(s.element, within: $0.element) }) ?? true else {
                        movedAway = true
                        break
                    }
                    result = next
                    if trigger(for: next) == nil { settled = true; break }
                }
            }
            steps.append(Step(attribute: attribute, axError: err, polls: polls, settled: settled))
            if settled { ledger.noteFocusReady(pid: pid) }
            if settled || movedAway { break attempts }
            if index == plan.count,
               needsEnhancedFallback(trigger: reason, steps: steps, app: app,
                                     isElectron: env.isElectronApp(pid: pid)) {
                plan.append(.enhancedUserInterface)
            }
        }
        return (result, Report(trigger: reason, app: app, outcome: .attempted(steps)))
    }
}

public protocol AccessibilityEnablementEnvironment {
    func lookup() -> FocusLookup
    func frontmostPID() -> Int32?
    func knownApp(pid: Int32) -> KnownApp
    func isElectronApp(pid: Int32) -> Bool
    func enable(_ attribute: AccessibilityEnablement.Attribute, pid: Int32) -> Int32
    func isElement(_ element: FocusedElementIdentity, within container: FocusedElementIdentity) -> Bool
    func sleep(millis: Int)
}

public final class AccessibilityEnablementLedger: @unchecked Sendable {
    public static let shared = AccessibilityEnablementLedger()

    private let lock = NSLock()
    private var attempted: Set<Int32> = []

    public init() {}

    public func claim(pid: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return attempted.insert(pid).inserted
    }

    public func noteFocusReady(pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        attempted.remove(pid)
    }
}

extension FocusLogText {
    public static func enablement(_ r: AccessibilityEnablement.Report) -> String {
        let head = "ax-enable trigger=\(r.trigger.rawValue) app=\(r.app.rawValue)"
        switch r.outcome {
        case .noTargetApp: return "\(head) skipped: no frontmost app"
        case .alreadyAttempted: return "\(head) skipped: already enabled for this process"
        case .attempted(let steps):
            let parts = steps.map { s in
                "\(s.attribute.rawValue) err=\(s.axError) (\(AXErrorCode.name(s.axError))) "
                    + "waited=\(s.polls * AccessibilityEnablement.settlePollMillis)ms settled=\(s.settled ? "yes" : "no")"
            }
            return "\(head) " + parts.joined(separator: " -> ")
        }
    }
}
