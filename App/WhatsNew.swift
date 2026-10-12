import AppKit
import Combine
import NaturalInputCore
import SwiftUI

@MainActor
final class WhatsNew: ObservableObject {
    static let shared = WhatsNew()

    @Published private(set) var unseen: String?

    private var waiting: Task<Void, Never>?

    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static func loadNotes() -> ReleaseNotes? {
        guard let path = Bundle.main.path(forResource: Edition.releaseNotesResource, ofType: "json"),
              let data = FileManager.default.contents(atPath: path) else { return nil }
        return ReleaseNotes.decode(data)
    }

    static let hasNotesForCurrent: Bool = !(loadNotes()?.between(nil, current).isEmpty ?? true)

    private static var state: WhatsNewPlan.State {
        get {
            let d = UserDefaults.standard
            return .init(lastVersion: d.string(forKey: WhatsNewPlan.Keys.lastVersion),
                         unseen: d.string(forKey: WhatsNewPlan.Keys.unseen),
                         since: d.string(forKey: WhatsNewPlan.Keys.since))
        }
        set {
            let d = UserDefaults.standard
            func put(_ v: String?, _ k: String) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } }
            put(newValue.lastVersion, WhatsNewPlan.Keys.lastVersion)
            put(newValue.unseen, WhatsNewPlan.Keys.unseen)
            put(newValue.since, WhatsNewPlan.Keys.since)
        }
    }

    func launched(consented: Bool) {
        let d = UserDefaults.standard
        let relaunched = d.bool(forKey: WhatsNewPlan.Keys.relaunchedByUpdate)
        d.removeObject(forKey: WhatsNewPlan.Keys.relaunchedByUpdate)
        let notes = Self.loadNotes()
        if notes == nil { Log.record(.updater(.whatsNewNoNotes)) }
        let l = WhatsNewPlan.onLaunch(current: Self.current, state: Self.state, relaunchedByUpdate: relaunched,
                                      consented: consented, notes: notes)
        Self.state = l.state
        unseen = l.state.unseen
        guard l.presentation != .none else { return }
        Log.record(.updater(.whatsNewPending(releases: l.releases.count, window: l.presentation == .window)))
        if l.presentation == .window { showWhenFree() }
    }

    func show() {
        waiting?.cancel()
        waiting = nil
        guard let notes = Self.loadNotes() else { return }
        let c = WhatsNewPlan.content(current: Self.current, state: Self.state, notes: notes)
        guard !c.releases.isEmpty else { return }
        WhatsNewWindow.show(WhatsNewView(releases: c.releases, to: c.to, from: c.from, close: { WhatsNewWindow.close() }))
        Log.record(.updater(.whatsNewShown(releases: c.releases.count)))
        Self.state = WhatsNewPlan.afterShown(Self.state)
        unseen = nil
    }

    private func showWhenFree() {
        waiting?.cancel()
        waiting = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let m = AppModel.shared
                if ConsentStore.allowsCapture,
                   UpdateRelaunchGate.mayRelaunch(idle: m.phase == .idle, deliveringTranscript: m.deliveringNewTranscript,
                                                  inserting: m.inserting) {
                    self?.show()
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

struct PendingUpdateSection: View {
    @ObservedObject var updater = Updater.shared
    @ObservedObject var whatsNew = WhatsNew.shared

    var body: some View {
        if let v = updater.available {
            Button("Talkiie \(v) 可以更新了…") { updater.showUpdate() }
        }
        if let v = whatsNew.unseen {
            Button("看看 \(v) 的新功能") { whatsNew.show() }
        }
        if updater.available != nil || whatsNew.unseen != nil {
            Divider()
        }
    }
}

struct WhatsNewAboutRow: View {
    var body: some View {
        LabeledContent("這一版改了什麼") {
            Button("這一版的新功能…") { WhatsNew.shared.show() }
                .disabled(!WhatsNew.hasNotesForCurrent)
        }
    }
}

@MainActor
enum WhatsNewWindow {
    private static var window: NSWindow?
    private static let closer = Closer()

    static func show(_ view: WhatsNewView) {
        NSApp.activate(ignoringOtherApps: true)
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        if let w = window {
            w.contentViewController = host
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "Talkiie 新功能"
        w.isReleasedWhenClosed = false
        w.delegate = closer
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    static func close() { window?.performClose(nil) }

    static var isOpen: Bool { window != nil }

    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ n: Notification) {
            MainActor.assumeIsolated { WhatsNewWindow.window = nil }
        }
    }
}

struct WhatsNewView: View {
    let releases: [ReleaseNotes.Release]
    let to: String
    let from: String?
    var close: () -> Void

    private var count: Int { releases.reduce(0) { $0 + $1.items.count } }
    private var subtitle: String {
        if releases.count > 1, let from {
            return "從 \(from) 更新上來，這幾版一共有 \(count) 項改變。"
        }
        return "這一版有 \(count) 項改變，下面告訴你怎麼用。"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    ForEach(releases) { r in release(r) }
                }
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 24)
            }
            Divider()
            HStack {
                Text("之後想再看：選單列的 Talkiie →「設定…」→「關於」→「這一版的新功能…」")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("知道了") { close() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 540)
        .frame(minHeight: 360, idealHeight: 600, maxHeight: 720)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Talkiie 更新到 \(to)").font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func release(_ r: ReleaseNotes.Release) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if releases.count > 1 {
                Text("\(r.version) · \(Self.date(r.date))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            if let summary = r.summary, !summary.isEmpty {
                Text(summary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(r.items.filter { $0.kind != .fixed }.enumerated()), id: \.offset) { _, item in
                WhatsNewItemCard(item: item)
            }
            let fixes = r.items.filter { $0.kind == .fixed }
            if !fixes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("修正").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(fixes.enumerated()), id: \.offset) { _, f in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.green)
                                .accessibilityHidden(true)
                            (Text(f.title + "。") + Text(f.body).foregroundColor(.secondary))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    static func date(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? "\(p[1]) 月 \(p[2]) 日" : iso
    }
}

private struct WhatsNewItemCard: View {
    let item: ReleaseNotes.Item

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.kind == .improved ? "wand.and.stars" : "sparkles")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.title).font(.headline)
                    Text(item.kind == .improved ? "改進" : "新功能")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                Text(item.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let how = item.how, !how.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("怎麼用").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        ForEach(Array(how.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("\(i + 1).").monospacedDigit().foregroundStyle(.tertiary)
                                Text(step).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .font(.callout)
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .contain)
    }
}
