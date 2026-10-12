import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
enum ListTogglePanel {
    enum Action: Equatable { case toggle, copyAlternate, close }

    static var onAction: ((Action) -> Void)?

    static func failureMessage(_ reason: ListToggleAbortReason) -> String {
        switch reason {
        case .cursorMoved, .focusChanged:
            return "游標動過了，沒有換"
        case .typingAborted:
            return "換到一半停了"
        case .secureInput:
            return "Secure Input 開著，沒有換"
        case .selectionMismatch, .cursorUnreadable, .postFailed:
            return "這個 app 選不到剛插的字，沒有換"
        }
    }
    static let failureCaption = "另一個版本在「最近口述」"

    private static let model = ListToggleModel()
    private static var panel: ListToggleNSPanel?

    static func showOffer(_ kind: ListToggleKind) {
        model.kind = kind
        model.state = .offer
        present()
    }

    static func showWorking() {
        model.state = .working
        present()
    }

    static func showFailed(_ reason: ListToggleAbortReason) {
        model.state = .failed(reason)
        present()
    }

    static func close() {
        panel?.orderOut(nil)
        model.state = .offer
    }

    static var isShowing: Bool { panel?.isVisible == true }

    static let offsetFromCenter: CGFloat = 44
    static let bottomInset: CGFloat = 12

    private static func present() {
        let p = panel ?? makePanel()
        panel = p
        if !(p.contentView is NSHostingView<ListToggleView>) {
            let host = FirstMouseHostingView(rootView: ListToggleView(model: model) { ListTogglePanel.onAction?($0) })
            host.sizingOptions = []
            p.contentView = host
        }
        let size = measure()
        var frame = p.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        if let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let x = min(vf.midX + offsetFromCenter, vf.maxX - frame.width - 8)
            frame.origin = NSPoint(x: x.rounded(), y: vf.minY + bottomInset)
        }
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
    }

    static func measure() -> NSSize {
        let c = NSHostingController(rootView: ListToggleView(model: model) { _ in }.fixedSize())
        let s = c.sizeThatFits(in: NSSize(width: 4000, height: 4000))
        return NSSize(width: ceil(s.width), height: ceil(s.height))
    }

    private static func makePanel() -> ListToggleNSPanel {
        let p = ListToggleNSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
                                  styleMask: [.nonactivatingPanel, .borderless],
                                  backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.level = .statusBar
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        return p
    }

    #if DEBUG
    static var debugPanel: NSPanel? { panel }
    static var debugState: ListToggleModel.State { model.state }
    #endif
}

final class ListToggleNSPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ListToggleModel: ObservableObject {
    enum State: Equatable { case offer, working, failed(ListToggleAbortReason) }
    @Published var kind: ListToggleKind = .remove
    @Published var state: State = .offer
}

struct ListToggleView: View {
    @ObservedObject var model: ListToggleModel
    let onAction: (ListTogglePanel.Action) -> Void

    var body: some View {
        HStack(spacing: 8) {
            switch model.state {
            case .offer:
                Image(systemName: model.kind == .remove ? "list.number" : "text.alignleft")
                    .foregroundStyle(HUDStyle.secondaryText)
                Text(model.kind.caption).font(.system(size: 13)).foregroundStyle(HUDStyle.text)
                Button(model.kind.buttonTitle) { onAction(.toggle) }
                    .controlSize(.small)
                    .help(model.kind == .remove ? "把剛插的條列換成一般段落" : "把剛插的這段換成條列")
            case .working:
                ProgressView().controlSize(.small)
                Text(model.kind == .remove ? "移除項目編號中…" : "加入項目編號中…")
                    .font(.system(size: 13)).foregroundStyle(HUDStyle.text)
            case .failed(let reason):
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ListTogglePanel.failureMessage(reason)).font(.system(size: 13)).foregroundStyle(HUDStyle.text)
                    Text(ListTogglePanel.failureCaption).font(.caption).foregroundStyle(HUDStyle.secondaryText)
                }
                Button("複製另一個版本") { onAction(.copyAlternate) }
                    .controlSize(.small)
                    .help("放進剪貼簿（剪貼簿管理器會看到這段文字）")
            }
            if model.state != .working {
                Button { onAction(.close) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(HUDStyle.secondaryText)
                        .frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.14), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("關閉")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 40)
        .padding(.vertical, model.state == .offer ? 0 : 4)
        .hudCapsuleStyle()
    }
}

@MainActor
final class ListToggleController {
    static let shared = ListToggleController()

    private struct Current {
        let kind: ListToggleKind
        let alternate: String
        let spot: InsertionSpot<FocusedElementIdentity>
    }

    private var current: Current?
    private var monitor: Task<Void, Never>?
    private var generation = 0

    static let pollSeconds: Double = 0.3
    static let initialSettleTries = 3

