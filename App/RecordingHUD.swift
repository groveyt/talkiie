import AppKit
import SwiftUI
import NaturalInputCore

@MainActor
enum RecordingHUD {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?
    private static var generation = 0

    static let capsule = CapsuleModel()
    private static var capsuleHost: NSView?

    private static let glow = AuroraGlowPanel()
    private static var glowScreen: NSScreen?
    private static let focusInspector = LiveFocusInspector()

    static var onButton: ((CapsuleButton) -> Void)?
    static var onDeliveryAction: ((DeliveryAction, String) -> Void)?

    static let successHoldSeconds: Double = 0.9

    static func showRecording(since: Date, caption: String? = nil) {
        presentCapsule(.listening, caption: caption)
    }

    static func showSending(notice: String?, transmitting: Bool) {
        presentCapsule(.thinking(transmitting: transmitting), caption: notice)
    }

    static func showDelivery(_ outcome: TranscriptDelivery.Outcome, text: String) {
        let content = DeliveryContent(outcome)
        if content.succeeded {
            presentCapsule(.success, caption: nil)
            if HUDStyle.theme.usesAuroraOrb, glow.isVisible, !showingCapsule, !Motion.reduceMotion {
                glow.sinkOut()
                let gen = generation
                hideTask = Task {
                    try? await Task.sleep(for: .seconds(AuroraGlowView.sinkSeconds + 0.03))
                    if !Task.isCancelled, generation == gen { hide() }
                }
                return
            }
            if HUDStyle.theme.usesAuroraOrb, glow.isVisible { glow.flashSuccess() }
            scheduleHide(after: successHoldSeconds)
            return
        }
        present(AnyView(DeliveryPill(content: content, text: text) { action in
            hide()
            onDeliveryAction?(action, text)
        }), acceptsClicks: !text.isEmpty)
        scheduleHide(after: text.isEmpty ? 7 : min(20, 12 + Double(text.count) / 12))
    }

    static func sendingTitle(transmitting: Bool) -> String {
        transmitting ? "轉錄中…" : "準備送出…"
    }

    static func showNotice(_ message: String, seconds: Double = 5) {
        present(AnyView(NoticePill(message: message)))
        scheduleHide(after: seconds)
    }

    private static func scheduleHide(after seconds: Double) {
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { fadeOut() }
        }
    }

    private static func fadeOut() {
        let hasCapsule = panel?.isVisible == true
        let hasGlow = glow.isVisible
        guard hasCapsule || hasGlow else { return }
        guard !Motion.reduceMotion else { return hide() }
        let gen = generation
        if hasCapsule, let p = panel {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Motion.fast
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().alphaValue = 0
            }
        }
        if hasGlow { glow.fadeOut(duration: Motion.fast) }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(Motion.fast + 0.03))
            if !Task.isCancelled, generation == gen { hide() }
        }
    }

    static func hide() {
        hideTask?.cancel(); hideTask = nil
        capsule.dismiss()
        generation += 1
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        glow.hide()
        glowScreen = nil
    }

    static var showingCapsule: Bool { panel?.contentView === capsuleHost && capsuleHost != nil }

    #if DEBUG
    static var glowVisible: Bool { glow.isVisible }
    static var glowIgnoresMouseEvents: Bool? { glow.debugIgnoresMouseEvents }
    static var glowIsKeyOrMain: Bool { glow.debugIsKeyOrMain }
    static var glowFrame: NSRect? { glow.debugPanelFrame }
    static var glowAnimating: Bool { glow.debugAnimating }
    static var glowDominantLobeX: Double? { glow.debugDominantLobeX }
    static var isVisible: Bool { panel?.isVisible == true && (panel?.alphaValue ?? 0) > 0 }
    static var panelIsKey: Bool { panel?.isKeyWindow == true }
    static func buttonCenterCG(_ b: CapsuleButton) -> CGPoint? {
        guard let p = panel, showingCapsule, let screen = NSScreen.screens.first else { return nil }
        let f = p.frame
        guard capsule.caption == nil else { return nil }
        let capsuleWidth = f.width - 16
        let left = f.midX - capsuleWidth / 2
        let x = b == .cancel ? left + 8 + 14 : left + capsuleWidth - 8 - 14
        let y = f.minY + 8 + CapsuleView.height / 2
        return CGPoint(x: x, y: screen.frame.maxY - y)
    }
    #endif

    private static func presentCapsule(_ mode: CapsuleModel.Mode, caption: String?) {
        if HUDStyle.theme.usesAuroraOrb, caption == nil {
            capsule.set(mode: mode, caption: nil)
            presentGlow(mode)
            return
        }
        glow.hide()
        glowScreen = nil
        let wasCapsule = panel?.contentView === capsuleHost && capsuleHost != nil && panel?.isVisible == true
        capsule.set(mode: mode, caption: caption)
        let host = capsuleHost ?? {
            let h = FirstMouseHostingView(rootView: CapsuleView(model: capsule) { b in
                RecordingHUD.onButton?(b)
            }.fixedSize())
            h.sizingOptions = []
            capsuleHost = h
            return h
        }()
        show(host, size: measure(CapsuleView(model: capsule) { _ in }), keepVisibleState: wasCapsule)
    }

    private static func presentGlow(_ mode: CapsuleModel.Mode) {
        hideTask?.cancel(); hideTask = nil
        generation += 1
        panel?.orderOut(nil); panel?.alphaValue = 1
        if glowScreen == nil {
            let element = focusInspector.currentFocus()?.element
            if let (screen, source) = AuroraScreenSelection.targetScreen(element: element, focusInspector: focusInspector) {
                glowScreen = screen
                Log.record(.auroraGlowScreen(source: source, width: Int(screen.frame.width), height: Int(screen.frame.height)))
            }
        }
        guard let screen = glowScreen else { return }
        let kind: AuroraGlowView.Kind
        let levelProvider: () -> Double
        switch mode {
        case .listening:
            kind = .listening
            levelProvider = { RecordingHUD.capsule.orbLevel }
        case .thinking(let transmitting):
            kind = transmitting ? .transcribing : .listening
            levelProvider = { 0 }
        case .success:
            kind = .transcribing
            levelProvider = { 0 }
        }
        glow.show(kind: kind, levelProvider: levelProvider, palette: HUDStyle.theme.auroraPalette, on: screen)
    }

    static func resizeForCapsule() {
        guard let host = capsuleHost, showingCapsule else { return }
        show(host, size: measure(CapsuleView(model: capsule) { _ in }), keepVisibleState: true)
    }

    private static func measure<V: View>(_ view: V) -> NSSize {
        let c = NSHostingController(rootView: view.fixedSize())
        let s = c.sizeThatFits(in: NSSize(width: 4000, height: 4000))
        return NSSize(width: ceil(s.width), height: ceil(s.height))
    }

    private static func present(_ view: AnyView, acceptsClicks: Bool = false) {
        capsule.dismiss()
        glow.hide()
        glowScreen = nil
        let host = FirstMouseHostingView(rootView: view.fixedSize())
        host.sizingOptions = []
        show(host, size: measure(view), keepVisibleState: false, acceptsClicks: acceptsClicks)
    }

    private static func show(_ host: NSView, size: NSSize, keepVisibleState: Bool, acceptsClicks: Bool = false) {
        hideTask?.cancel(); hideTask = nil
        generation += 1
        let p = panel ?? makePanel()
        panel = p
        if p.contentView !== host { p.contentView = host }
        if let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            let origin = NSPoint(x: (vf.midX - size.width / 2).rounded(), y: vf.minY + 12)
            let frame = NSRect(origin: origin, size: size)
            if p.frame != frame {
                if keepVisibleState && p.isVisible && !Motion.reduceMotion {
                    NSAnimationContext.runAnimationGroup { ctx in
                        ctx.duration = Motion.medium
                        ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        p.animator().setFrame(frame, display: true)
                    }
                } else {
                    p.setFrame(frame, display: true)
                }
            }
        } else if p.frame.size != size {
            p.setContentSize(size)
        }
        p.ignoresMouseEvents = host !== capsuleHost && !acceptsClicks
        p.alphaValue = 1
        if !keepVisibleState || !p.isVisible { p.orderFrontRegardless() }
        Log.record(.hudPresent(width: Int(size.width), height: Int(size.height)))
    }

    private static func makePanel() -> NSPanel {
        let p = CapsulePanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
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
        p.acceptsMouseMovedEvents = true
        return p
    }
}

