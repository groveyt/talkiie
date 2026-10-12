import AppKit
import ApplicationServices
import AVFoundation
import NaturalInputCore

enum Permissions {

    static func microphoneStatus() -> PermissionGuidance.Microphone {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .notDetermined
        }
    }

    static func accessibilityTrusted() -> Bool { AXIsProcessTrusted() }

    static func requestMicrophone(completion: @escaping @Sendable (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    static func promptAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    enum Pane { case microphone, accessibility }

    static func openSettings(_ pane: Pane) {
        let anchor = pane == .microphone ? "Privacy_Microphone" : "Privacy_Accessibility"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