    func offer(kind: ListToggleKind, alternate: String, spot: InsertionSpot<FocusedElementIdentity>?) {
        dismiss(nil)
        guard let spot else {
            Log.record(.listToggle(.notShown(kind, reason: nil)))
            return
        }
        generation += 1
        let gen = generation
        Task {
            var reason = await TranscriptDelivery.listToggleStillAtEnd(spot)
            for _ in 0..<Self.initialSettleTries where reason == .cursorMoved {
                try? await Task.sleep(for: .seconds(0.1))
                guard gen == self.generation else { return }
                reason = await TranscriptDelivery.listToggleStillAtEnd(spot)
            }
            if let reason {
                Log.record(.listToggle(.notShown(kind, reason: reason)))
                return
            }
            guard gen == self.generation, AppModel.shared.phase == .idle else { return }
            self.current = Current(kind: kind, alternate: alternate, spot: spot)
            ListTogglePanel.onAction = { [weak self] in self?.handle($0) }
            ListTogglePanel.showOffer(kind)
            Log.record(.listToggle(.shown(kind)))
            self.watch(gen)
        }
    }

    func newRoundStarted() {
        guard current != nil || ListTogglePanel.isShowing else { return }
        dismiss(.newRound)
    }

    private func watch(_ gen: Int) {
        monitor?.cancel()
        monitor = Task { [weak self] in
            let deadline = Date().addingTimeInterval(ListToggle.visibleSeconds)
            while Date() < deadline {
                try? await Task.sleep(for: .seconds(Self.pollSeconds))
                guard !Task.isCancelled, let self, gen == self.generation, let c = self.current else { return }
                if await TranscriptDelivery.listToggleStillAtEnd(c.spot) != nil {
                    guard gen == self.generation, !Task.isCancelled else { return }
                    return self.dismiss(.moved)
                }
            }
            guard !Task.isCancelled, let self, gen == self.generation else { return }
            self.dismiss(.timeout)
        }
    }

    private func dismiss(_ why: ListToggleLogEvent.Hidden?) {
        monitor?.cancel(); monitor = nil
        if let why, let c = current { Log.record(.listToggle(.hidden(c.kind, why))) }
        current = nil
        generation += 1
        ListTogglePanel.close()
    }

    private func handle(_ action: ListTogglePanel.Action) {
        switch action {
        case .close:
            dismiss(.closed)
        case .copyAlternate:
            if let c = current {
                Clipboard.copy(c.alternate)
                Log.record(.listToggle(.copied(c.kind)))
            }
            dismiss(nil)
        case .toggle:
            guard let c = current else { return dismiss(nil) }
            monitor?.cancel(); monitor = nil
            generation += 1
            let gen = generation
            ListTogglePanel.showWorking()
            Task {
                let result = await AppModel.shared.replaceForListToggle(c.spot, with: c.alternate)
                guard gen == self.generation else { return }
                switch result {
                case .replaced(let units):
                    Log.record(.listToggle(.replaced(c.kind, units: units)))
                    self.current = nil
                    ListTogglePanel.close()
                case .aborted(let reason, let collapsed, let typed):
                    Log.record(.listToggle(.aborted(c.kind, reason, collapsed: collapsed, typedUnits: typed)))
                    ListTogglePanel.showFailed(reason)
                    self.monitor = Task { [weak self] in
                        try? await Task.sleep(for: .seconds(ListToggle.visibleSeconds))
                        guard !Task.isCancelled, let self, gen == self.generation else { return }
                        self.dismiss(.timeout)
                    }
                }
            }
        }
    }
}

#if DEBUG
@MainActor
enum ListToggleSelfTest {
    static func run() async {
        let args = CommandLine.arguments
        var dir: URL?
        if let i = args.firstIndex(of: "--list-toggle-selftest"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
            dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        func pause(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        func fail(_ check: Int) -> Never { ListToggleSelfTestLine.emit(.failed(check: check)); exit(Int32(check)) }

        let wasActive = NSApp.isActive
        var heights: [Int] = []
        let shots: [(String, () -> Void)] = [
            ("list-toggle-remove.png", { ListTogglePanel.showOffer(.remove) }),
            ("list-toggle-apply.png", { ListTogglePanel.showOffer(.apply) }),
            ("list-toggle-working.png", { ListTogglePanel.showWorking() }),
            ("list-toggle-failed.png", { ListTogglePanel.showFailed(.selectionMismatch) }),
        ]
        for (name, show) in shots {
            show()
            await pause(0.3)
            guard let p = ListTogglePanel.debugPanel, p.isVisible else { fail(60) }
            let size = p.contentRect(forFrameRect: p.frame).size
            guard size.width >= 80, size.width <= 520, size.height >= 30, size.height <= 90 else { fail(60) }
            guard !p.isKeyWindow, !p.isMainWindow, !p.canBecomeKey, NSApp.isActive == wasActive else { fail(61) }
            p.makeKey()
            await pause(0.05)
            guard !p.isKeyWindow, NSApp.isActive == wasActive else { fail(61) }
            heights.append(Int(size.height))
            if name == "list-toggle-failed.png" {
                guard case .failed = ListTogglePanel.debugState else { fail(62) }
            }
            guard save(p, name, in: dir) else { fail(64) }
        }
        ListTogglePanel.close()
        await pause(0.2)
        guard ListTogglePanel.debugPanel?.isVisible != true, !ListTogglePanel.isShowing else { fail(63) }
        ListToggleSelfTestLine.emit(.passed(heights: heights))
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
