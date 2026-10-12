import Foundation

public enum PaidFeature: String, CaseIterable, Sendable {
    case themes
    case speed
}

public struct Entitlement: Equatable, Sendable {
    public static let locked = Entitlement()

    public func isUnlocked(_ feature: PaidFeature) -> Bool { false }
}
