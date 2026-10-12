import AppKit
import SwiftUI

enum StatsPalette {
    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        })
    }

    static let heroStart = dynamic(light: 0x0A5BD8, dark: 0x0A5CCB)
    static let heroEnd = dynamic(light: 0x4B3FC4, dark: 0x4A44C0)
    static var heroGradient: LinearGradient {
        LinearGradient(colors: [heroStart, heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static let onHero = Color.white
    static let onHeroSecondary = Color.white.opacity(0.9)
    static let heroChip = Color.white.opacity(0.18)
    static let heroSegmentSelectedText = heroStart

    static let bar = dynamic(light: 0x4F8DEB, dark: 0x5B9BF0)
    static let barToday = dynamic(light: 0x4B3FC4, dark: 0xA29BFF)

    static let heatLevels: [Color] = [
        dynamic(light: 0xE5E7EB, dark: 0x2C2C30),
        dynamic(light: 0xC6DBFA, dark: 0x1E3A66),
        dynamic(light: 0x8FB8F5, dark: 0x2A5BA8),
        dynamic(light: 0x4F8DEB, dark: 0x3F85DE),
        dynamic(light: 0x1D5FD6, dark: 0x7DB6FF),
    ]

    static func heat(level: Int) -> Color { heatLevels[max(0, min(heatLevels.count - 1, level))] }

    static let shareBackground = dynamic(light: 0xFFFFFF, dark: 0x1E1E1E)
}
