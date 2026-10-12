import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
enum FallbackPanel {
    enum Action: Sendable, Equatable {
        case copy
        case close
    }

    static var onAction: ((Action, String) -> Void)?

    static let title = "沒有插入"
    static let caption = "選單列 Talkiie →「最近口述」還找得到這段"
    static let copyHelp = "放進剪貼簿（剪貼簿管理器會看到這段文字）"
    static let bottomInset: CGFloat = 84

    private static let model = FallbackModel()
    private static var panel: FallbackNSPanel?

    static func show(text: String, reason: String?) {
        model.text = text
        model.reason = reason
        present()
    }

    static func close() {
        panel?.orderOut(nil)
        model.text = ""
        model.reason = nil
    }

    static var isShowing: Bool { panel?.isVisible == true && !model.text.isEmpty }

    private static func present() {
        let p = panel ?? makePanel()
        panel = p
        if p.contentView == nil || !(p.contentView is NSHostingView<FallbackView>) {
            let host = FirstMouseHostingView(rootView: FallbackView(model: model) { action in
                if action == .close { return FallbackPanel.close() }
                FallbackPanel.onAction?(action, FallbackPanel.model.text)
            })
            host.sizingOptions = []
            p.contentView = host
        }
        let size = measure()
        var frame = p.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        if let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            frame.origin = NSPoint(x: (vf.midX - frame.width / 2).rounded(), y: vf.minY + bottomInset)
        }
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
    }

    static func measure() -> NSSize {
        let c = NSHostingController(rootView: FallbackView(model: model) { _ in }.fixedSize(horizontal: false, vertical: true))
        let s = c.sizeThatFits(in: NSSize(width: FallbackView.width, height: 4000))
        return NSSize(width: FallbackView.width, height: ceil(s.height))
    }

    private static func makePanel() -> FallbackNSPanel {
        let p = FallbackNSPanel(contentRect: NSRect(x: 0, y: 0, width: FallbackView.width, height: 80),
                                styleMask: [.nonactivatingPanel, .borderless],
                                backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.onClose = { FallbackPanel.close() }
        return p
    }

    #if DEBUG
    static var debugPanel: NSPanel? { panel }
    static var debugText: String { model.text }
    static func debugPressEscape() -> Bool {
        guard let p = panel else { return false }
        p.makeKey()
        guard p.isKeyWindow,
              let esc = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: p.windowNumber, context: nil, characters: "\u{1b}",
                                         charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                         keyCode: FallbackNSPanel.escapeKeyCode) else { return false }
        p.sendEvent(esc)
        return true
    }
    #endif
}

final class FallbackNSPanel: NSPanel {
    static let escapeKeyCode: UInt16 = 53
    var onClose: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == Self.escapeKeyCode { onClose?(); return }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) { onClose?() }
}

@MainActor
final class FallbackModel: ObservableObject {
    @Published var text = ""
    @Published var reason: String?
}

struct FallbackView: View {
    @ObservedObject var model: FallbackModel
    let onAction: (FallbackPanel.Action) -> Void

    static let width: CGFloat = 360

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(FallbackPanel.title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HUDStyle.text)
                    .accessibilityHint(model.reason ?? "")
                if !model.text.isEmpty {
                    Text(model.text).font(.system(size: 13)).lineLimit(2)
                        .foregroundStyle(HUDStyle.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button("複製") { onAction(.copy) }
                        .help(FallbackPanel.copyHelp)
                }
                .controlSize(.small)
                Text(FallbackPanel.caption).font(.caption).foregroundStyle(HUDStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                onAction(.close)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.14), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("關閉（Esc）")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .hudRoundedStyle(cornerRadius: 18)
        .frame(width: Self.width, alignment: .leading)
    }
}

#if DEBUG
@MainActor
enum FallbackSelfTest {
    static let shortText = "這是救援面板的預覽文字。"
    static let longText = String(repeating: "這是一段很長的預覽文字，用來確認文字會被截成兩行而不是把面板撐到螢幕外。", count: 30)

    static func run() async {
        SelfTestEnvironment.exitIfUnusable(.fallback)
        let args = CommandLine.arguments
        var dir: URL?
        if let i = args.firstIndex(of: "--fallback-selftest"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
            dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        func fail(_ check: Int32) -> Never {
            SelfTestEnvironment.exitIfUnusable(.fallback, during: true)
            FallbackSelfTestLine.emit(.failed(check: Int(check))); exit(check)
        }

        let wasActive = NSApp.isActive
        FallbackPanel.show(text: shortText, reason: InsertionPolicy.Refusal.notEditable.message)
        await pause(0.4)
        guard let p = FallbackPanel.debugPanel, p.isVisible, FallbackPanel.debugText == shortText else {
            fail(50)
        }
        let short = p.contentRect(forFrameRect: p.frame).size
        guard short.width == FallbackView.width, short.height >= 40, short.height <= 200 else {
            fail(50)
        }
        guard !p.isKeyWindow, NSApp.isActive == wasActive else { fail(51) }
        guard save(p, "fallback-short.png", in: dir) else { fail(54) }

        FallbackPanel.show(text: longText, reason: InsertionPolicy.Refusal.noFocus.message)
        await pause(0.4)
        let long = p.contentRect(forFrameRect: p.frame).size
        guard long.height <= short.height + 20 else {
            fail(52)
        }
        guard save(p, "fallback-long.png", in: dir) else { fail(54) }

        guard FallbackPanel.debugPressEscape() else {
            fail(53)
        }
        await pause(0.2)
        guard !p.isVisible, FallbackPanel.debugText.isEmpty, !FallbackPanel.isShowing else {
            fail(53)
        }
        FallbackSelfTestLine.emit(.passed(shortHeight: Int(short.height), longHeight: Int(long.height)))
        exit(0)
    }

    private static func save(_ p: NSPanel, _ name: String, in dir: URL?) -> Bool {
        guard let dir else { return true }
        guard let view = p.contentView?.superview ?? p.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: png)
    }
}
#endif
