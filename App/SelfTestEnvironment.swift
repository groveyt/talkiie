#if DEBUG
import CoreGraphics
import Foundation

enum SelfTestEnvironment {
    static let exitCode: Int32 = 75

    enum Blocker: Int {
        case noGUISession = 1
        case notOnConsole = 2
        case screenLocked = 3
    }

    static func blocker() -> Blocker? {
        if let raw = ProcessInfo.processInfo.environment["TALKIIE_SELFTEST_FAKE_BLOCKER"],
           let n = Int(raw), let fake = Blocker(rawValue: n) {
            return fake
        }
        guard let s = CGSessionCopyCurrentDictionary() as? [String: Any] else { return .noGUISession }
        if (s["kCGSSessionOnConsoleKey"] as? Bool) == false { return .notOnConsole }
        if (s["CGSSessionScreenIsLocked"] as? Bool) == true { return .screenLocked }
        return nil
    }

    static func exitIfUnusable(_ test: SelfTestEnvironmentLine.Test, during: Bool = false) {
        guard let b = blocker() else { return }
        SelfTestEnvironmentLine.emit(test: test, blocker: b, during: during)
        exit(exitCode)
    }
}
#endif
