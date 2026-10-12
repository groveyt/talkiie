import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
enum ConsentStore {
    static var acceptedVersion: Int? {
        #if DEBUG
        if let override = debugOverride { return override }
        #endif
        return UserDefaults.standard.object(forKey: ConsentGate.defaultsKey) as? Int
    }

    static var allowsCapture: Bool { ConsentGate.allowsCapture(acceptedVersion: acceptedVersion, current: Edition.consentVersion) }

    static var hasEverConsented: Bool { ConsentGate.hasEverAccepted(acceptedVersion: acceptedVersion) }

    static func accept() {
        UserDefaults.standard.set(Edition.consentVersion, forKey: ConsentGate.defaultsKey)
    }

    #if DEBUG
    static var debugOverride: Int?? = nil
    #endif
}

@MainActor
final class ConsentWindow: NSObject {
    static let shared = ConsentWindow()

    var onAccepted: (() -> Void)?
    private var window: NSWindow?

    #if DEBUG
    static var debugSuppressWindow = false
    private(set) var debugRequests = 0
    #endif

    func presentIfNeeded() {
        guard !ConsentStore.allowsCapture else { return }
        #if DEBUG
        debugRequests += 1
        if Self.debugSuppressWindow { return }
        #endif
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 420),
                             styleMask: [.titled], backing: .buffered, defer: false)
            w.title = "Talkiie"
            w.isReleasedWhenClosed = false
            w.level = .floating
            w.contentView = NSHostingView(rootView: ConsentView(
                accept: { [weak self] in self?.accept() },
                quit: { NSApp.terminate(nil) }))
            w.setContentSize(w.contentView?.fittingSize ?? NSSize(width: 480, height: 420))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func accept() {
        ConsentStore.accept()
        Log.record(.consentAccepted(version: Edition.consentVersion))
        window?.orderOut(nil)
        window = nil
        onAccepted?()
    }
}

struct ConsentView: View {
    let accept: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(Edition.Copy.title).font(.title2).bold()
            ForEach(Array(Edition.Copy.points(hotkey: AppModel.hotkeyStartPhrase).enumerated()), id: \.offset) { _, point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                    Text(point).fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack {
                Spacer()
                Button(Edition.Copy.quitButton, action: quit)
                Button(Edition.Copy.acceptButton, action: accept)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 480)
    }
}
