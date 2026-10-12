import AppKit
import SwiftUI
import NaturalInputCore

enum Motion {
    static let quick: Double = 0.15
    static let fast: Double = 0.25
    static let medium: Double = 0.35
    static func smoothOut(_ d: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: d) }
    static func bounce(_ d: Double) -> Animation { .timingCurve(0.34, 1.36, 0.64, 1, duration: d) }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

@MainActor
enum HUDStyle {
    static var previewOverride: HUDTheme?

    static var theme: HUDTheme {
        previewOverride ?? HUDTheme.effective(stored: UserDefaults.standard.string(forKey: HUDTheme.defaultsKey),
                                              unlocked: Edition.plusUnlocked)
    }
    private static var palette: HUDPalette { theme.palette }

    static var background: Color { color(palette.background) }
    static var stroke: Color { color(palette.stroke) }
    static var shadowColor: Color { color(palette.shadow) }
    static let shadowRadius: CGFloat = 6
    static let shadowY: CGFloat = 2

    static var text: Color { theme.usesGlassSurface ? glassText : color(palette.text) }
    static var secondaryText: Color { theme.usesGlassSurface ? glassSecondaryText : color(palette.secondaryText) }

    private static func color(_ c: HUDPalette.RGBA) -> Color {
        Color(red: c.red, green: c.green, blue: c.blue, opacity: c.opacity)
    }

    #if DEBUG
    static var debugLastSurfaceUsedGlass: Bool?
    static func debugMarkSurface(glass: Bool) { debugLastSurfaceUsedGlass = glass }
    #else
    static func debugMarkSurface(glass: Bool) {}
    #endif
}

extension View {
    @MainActor func hudCapsuleStyle() -> some View {
        hudSurface(in: Capsule())
    }

