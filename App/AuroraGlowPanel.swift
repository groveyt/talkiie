import AppKit
import NaturalInputCore

final class AuroraGlowView: NSView {
    enum Kind: Equatable { case listening, transcribing }
    static let sinkSeconds = 0.0
}

@MainActor
final class AuroraGlowPanel {
    var isVisible: Bool { false }

    func show(kind: AuroraGlowView.Kind, levelProvider: @escaping () -> Double,
              palette: AuroraPalette = .warm, on screen: NSScreen) {}

    var debugAnimating: Bool { false }
    var debugDominantLobeX: Double? { nil }

    func flashSuccess() {}
    func sinkOut() {}
    func hide() {}
    func fadeOut(duration: Double) {}

    #if DEBUG
    var debugPanelFrame: NSRect? { nil }
    var debugIgnoresMouseEvents: Bool? { nil }
    var debugIsKeyOrMain: Bool { false }
    #endif
}

#if DEBUG
extension HUDSelfTest {
    static func auroraGlowBehaves(_ m: AppModel) async -> Bool { false }
}
#endif
