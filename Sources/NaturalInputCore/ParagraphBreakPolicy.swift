import Foundation

public enum ParagraphSeparator: Equatable, Sendable {
    case shiftReturn
    case space
}

public enum ParagraphBreakPolicy {
    static let knownTerminalBundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "io.alacritty",
        "dev.warp.warp-stable",
        "dev.warp.warp",
        "co.zeit.hyper",
        "org.tabby",
        "com.microsoft.vscode",
        "com.microsoft.vscodeinsiders",
        "com.todesktop.230313mzl4w4u92",
        "dev.zed.zed",
    ]

    public static func separator(forBundleID bundleID: String?, focusedRole: String?) -> ParagraphSeparator {
        separator(forBundleID: bundleID, focusedRole: focusedRole, containerTextRole: nil)
    }

    public static func separator(forBundleID bundleID: String?, focusedRole: String?,
                                 containerTextRole: String?) -> ParagraphSeparator {
        let isContainer = focusedRole == "AXGroup" || focusedRole == "AXWebArea"
        let effectiveRole = isContainer ? containerTextRole : focusedRole
        guard effectiveRole == "AXTextArea" else { return .space }
        return separator(forBundleID: bundleID)
    }

    public static func separator(forBundleID bundleID: String?) -> ParagraphSeparator {
        switch KnownApp(bundleID: bundleID) {
        case .terminal, .iTerm:
            return .space
        default:
            break
        }
        guard let id = bundleID?.lowercased() else { return .shiftReturn }
        if id.contains("terminal") || id.hasSuffix("term") || knownTerminalBundleIDs.contains(id) {
            return .space
        }
        return .shiftReturn
    }
}
