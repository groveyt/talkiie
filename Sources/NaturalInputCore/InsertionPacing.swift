import Foundation

public struct InsertionPacing: Equatable, Sendable {
    public enum Reason: String, Sendable {
        case normal
        case axJustEnabled
    }

    public let chunkUnits: Int
    public let interChunkDelayMs: Int
    public let reason: Reason

    public static let normal = InsertionPacing(chunkUnits: UnicodeChunker.defaultMaxUnits,
                                               interChunkDelayMs: 12, reason: .normal)
    public static let gentle = InsertionPacing(chunkUnits: 8, interChunkDelayMs: 50, reason: .axJustEnabled)

    public static let warmUpMillis: UInt64 = 10_000

    public static func pacing(enabledAtMillis: UInt64?, nowMillis: UInt64) -> InsertionPacing {
        guard let at = enabledAtMillis, nowMillis >= at, nowMillis - at < warmUpMillis else { return .normal }
        return .gentle
    }

    public var logText: String {
        "insert pacing=\(reason == .normal ? "normal" : "gentle") reason=\(reason.rawValue) "
            + "chunk=\(chunkUnits) delay=\(interChunkDelayMs)ms"
    }
}

public struct RoundPacingState: Equatable, Sendable {
    public private(set) var laggedThisRound = false

    public init() {}

    @discardableResult
    public mutating func noteLag() -> Bool {
        guard !laggedThisRound else { return false }
        laggedThisRound = true
        return true
    }

    public func interChunkDelayMs(base: Int) -> Int {
        laggedThisRound ? max(base, InsertionPacing.gentle.interChunkDelayMs) : base
    }

    public func settlePolls(base: Int) -> Int {
        laggedThisRound ? max(base, CursorSettle.extendedMaxPolls) : base
    }
}

public final class InsertionWarmUpLedger: @unchecked Sendable {
    public static let shared = InsertionWarmUpLedger()

    private let lock = NSLock()
    private var enabledAt: [Int32: UInt64] = [:]
    private let clock: () -> UInt64

    public init(clock: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds / 1_000_000 }) {
        self.clock = clock
    }

    public func noteEnabled(pid: Int32) {
        let now = clock()
        lock.lock(); defer { lock.unlock() }
        enabledAt[pid] = now
    }

    public func noteCleanRound(pid: Int32) {
        lock.lock(); defer { lock.unlock() }
        enabledAt.removeValue(forKey: pid)
    }

    public func pacing(pid: Int32) -> InsertionPacing {
        let now = clock()
        lock.lock(); defer { lock.unlock() }
        return InsertionPacing.pacing(enabledAtMillis: enabledAt[pid], nowMillis: now)
    }
}
