public struct FnTapDetector: Sendable {

    public static let maxHoldSeconds: Double = 0.5

    public static let passiveEventTypes: Set<UInt> = [
        2,
        4,
        5,
        8,
        9,
        11,
        13,
        15,
        16,
        17,
        26,
    ]

    public static func interrupts(eventType: UInt) -> Bool { !passiveEventTypes.contains(eventType) }

    public enum Input: Equatable, Sendable {
        case modifiers(fn: Bool, others: Bool, at: Double)
        case otherInput
    }

    private var downAt: Double?
    private var interrupted = false

    public init() {}

    public var isFnHeld: Bool { downAt != nil }

    public mutating func handle(_ input: Input) -> Bool {
        switch input {
        case .otherInput:
            if downAt != nil { interrupted = true }
            return false
        case .modifiers(let fn, let others, let at):
            if fn {
                if let _ = downAt {
                    if others { interrupted = true }
                } else if !others {
                    downAt = at
                    interrupted = false
                }
                return false
            }
            guard let start = downAt else { return false }
            defer { downAt = nil; interrupted = false }
            return !interrupted && !others && at - start <= Self.maxHoldSeconds
        }
    }
}
