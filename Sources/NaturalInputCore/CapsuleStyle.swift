import Foundation

public enum CapsuleStyle: String, Equatable, Sendable, CaseIterable {
    case full
    case minimal

    public static let defaultsKey = "capsuleStyle"
    public static let defaultValue = CapsuleStyle.full

    public static func resolve(stored: String?) -> CapsuleStyle {
        guard let stored, let value = CapsuleStyle(rawValue: stored) else { return .full }
        return value
    }

    public var title: String {
        switch self {
        case .full: return "完整"
        case .minimal: return "精簡"
        }
    }

    public var detail: String {
        switch self {
        case .full: return "錄音時 ✕／✓ 一直看得到。"
        case .minimal: return "精簡：錄音時只有中間的球，滑鼠移上去才出現取消／完成。"
        }
    }

    public func showsButtons(listening: Bool, hovering: Bool) -> Bool {
        guard listening else { return false }
        switch self {
        case .full: return true
        case .minimal: return hovering
        }
    }
}
