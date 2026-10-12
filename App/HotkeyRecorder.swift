import AppKit
import NaturalInputCore
import SwiftUI

struct HotkeyRecorder: View {
    @EnvironmentObject var model: AppModel
    @Binding var message: String?
    @State private var listening = false

    var body: some View {
        Button { listening ? stop() : start() } label: {
            Text(listening ? "請按下新的熱鍵…" : model.hotkey.label)
                .font(listening ? .body : .body.monospaced().weight(.semibold))
                .foregroundStyle(listening ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(minWidth: 140)
        }
        .background(KeyCatcher(active: listening, onCombo: take, onCancel: stop))
        .accessibilityLabel("口述熱鍵")
        .accessibilityValue(listening ? "正在等你按下新的熱鍵" : model.hotkey.spoken)
        .accessibilityHint("按一下，再按下新的組合鍵；按 Esc 取消。")
        .onDisappear { stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stop() }
    }

    private func start() {
        guard model.phase == .idle else { message = "口述進行中，結束之後再換"; return }
        message = nil
        listening = true
        model.suspendHotkeys(true)
    }

    private func take(_ combo: HotkeyCombo) {
        if combo != model.hotkey || !model.hotkeyRegistered {
            message = model.setHotkey(combo)
            AccessibilityNotification.Announcement(message ?? "熱鍵改成 \(combo.spoken)").post()
        }
        stop()
    }

    private func stop() {
        guard listening else { return }
        listening = false
        model.suspendHotkeys(false)
    }
}

private struct KeyCatcher: NSViewRepresentable {
    let active: Bool
    let onCombo: (HotkeyCombo) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView { KeyCatcherView() }

    func updateNSView(_ view: KeyCatcherView, context: Context) {
        view.onCombo = onCombo
        view.onCancel = onCancel
        guard view.active != active else { return }
        view.active = active
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if active {
                window.makeFirstResponder(view)
            } else if window.firstResponder === view {
                window.makeFirstResponder(nil)
            }
        }
    }
}

final class KeyCatcherView: NSView {
    var active = false
    var onCombo: ((HotkeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { active }

    var isRecording: Bool { active && window?.firstResponder === self }

    override func keyDown(with event: NSEvent) {
        guard active else { return super.keyDown(with: event) }
        take(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        take(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        if active { onCancel?() }
        return true
    }

    private func take(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: HotkeyCombo.Mods = []
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.command) { mods.insert(.command) }
        if event.keyCode == 0x35 && mods.isEmpty { onCancel?(); return }
        onCombo?(HotkeyCombo(keyCode: UInt32(event.keyCode), mods: mods))
    }
}
