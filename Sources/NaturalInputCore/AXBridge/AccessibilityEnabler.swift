#if os(macOS)
import AppKit
import ApplicationServices

public enum AccessibilityEnabler {

    static func axName(_ attribute: AccessibilityEnablement.Attribute) -> String {
        switch attribute {
        case .manualAccessibility: return "AXManualAccessibility"
        case .enhancedUserInterface: return "AXEnhancedUserInterface"
        }
    }

    public static func enable(_ attribute: AccessibilityEnablement.Attribute, pid: Int32) -> Int32 {
        guard pid > 0, AXIsProcessTrusted() else { return AXError.apiDisabled.rawValue }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, LiveFocusInspector.messagingTimeoutSeconds)
        let name = axName(attribute) as CFString
        return AXUIElementSetAttributeValue(app, name, kCFBooleanTrue).rawValue
    }
}

public struct LiveAccessibilityEnablementEnvironment: AccessibilityEnablementEnvironment {
    let inspector: LiveFocusInspector
    let ownPID: Int32

    public init(inspector: LiveFocusInspector = LiveFocusInspector(),
                ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.inspector = inspector
        self.ownPID = ownPID
    }

    public func lookup() -> FocusLookup { inspector.lookupFocus() }

    public func frontmostPID() -> Int32? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid > 0, pid != ownPID else { return nil }
        return pid
    }

    public func knownApp(pid: Int32) -> KnownApp {
        KnownApp(bundleID: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier)
    }

    public func isElectronApp(pid: Int32) -> Bool {
        guard let url = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Resources/app.asar").path)
    }

    public func enable(_ attribute: AccessibilityEnablement.Attribute, pid: Int32) -> Int32 {
        guard pid != ownPID else { return AXError.illegalArgument.rawValue }
        return AccessibilityEnabler.enable(attribute, pid: pid)
    }

    public func isElement(_ element: FocusedElementIdentity, within container: FocusedElementIdentity) -> Bool {
        inspector.isElement(element, within: container)
    }

    public func sleep(millis: Int) { usleep(useconds_t(millis * 1_000)) }
}

extension LiveFocusInspector {
    public func enableAccessibilityIfNeeded(
        after first: FocusLookup, ledger: AccessibilityEnablementLedger = .shared,
        warmUp: InsertionWarmUpLedger = .shared
    ) -> (lookup: FocusLookup, report: AccessibilityEnablement.Report?) {
        AccessibilityEnablement.enableIfNeeded(after: first, LiveAccessibilityEnablementEnvironment(inspector: self),
                                               ledger: ledger, warmUp: warmUp)
    }
}
#endif
