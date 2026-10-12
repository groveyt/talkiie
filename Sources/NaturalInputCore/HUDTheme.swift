import Foundation
import TalkiieOrb

public struct HUDPalette: Equatable, Sendable {
    public struct RGBA: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var opacity: Double

        public init(red: Double, green: Double, blue: Double, opacity: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.opacity = opacity
        }

        public static func white(_ w: Double, opacity: Double) -> RGBA { RGBA(red: w, green: w, blue: w, opacity: opacity) }
    }

    public var background: RGBA
    public var stroke: RGBA
    public var shadow: RGBA
    public var text: RGBA
    public var secondaryText: RGBA

    public init(background: RGBA, stroke: RGBA, shadow: RGBA, text: RGBA, secondaryText: RGBA) {
        self.background = background
        self.stroke = stroke
        self.shadow = shadow
        self.text = text
        self.secondaryText = secondaryText
    }

    public static let classic = HUDPalette(
        background: .white(0.09, opacity: 0.94),
        stroke: .white(1, opacity: 0.10),
        shadow: RGBA(red: 0, green: 0, blue: 0, opacity: 0.35),
        text: .white(1, opacity: 0.92),
        secondaryText: .white(1, opacity: 0.6))
}

public enum HUDTheme: String, CaseIterable, Sendable, Identifiable {
    case classic
    case aurora
    case auroraCool
    case glass

    public var id: String { rawValue }

    public var requiresPlus: Bool { self != .classic }

    public static func pickerOptions(unlocked: Bool, offersPlus: Bool) -> [HUDTheme] {
        allCases.filter { !$0.requiresPlus || unlocked || offersPlus }
    }

    public var usesAuroraOrb: Bool { self == .aurora || self == .auroraCool }

    public var auroraPalette: AuroraPalette { self == .auroraCool ? .cool : .warm }

    public var usesGlassSurface: Bool { self == .glass }

    public var palette: HUDPalette {
        switch self {
        case .classic, .aurora, .auroraCool, .glass: return .classic
        }
    }

    public static let defaultsKey = "hudTheme"
    public static let defaultValue = HUDTheme.classic

    public static func effective(stored: String?, unlocked: Bool) -> HUDTheme {
        guard let stored, let theme = HUDTheme(rawValue: stored) else { return .classic }
        if theme.requiresPlus && !unlocked { return .classic }
        return theme
    }
}
