import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
final class WrittenStyleKeepWordsStore: ObservableObject {
    static let shared = WrittenStyleKeepWordsStore()

    nonisolated static var current: [String] {
        WrittenStyleKeepWords.words(fromDefaults: UserDefaults.standard.object(forKey: WrittenStyleKeepWords.defaultsKey))
    }

    @Published private(set) var words = WrittenStyleKeepWordsStore.current

    @discardableResult
    func mark(_ marked: Set<String>, offered: [String]) -> Int {
        let before = Set(words)
        let new = WrittenStyleKeepWords.adding(marked: marked, offered: offered, to: words)
        save(new)
        let added = new.filter { !before.contains($0) }.count
        Log.record(.keepWordsMarked(added: added, total: new.count))
        return added
    }

    func remove(_ word: String) { save(WrittenStyleKeepWords.removing(word, from: words)) }

    private func save(_ list: [String]) {
        UserDefaults.standard.set(list, forKey: WrittenStyleKeepWords.defaultsKey)
        words = Self.current
    }
}

struct WrittenStyleToggleRow: View {
    @AppStorage(WrittenStyle.enabledDefaultsKey) private var enabled = WrittenStyle.defaultEnabled

    static var isOn: Bool { WrittenStyle.enabled(fromDefaults: UserDefaults.standard.object(forKey: WrittenStyle.enabledDefaultsKey)) }

    static var help: String { Edition.Copy.writtenStyleHelp ?? "" }

    var body: some View {
        FeatureToggleRow(title: "整理成書面語", summary: Self.help, isOn: $enabled)
    }
}

struct WrittenStyleSettingsSection: View {
    @ObservedObject var keepWords = WrittenStyleKeepWordsStore.shared
    @State private var hovered: String?
    @AppStorage(WrittenStyle.enabledDefaultsKey) private var enabled = WrittenStyle.defaultEnabled

    var body: some View {
        WrittenStyleToggleRow()
        ExampleDisclosure {
            SettingsHelp(text: "只刪不改寫：否定、數字、英文、問句一律保留；刪太多就照原文打出來。")
            DeletionExample(original: WrittenStyle.example, result: WrittenStyle.exampleResult,
                            resultCaption: enabled ? "打出來的是" : "打開之後打出來的是")
        }
        if !keepWords.words.isEmpty {
            DisclosureGroup {
                SettingsHelp(text: "你在「插入原文」之後標「這個不該刪」的詞；整理時一律保留。")
                ForEach(keepWords.words, id: \.self) { w in
                    HStack(spacing: 8) {
                        Text(w)
                        TagBadge(text: "自己標的", symbol: "hand.point.up.left")
                        Spacer()
                        HoverDeleteButton(hovering: hovered == w, accessibilityLabel: "刪除「\(w)」") { keepWords.remove(w) }
                    }
                    .contentShape(Rectangle())
                    .onHover { hovered = $0 ? w : (hovered == w ? nil : hovered) }
                }
            } label: {
                Text("不要刪的詞・\(keepWords.words.count) 個").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
enum RevertMarksPanel {
    static let title = "已插入原文。有哪些詞不該刪？"
    static let caption = "點選後按「加進不要刪的詞」；不用的話按略過。之後整理時會保留這些詞。"

    private static let model = RevertMarksModel()
    private static var panel: FallbackNSPanel?

    static func show(words: [String]) {
        guard !words.isEmpty else { return }
        model.words = words
        model.marked = []
        let p = panel ?? makePanel()
        panel = p
        if !(p.contentView is NSHostingView<RevertMarksView>) {
            let host = FirstMouseHostingView(rootView: RevertMarksView(model: model) { action in
                switch action {
                case .save:
                    let added = WrittenStyleKeepWordsStore.shared.mark(model.marked, offered: model.words)
                    close()
                    if added > 0 { RecordingHUD.showNotice("\(added) 個詞加進「不要刪的詞」", seconds: 1.5) }
                case .skip:
                    close()
                }
            })
            host.sizingOptions = []
            p.contentView = host
        }
        let c = NSHostingController(rootView: RevertMarksView(model: model) { _ in }.fixedSize(horizontal: false, vertical: true))
        let s = c.sizeThatFits(in: NSSize(width: RevertMarksView.width, height: 4000))
        var frame = p.frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: RevertMarksView.width, height: ceil(s.height))))
        if let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            frame.origin = NSPoint(x: (vf.midX - frame.width / 2).rounded(), y: vf.minY + FallbackPanel.bottomInset)
        }
        p.setFrame(frame, display: true)
        p.orderFrontRegardless()
    }

    static func close() {
        panel?.orderOut(nil)
        model.words = []
        model.marked = []
    }

    private static func makePanel() -> FallbackNSPanel {
        let p = FallbackNSPanel(contentRect: NSRect(x: 0, y: 0, width: RevertMarksView.width, height: 80),
                                styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.onClose = { RevertMarksPanel.close() }
        return p
    }
}

@MainActor
final class RevertMarksModel: ObservableObject {
    @Published var words: [String] = []
    @Published var marked: Set<String> = []
}

struct RevertMarksView: View {
    enum Action { case save, skip }

    @ObservedObject var model: RevertMarksModel
    let onAction: (Action) -> Void

    static let width: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(RevertMarksPanel.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(HUDStyle.text)
                Spacer()
                Button { onAction(.skip) } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7)).frame(width: 20, height: 20)
                        .background(Color.white.opacity(0.14), in: Circle()).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("略過（Esc）")
            }
            FlowRow(spacing: 6) {
                ForEach(model.words, id: \.self) { w in
                    let on = model.marked.contains(w)
                    Button {
                        if on { model.marked.remove(w) } else { model.marked.insert(w) }
                    } label: {
                        Text(w).font(.system(size: 13))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .foregroundStyle(on ? Color.black : HUDStyle.text)
                            .background(on ? Color.white.opacity(0.9) : Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(on ? "已標「這個不該刪」" : "這個不該刪")
                }
            }
            HStack(spacing: 8) {
                Button("加進不要刪的詞") { onAction(.save) }.disabled(model.marked.isEmpty)
                Button("略過") { onAction(.skip) }
            }
            .controlSize(.small)
            Text(RevertMarksPanel.caption).font(.caption).foregroundStyle(HUDStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .hudRoundedStyle(cornerRadius: 18)
        .frame(width: Self.width, alignment: .leading)
    }
}

struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 340
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
