import AppKit

@MainActor
enum NoticesWindow {
    private static var window: NSWindow?
    private static let closer = Closer()

    static func loadText() -> String {
        guard let path = Bundle.main.path(forResource: "THIRD_PARTY_NOTICES", ofType: "md"),
              let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return "這個 build 裡找不到授權聲明檔（Contents/Resources/THIRD_PARTY_NOTICES.md）。"
        }
        return text
    }

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let size = NSSize(width: 720, height: 560)
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(origin: .zero, size: size)
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
            text.textContainerInset = NSSize(width: 12, height: 12)
            text.string = loadText()
            text.setAccessibilityLabel("第三方授權聲明")
        }
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable],
                         backing: .buffered, defer: false)
        w.title = "授權與致謝"
        w.contentView = scroll
        w.minSize = NSSize(width: 420, height: 300)
        w.isReleasedWhenClosed = false
        w.delegate = closer
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ n: Notification) {
            MainActor.assumeIsolated { NoticesWindow.window = nil }
        }
    }
}