struct NoticePill: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.system(size: 13)).foregroundStyle(HUDStyle.text)
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .hudCapsuleStyle()
    }
}

struct DeliveryContent: Equatable {
    let succeeded: Bool
    let title: String
    let detail: String?
    let caption: String
    let canReinsert: Bool

    static let recoveryHint = "之後也可以在選單列 Talkiie →「最近口述」找到這段"
    static let unverifiedHint = "沒看到字？選單列 Talkiie →「最近口述」可重新插入或複製"
    static let accessibilityHint = "請到選單列 Talkiie →「設定…」→「權限」允許輔助使用。文字已保留在「最近口述」"
    static let partialNote = "前面已有一部分文字進入欄位，可能不完整；不會自動重送，請自行檢查"
    static let busyNote = "上一段還在插入中，這段沒有插入"
    static let startBlockedNote = "上一段還在插入中，請稍候再按"

    init(_ outcome: TranscriptDelivery.Outcome) {
        switch outcome {
        case .inserted:
            succeeded = true
            title = "已插入（未驗證）"
            detail = nil
            caption = Self.unverifiedHint
            canReinsert = true
        case .refused(let reason):
            succeeded = false
            title = "沒有插入"
            detail = reason.message
            caption = reason == .accessibilityNotTrusted ? Self.accessibilityHint : Self.recoveryHint
            canReinsert = reason != .accessibilityNotTrusted
        case .aborted(let sentUnits, let reason):
            succeeded = false
            title = "插入中斷"
            detail = sentUnits > 0 ? reason.text + "\n" + Self.partialNote : reason.text
            caption = Self.recoveryHint
            canReinsert = sentUnits == 0
        case .busy:
            succeeded = false
            title = "沒有插入"
            detail = Self.busyNote
            caption = Self.recoveryHint
            canReinsert = true
        }
    }
}

enum DeliveryAction: Sendable, Equatable {
    case reinsert
    case copy
}

private struct DeliveryPill: View {
    let content: DeliveryContent
    let text: String
    let onAction: (DeliveryAction) -> Void
    static let width: CGFloat = 420

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: content.succeeded ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(content.succeeded ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(content.title).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HUDStyle.text)
                if let detail = content.detail {
                    Text(detail).font(.system(size: 12))
                        .foregroundStyle(HUDStyle.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !text.isEmpty {
                    Text(text).font(.system(size: 13)).lineLimit(6)
                        .foregroundStyle(HUDStyle.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                if !text.isEmpty {
                    HStack(spacing: 8) {
                        if content.canReinsert {
                            Button("重新插入") { onAction(.reinsert) }
                        }
                        Button("複製") { onAction(.copy) }
                            .help("放進剪貼簿（剪貼簿管理器會看到這段文字）")
                    }
                    .controlSize(.small)
                    .padding(.top, 2)
                }
                Text(content.caption).font(.caption).foregroundStyle(HUDStyle.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: Self.width, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .hudRoundedStyle(cornerRadius: 20)
    }
}
