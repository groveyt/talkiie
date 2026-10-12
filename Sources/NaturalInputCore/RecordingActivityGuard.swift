import Foundation

public protocol ActivityAsserting: AnyObject {
    func beginActivity(options: ProcessInfo.ActivityOptions, reason: String) -> NSObjectProtocol
    func endActivity(_ activity: NSObjectProtocol)
}

extension ProcessInfo: ActivityAsserting {}

public final class RecordingActivityGuard {
    public static let options: ProcessInfo.ActivityOptions =
        [.userInitiated, .idleDisplaySleepDisabled, .idleSystemSleepDisabled]
    public static let reason = "Talkiie dictation in progress"

    private let asserter: any ActivityAsserting
    private var token: NSObjectProtocol?

    public var isHeld: Bool { token != nil }

    public init(asserter: any ActivityAsserting = ProcessInfo.processInfo) {
        self.asserter = asserter
    }

    public func begin() {
        guard token == nil else { return }
        token = asserter.beginActivity(options: Self.options, reason: Self.reason)
    }

    public func end() {
        guard let token else { return }
        asserter.endActivity(token)
        self.token = nil
    }

    deinit { end() }
}
