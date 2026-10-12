import AppKit
import SwiftUI
import NaturalInputCore

@MainActor
extension HUDStyle {
    static var glassText: Color { classicColor(HUDPalette.classic.text) }
    static var glassSecondaryText: Color { classicColor(HUDPalette.classic.secondaryText) }

    private static func classicColor(_ c: HUDPalette.RGBA) -> Color {
        Color(red: c.red, green: c.green, blue: c.blue, opacity: c.opacity)
    }
}

extension View {
    @MainActor func hudGlassStrokeAndShadow(in shape: some InsettableShape) -> some View {
        self
            .overlay(shape.strokeBorder(HUDStyle.stroke))
            .shadow(color: HUDStyle.shadowColor, radius: HUDStyle.shadowRadius, y: HUDStyle.shadowY)
    }
}

struct HUDGlassSurface<S: Shape>: View {
    let shape: S

    var body: some View {
        shape.fill(HUDStyle.background)
    }
}

@available(macOS 26, *)
struct HUDGlassButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button { action() } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.10), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

extension OrbNSView {
    static func glassBackgroundIsDark(appearance: NSAppearance?) -> Bool { true }
    static func applyGlassOrbShadow(_ cg: CGContext, dark: Bool) {}
}

#if DEBUG
extension HUDSelfTest {
    static func glassSurfaceBehaves(_ m: AppModel) async -> Bool { false }
}
#endif
