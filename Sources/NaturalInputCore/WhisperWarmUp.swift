import Foundation

public enum WhisperWarmUpPolicy {
    public static let idleThreshold: TimeInterval = 180
    public static let silenceSamples = 8_000
    public static func silence() -> [Float] { [Float](repeating: 0, count: silenceSamples) }

    public static func shouldFire(offered: Bool, allowsCapture: Bool, idle: TimeInterval?, inFlight: Bool) -> Bool {
        guard offered, allowsCapture, !inFlight else { return false }
        guard let idle else { return true }
        return idle >= idleThreshold
    }
}

public struct WhisperWarmUpReport: Equatable, Sendable {
    public let idleSeconds: Int?
    public let latencyMillis: Int
    public let ok: Bool
    public init(idleSeconds: Int?, latencyMillis: Int, ok: Bool) {
        self.idleSeconds = idleSeconds; self.latencyMillis = latencyMillis; self.ok = ok
    }
}

public final class WhisperWarmUpLedger: @unchecked Sendable {
    private let lock = NSLock()
    private let clock: @Sendable () -> TimeInterval
    private var lastRequestAt: TimeInterval?
    private var inFlight = false

    public init(clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    public func noteRequest() {
        lock.lock(); defer { lock.unlock() }
        lastRequestAt = clock()
    }

    public func claim(offered: Bool, allowsCapture: Bool) -> Claim? {
        lock.lock(); defer { lock.unlock() }
        let now = clock()
        let idle = lastRequestAt.map { max(0, now - $0) }
        guard WhisperWarmUpPolicy.shouldFire(offered: offered, allowsCapture: allowsCapture,
                                             idle: idle, inFlight: inFlight) else { return nil }
        inFlight = true
        lastRequestAt = now
        return Claim(idleSeconds: idle.map { Int($0) })
    }

    public func release() {
        lock.lock(); defer { lock.unlock() }
        inFlight = false
        lastRequestAt = clock()
    }

    public struct Claim: Equatable, Sendable { public let idleSeconds: Int? }
}

public final class WhisperWarmer: @unchecked Sendable {
    private let ledger: WhisperWarmUpLedger
    private let send: @Sendable () async -> Bool
    private let report: @Sendable (WhisperWarmUpReport) -> Void

    public init(ledger: WhisperWarmUpLedger,
                send: @escaping @Sendable () async -> Bool,
                report: @escaping @Sendable (WhisperWarmUpReport) -> Void) {
        self.ledger = ledger; self.send = send; self.report = report
    }

    @discardableResult
    public func pressed(allowsCapture: Bool) -> Task<Void, Never>? {
        guard let claim = ledger.claim(offered: true, allowsCapture: allowsCapture) else { return nil }
        let send = self.send, ledger = self.ledger, report = self.report
        return Task.detached(priority: .utility) {
            let clock = ContinuousClock()
            let start = clock.now
            let ok = await send()
            let d = clock.now - start
            let ms = Int(d.components.seconds * 1_000 + d.components.attoseconds / 1_000_000_000_000_000)
            ledger.release()
            report(WhisperWarmUpReport(idleSeconds: claim.idleSeconds, latencyMillis: ms, ok: ok))
        }
    }
}
