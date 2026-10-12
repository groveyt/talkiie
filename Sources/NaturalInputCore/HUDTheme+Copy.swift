import Foundation

extension HUDTheme {
    public var title: String { self == .classic ? "經典" : rawValue }

    public var detail: String { self == .classic ? "現在的點狀球，黑底膠囊。" : "" }
}
