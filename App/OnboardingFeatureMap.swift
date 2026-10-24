import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
enum FeatureMapWindow {
    private static var window: NSWindow?
    private static let closer = Closer()

    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: FeatureMapView().environmentObject(AppModel.shared))
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable]
        w.title = "Talkiie 能做的事"
        w.isReleasedWhenClosed = false
        w.delegate = closer
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    static var debugWindow: NSWindow? { window }
    static func debugClose() { window?.close() }
    #endif

    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ n: Notification) {
            MainActor.assumeIsolated { FeatureMapWindow.window = nil }
        }
    }
}

struct FeatureMapRow: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let summary: String
    let state: String
    let on: Bool?
    let target: FeatureTarget?
}

struct FeatureMapView: View {
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var dictionary = PersonalDictionaryStore.shared
    @ObservedObject private var edit = EditCaptureSettings.shared
    @State private var tick = 0

    static let width: CGFloat = 560

    var body: some View {
        let _ = tick
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Talkiie 能做的事").font(.title2.weight(.semibold))
                Text(Edition.Copy.destinationLine).font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 12)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                        FeatureMapRowView(row: row)
                        if i < rows.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 6)
            }
            Divider()
            HStack {
                Text("這裡只是一份清單：要改任何東西，按「打開設定」到對應的頁面。")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("新手導覽…") { OnboardingController.shared.reopen() }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: Self.width, height: 600)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in tick += 1 }
    }

    private func bool(_ key: String, default d: Bool) -> Bool { (UserDefaults.standard.object(forKey: key) as? Bool) ?? d }

    var rows: [FeatureMapRow] {
        let d = UserDefaults.standard
        let tap = TapHotkey.resolve(stored: d.string(forKey: TapHotkey.defaultsKey),
                                    legacyFnEnabled: d.bool(forKey: TapHotkey.legacyFnDefaultsKey))
        let stop = StopTrigger.resolve(stored: d.string(forKey: StopTrigger.defaultsKey))
        let filler = FillerRemoval.strength(fromDefaults: d.string(forKey: FillerRemoval.defaultsKey))
        let paragraph = SemanticParagraphs.strength(fromDefaults: d.string(forKey: SemanticParagraphs.defaultsKey))
        let chime = bool(StartChime.enabledDefaultsKey, default: StartChime.enabledByDefault)
        let lists = bool(SpokenList.defaultsKey, default: SpokenList.defaultEnabled)
        let commands = bool(SpokenCommands.defaultsKey, default: SpokenCommands.defaultEnabled)
        let stats = UsageStats.recordingEnabled(fromDefaults: d.object(forKey: UsageStats.recordingDefaultsKey))
        let nudge = FeatureNudgePlan.isEnabled(fromDefaults: d.object(forKey: FeatureNudgePlan.enabledDefaultsKey))
        let written = WrittenStyleToggleRow.isOn
        let words = dictionary.entries.count

        var out: [FeatureMapRow] = [
            .init(id: "hotkey", symbol: "keyboard", title: "開始／結束口述的熱鍵",
                  summary: "在任何 app 按一下開始說話，再按一下結束，文字打在游標那裡。",
                  state: model.hotkey.label, on: nil, target: .general),
            .init(id: "tap", symbol: "hand.tap", title: "也用這個鍵開始／結束",
                  summary: "再加一個開始鍵：fn、⌃、⌥ 或 ⌘，按一下或按兩下。",
                  state: tap == .off ? "不使用" : tap.label, on: tap != .off, target: .general),
            .init(id: "stop", symbol: "stop.circle", title: "結束錄音的方式",
                  summary: "預設錄音中按任何鍵就結束並插字；也可以指定某個鍵。",
                  state: stop == .anyKey ? "任意鍵" : stop.menuPhrase, on: nil, target: .general),
            .init(id: "chime", symbol: "speaker.wave.2", title: "提示音",
                  summary: "開始與結束時播一聲，確認 Talkiie 有在聽。",
                  state: chime ? "開" : "關", on: chime, target: .general),
            .init(id: "filler", symbol: "scissors", title: "刪除贅字",
                  summary: "把「嗯」「那個」「就是」這類口頭禪自動刪掉，只刪不改。",
                  state: filler == .off ? "關" : "開（\(filler.title)）", on: filler != .off, target: .text),
            .init(id: "lists", symbol: "list.number", title: "口述的清單排成條列",
                  summary: "說「第一點…第二點…」時自動排成編號清單。",
                  state: lists ? "開" : "關", on: lists, target: .text),
            .init(id: "commands", symbol: "return", title: "排版指令「換行」「新段落」",
                  summary: "單獨說一句「換行」或「新段落」就直接換行、空一行。",
                  state: commands ? "開" : "關", on: commands, target: .text),
            .init(id: "paragraphs", symbol: "text.alignleft", title: "長口述自動分段",
                  summary: "說了一長段時，依語意自動分成幾段。",
                  state: paragraph == .off ? "關" : "開（\(paragraph.title)）", on: paragraph != .off, target: .text),
            .init(id: "dictionary", symbol: "character.book.closed", title: "個人詞庫",
                  summary: "人名、產品名常被聽錯，加進詞庫就會認出來、改對。",
                  state: words == 0 ? "還沒有詞" : "\(words) 個詞", on: words > 0, target: .text),
        ]
        if Edition.offersWrittenStyle {
            out.append(.init(id: "written", symbol: "text.badge.checkmark", title: "整理成書面語",
                             summary: "講完之後先照原樣打出來，刪好贅字後讓你按一下換成整理後的版本。",
                             state: written ? "開" : "關", on: written, target: .text))
        }
        out += [
            .init(id: "edit", symbol: "pencil.and.list.clipboard", title: "收集我的修改",
                  summary: "改完剛打出來的字後按 \(edit.shortcut.label)，Talkiie 從你的修改學習。",
                  state: edit.enabled ? "開" : "關", on: edit.enabled, target: .privacy),
            .init(id: "recent", symbol: "clock.arrow.circlepath", title: "最近口述",
                  summary: "選單列 Talkiie →「最近口述」：剛說過的字可以重新插入或複製。",
                  state: "選單列", on: nil, target: nil),
            .init(id: "stats", symbol: "chart.bar.xaxis", title: "使用統計",
                  summary: "今天、這週、這個月說了多少字、省了多少打字時間。",
                  state: stats ? "開" : "關", on: stats, target: .stats),
            .init(id: "nudge", symbol: "lightbulb", title: "功能提示",
                  summary: "偶爾在選單最上面提醒你還沒用過的功能；只帶你去設定頁，不會替你打開。",
                  state: nudge ? "開" : "關", on: nudge, target: .general),
        ]
        return out
    }
}

private struct FeatureMapRowView: View {
    let row: FeatureMapRow

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: row.symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.headline)
                Text(row.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                if let on = row.on {
                    Circle().fill(on ? Color.green : Color.secondary.opacity(0.4)).frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                }
                Text(row.state).font(.callout.monospacedDigit()).foregroundStyle(row.on == false ? .secondary : .primary)
            }
            .frame(minWidth: 70, alignment: .trailing)
            if let target = row.target {
                Button("打開設定") { SettingsWindow.show(SettingsTab(target)) }
                    .controlSize(.small)
            } else {
                Color.clear.frame(width: 72, height: 1)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .contain)
    }
}