    @MainActor func hudRoundedStyle(cornerRadius: CGFloat) -> some View {
        hudSurface(in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    @MainActor @ViewBuilder func hudSurface(in shape: some InsettableShape) -> some View {
        if HUDStyle.theme.usesGlassSurface {
            let _ = HUDStyle.debugMarkSurface(glass: true)
            self.background { HUDGlassSurface(shape: shape) }
        } else {
            let _ = HUDStyle.debugMarkSurface(glass: false)
            self
                .background(HUDStyle.background, in: shape)
                .overlay(shape.strokeBorder(HUDStyle.stroke))
                .shadow(color: HUDStyle.shadowColor, radius: HUDStyle.shadowRadius, y: HUDStyle.shadowY)
        }
    }

    @MainActor @ViewBuilder func hudSurfaceBackground(in shape: some InsettableShape) -> some View {
        if HUDStyle.theme.usesGlassSurface {
            let _ = HUDStyle.debugMarkSurface(glass: true)
            self.background { HUDGlassSurface(shape: shape) }
        } else {
            let _ = HUDStyle.debugMarkSurface(glass: false)
            self.background(HUDStyle.background, in: shape)
        }
    }

    @MainActor @ViewBuilder func hudSurfaceStrokeAndShadow(in shape: some InsettableShape) -> some View {
        if HUDStyle.theme.usesGlassSurface {
            self.hudGlassStrokeAndShadow(in: shape)
        } else {
            self
                .overlay(shape.strokeBorder(HUDStyle.stroke))
                .shadow(color: HUDStyle.shadowColor, radius: HUDStyle.shadowRadius, y: HUDStyle.shadowY)
        }
    }
}

enum CapsuleButton: Sendable {
    case cancel
    case confirm
}

@MainActor
final class CapsuleModel: ObservableObject {
    enum Mode: Equatable {
        case listening
        case thinking(transmitting: Bool)
        case success
    }

    @Published private(set) var mode: Mode = .listening
    @Published private(set) var caption: String?
    @Published private(set) var levels: [CGFloat]
    @Published var hovering = false

    private(set) var orbLevel = 0.0
    private var orbEnvelope = OrbVoiceEnvelope()

    static let barCount = 24
    static let maxPending = 6
    static let decay: CGFloat = 0.8

    private var pending: [CGFloat] = []
    private var ticker: Timer?
    @Published private(set) var parked = false

    #if DEBUG
    private(set) var modeHistory: [Mode] = []
    #endif

    init() { levels = Array(repeating: 0, count: Self.barCount) }

    func set(mode: Mode, caption: String?) {
        self.caption = caption
        #if DEBUG
        if modeHistory.last != mode { modeHistory.append(mode) }
        #endif
        if mode == .listening {
            if self.mode != .listening || parked { resetLevels() }
            startTicker()
        } else {
            stopTicker()
        }
        parked = false
        if Motion.reduceMotion {
            self.mode = mode
        } else {
            withAnimation(Motion.smoothOut(Motion.medium)) { self.mode = mode }
        }
    }

    func dismiss() {
        stopTicker()
        resetLevels()
        parked = true
    }

    #if DEBUG
    func debugClearHistory() { modeHistory.removeAll() }
    var debugTickerRunning: Bool { ticker != nil }
    #endif

    func resetLevels() {
        pending.removeAll()
        orbEnvelope = OrbVoiceEnvelope()
        orbLevel = 0
        levels = Array(repeating: 0, count: Self.barCount)
        hovering = false
    }

    func push(rms: [Float]) {
        guard mode == .listening else { return }
        pending.append(contentsOf: rms.map(Self.normalized))
        if pending.count > Self.maxPending { pending.removeFirst(pending.count - Self.maxPending) }
    }

    func tick() {
        let next = pending.isEmpty ? (levels.last ?? 0) * Self.decay : pending.removeFirst()
        orbLevel = orbEnvelope.next(Double(next), dt: 1 / AudioCapture.levelHz)
        levels.removeFirst()
        levels.append(next < 0.01 ? 0 : next)
    }

    nonisolated static func normalized(_ rms: Float) -> CGFloat { CGFloat(OrbVoiceEnvelope.normalized(rms: rms)) }

    private func startTicker() {
        guard ticker == nil else { return }
        let t = Timer(timeInterval: 1 / AudioCapture.levelHz, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

struct CapsuleView: View {
    @ObservedObject var model: CapsuleModel
    let onButton: (CapsuleButton) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(CapsuleStyle.defaultsKey) private var styleRaw = CapsuleStyle.defaultValue.rawValue

    static let height: CGFloat = 52

    private var listening: Bool { model.mode == .listening }
    private var live: Bool { !reduceMotion && !model.parked }
    private var style: CapsuleStyle { CapsuleStyle.resolve(stored: styleRaw) }
    private var showButtons: Bool { style.showsButtons(listening: listening, hovering: model.hovering) }
    private var buttonTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let caption = model.caption {
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HUDStyle.text)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .hudCapsuleStyle()
                    .fixedSize()
                    .transition(.opacity)
            }
            capsule
        }
        .padding(8)
    }

    private var capsule: some View {
        HStack(spacing: showButtons ? 10 : 0) {
            if showButtons {
                button(.cancel, symbol: "xmark", label: "取消並丟棄（Esc）")
                    .transition(buttonTransition)
            }
            ZStack {
                centerContent
            }
            .frame(width: OrbView.size, height: OrbView.size)
            if showButtons {
                button(.confirm, symbol: "checkmark", label: "結束並插字（\(AppModel.stopTrigger.menuPhrase)）")
                    .transition(buttonTransition)
            }
        }
        .padding(.horizontal, showButtons ? 8 : (Self.height - OrbView.size) / 2)
        .frame(height: Self.height)
        .hudSurfaceBackground(in: Capsule())
        .clipShape(Capsule())
        .hudSurfaceStrokeAndShadow(in: Capsule())
        .onHover { inside in
            guard style == .minimal, model.hovering != inside else { return }
            if reduceMotion {
                model.hovering = inside
            } else {
                withAnimation(Motion.smoothOut(Motion.quick)) { model.hovering = inside }
            }
            RecordingHUD.resizeForCapsule()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityActions {
            if listening && !showButtons {
                Button("取消並丟棄") { onButton(.cancel) }
                Button("結束並插字") { onButton(.confirm) }
            }
        }
    }

    @MainActor @ViewBuilder
    private var centerContent: some View {
        OrbView(mode: .listening(level: listening ? model.orbLevel : 0),
               animating: live && (listening || model.mode == .thinking(transmitting: false)))
            .opacity(listening || model.mode == .thinking(transmitting: false) ? 1 : 0)
        OrbView(mode: .transcribing, animating: live && model.mode == .thinking(transmitting: true))
            .opacity(model.mode == .thinking(transmitting: true) ? 1 : 0)
        if model.mode == .success {
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color.green)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.6).combined(with: .opacity))
                .accessibilityLabel(DeliveryContent(.inserted(.enforced)).title)
        }
    }

