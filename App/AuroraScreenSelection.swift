import AppKit
import NaturalInputCore

public enum AuroraScreenSource: String, Sendable {
    case targetWindow
    case mousePointer
    case mainScreen
}

@MainActor
enum AuroraScreenSelection {
    static func targetScreen(element: FocusedElementIdentity?, focusInspector: LiveFocusInspector) -> (NSScreen, AuroraScreenSource)? {
        nil
    }
}