    private var accessibilityTitle: String {
        switch model.mode {
        case .listening: return "Talkiie 聆聽中"
        case .thinking(let transmitting): return RecordingHUD.sendingTitle(transmitting: transmitting)
        case .success: return DeliveryContent(.inserted(.enforced)).title
        }
    }

    @ViewBuilder
    private func button(_ b: CapsuleButton, symbol: String, label: String) -> some View {
        if #available(macOS 26, *), HUDStyle.theme.usesGlassSurface {
            HUDGlassButton(symbol: symbol, label: label) { onButton(b) }
        } else {
            Button { onButton(b) } label: {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(b == .confirm ? 0.18 : 0.10), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(label)
        }
    }
}

struct OrbView: NSViewRepresentable {
    let mode: OrbGeometry.Mode
    let animating: Bool

    static let size: CGFloat = 44

    func makeNSView(context: Context) -> OrbNSView { OrbNSView() }

    func updateNSView(_ view: OrbNSView, context: Context) {
        view.mode = mode
        view.animating = animating
        view.syncTimer()
    }
}

final class OrbNSView: NSView {
    var mode: OrbGeometry.Mode = .transcribing {
        didSet { if mode != oldValue { needsDisplay = true } }
    }
    var animating = false {
        didSet { if animating != oldValue { syncTimer(); needsDisplay = true } }
    }

    private var timer: Timer?
    private static let epoch = Date()

    #if DEBUG
    private(set) static var debugRunningTimers = 0
    static var debugFixedTime: Double?
    #endif

    override var isFlipped: Bool { true }

    static func ink(_ white: Double) -> Double { min(1, max(0, 1 - white)) }

    static func backgroundIsDark(theme: HUDTheme, appearance: NSAppearance?) -> Bool {
        guard theme.usesGlassSurface else { return true }
        return glassBackgroundIsDark(appearance: appearance)
    }

    private var effectiveTime = 0.0
    private var lastClock: Date?
    static let voiceSpeedup = 0.8

    private func clock() -> Double {
        let now = Date()
        let dt = lastClock.map { min(0.1, now.timeIntervalSince($0)) } ?? 0
        lastClock = now
        if case .listening(let level) = mode {
            effectiveTime += dt * (1 + Self.voiceSpeedup * min(1, max(0, level)))
        } else {
            effectiveTime += dt
        }
        return effectiveTime
    }

    private var visibilityObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let o = visibilityObserver { NotificationCenter.default.removeObserver(o) }
        visibilityObserver = window.map { w in
            NotificationCenter.default.addObserver(
                forName: CapsulePanel.visibilityDidChange, object: w, queue: nil
            ) { [weak self] _ in MainActor.assumeIsolated { self?.syncTimer() } }
        }
        syncTimer()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        var t = timer != nil ? clock() : OrbGeometry.staticTime
        #if DEBUG
        if let fixed = Self.debugFixedTime { t = fixed }
        #endif
        let theme = HUDStyle.theme
        let dark = Self.backgroundIsDark(theme: theme, appearance: effectiveAppearance)
        cg.saveGState()
        if theme.usesGlassSurface {
            Self.applyGlassOrbShadow(cg, dark: dark)
        }
        for d in OrbGeometry.frame(mode, size: Double(bounds.width), time: t) {
            cg.setFillColor(gray: dark ? Self.ink(d.white) : d.white, alpha: d.alpha)
            cg.fillEllipse(in: CGRect(x: d.x - d.r, y: d.y - d.r, width: 2 * d.r, height: 2 * d.r))
        }
        cg.restoreGState()
    }

    func syncTimer() {
        let want = animating && window?.isVisible == true
        guard want != (timer != nil) else { return }
        if want {
            let t = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.needsDisplay = true }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            #if DEBUG
            Self.debugRunningTimers += 1
            #endif
        } else {
            timer?.invalidate()
            timer = nil
            #if DEBUG
            Self.debugRunningTimers -= 1
            #endif
        }
    }
}

final class CapsulePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static let visibilityDidChange = Notification.Name("CapsulePanel.visibilityDidChange")

    override func orderFrontRegardless() {
        super.orderFrontRegardless()
        NotificationCenter.default.post(name: Self.visibilityDidChange, object: self)
    }

    override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        NotificationCenter.default.post(name: Self.visibilityDidChange, object: self)
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
