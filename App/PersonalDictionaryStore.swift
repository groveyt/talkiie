import AppKit
import NaturalInputCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PersonalDictionaryStore: ObservableObject {
    static let shared = PersonalDictionaryStore()

    @Published private(set) var entries: [PersonalDictionary.Entry]

    private init() { entries = Self.load() }

    static var current: PersonalDictionary {
        PersonalDictionary(entries: load(), phonetic: fuzzyEnabled ? BopomofoLexicon.shared : nil)
    }

    static var fuzzyEnabled: Bool {
        PersonalDictionary.fuzzyEnabled(fromDefaults: UserDefaults.standard.object(forKey: PersonalDictionary.fuzzyDefaultsKey))
    }

    private static func load() -> [PersonalDictionary.Entry] {
        PersonalDictionary.decode(UserDefaults.standard.array(forKey: PersonalDictionary.defaultsKey))
    }

    @discardableResult
    func addTerms(_ text: String) -> Int {
        let existing = Set(entries.filter(PersonalDictionary.isTermOnly).map { PersonalDictionary.normalizedKey($0.replacement) })
        let new = PersonalDictionary.terms(from: text).filter { !existing.contains(PersonalDictionary.normalizedKey($0.replacement)) }
        guard !new.isEmpty else { return 0 }
        save(entries + new)
        return new.count
    }

    @discardableResult
    func add(heard: String, replacement: String) -> PersonalDictionary.Problem? {
        if let problem = PersonalDictionary.problem(heard: heard, replacement: replacement) { return problem }
        let entry = PersonalDictionary.Entry(heard: heard.trimmingCharacters(in: .whitespacesAndNewlines),
                                             replacement: replacement.trimmingCharacters(in: .whitespacesAndNewlines))
        let key = PersonalDictionary.normalizedKey(entry.heard)
        var next = entries.filter { PersonalDictionary.normalizedKey($0.heard) != key }
        next.append(entry)
        save(next)
        return nil
    }

    func learn(inserted: String, edited: String) -> (added: Int, refreshed: Int, promptOnly: Int) {
        guard let lexicon = BopomofoLexicon.shared else { return (0, 0, 0) }
        let learned = DictionaryLearner.learn(inserted: inserted, edited: edited, lexicon: lexicon)
        guard !learned.isEmpty else { return (0, 0, 0) }
        let merged = PersonalDictionary.merging(learned: learned, into: entries)
        if merged.added + merged.refreshed > 0 { save(merged.entries) }
        let keys = Set(learned.map { PersonalDictionary.normalizedKey($0.heard) })
        let promptOnly = merged.entries.filter { $0.origin == .learned && $0.promptOnly
            && keys.contains(PersonalDictionary.normalizedKey($0.heard)) }.count
        return (merged.added, merged.refreshed, promptOnly)
    }

    func remove(_ entry: PersonalDictionary.Entry) {
        save(entries.filter { $0 != entry })
    }

    var exportData: Data { PersonalDictionaryExchange.export(entries) }

    @discardableResult
    func importEntries(_ imported: [PersonalDictionary.Entry]) -> PersonalDictionaryExchange.MergeResult {
        let merged = PersonalDictionaryExchange.merge(imported, into: entries)
        if merged.changesSomething { save(merged.entries) }
        return merged
    }

    #if DEBUG
    func useSample() {
        sampleOnly = true
        entries = [
            .init(heard: "", replacement: "Talkiie", promptOnly: true),
            .init(heard: "石庫", replacement: "詞庫", origin: .learned),
            .init(heard: "資源", replacement: "此元", origin: .learned, promptOnly: true),
            .init(heard: "淘氣", replacement: "Talkiie"),
            .init(heard: "麥克迷你", replacement: "Mac mini"),
            .init(heard: "", replacement: "Sparkle", promptOnly: true),
            .init(heard: "惠斯伯", replacement: "whisper", origin: .learned),
            .init(heard: "", replacement: "Breeze", promptOnly: true),
            .init(heard: "愛兒", replacement: "Air"),
            .init(heard: "安靜卡", replacement: "AirDrop", origin: .learned),
            .init(heard: "", replacement: "TestFlight", promptOnly: true),
        ]
    }
    private var sampleOnly = false
    #else
    private let sampleOnly = false
    #endif

    var prompt: TranscriptionPrompt { TranscriptionPrompt(dictionary: PersonalDictionary(entries: entries)) }

    private func save(_ next: [PersonalDictionary.Entry]) {
        entries = next
        guard !sampleOnly else { return }
        UserDefaults.standard.set(PersonalDictionary.encode(next), forKey: PersonalDictionary.defaultsKey)
    }
}

struct PersonalDictionarySection: View {
    @ObservedObject var store: PersonalDictionaryStore
    @AppStorage(PersonalDictionary.fuzzyDefaultsKey) private var fuzzyOn = PersonalDictionary.fuzzyDefault
    @State private var heard = ""
    @State private var replacement = ""
    @State private var problem: PersonalDictionary.Problem?
    @State private var adding = false
    @State private var query = ""
    @State private var showAll = false
    @State private var hovered: PersonalDictionary.Entry?
    @FocusState private var searchFocused: Bool

    static let recentCount = 8

    private var visible: [PersonalDictionary.Entry] {
        let newestFirst = Array(store.entries.reversed())
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            return newestFirst.filter { $0.heard.localizedCaseInsensitiveContains(q) || $0.replacement.localizedCaseInsensitiveContains(q) }
        }
        return showAll ? newestFirst : Array(newestFirst.prefix(Self.recentCount))
    }

    var body: some View {
        Section {
            FeatureLabel(title: "常聽錯的詞填一次，之後自動改",
                         summary: "「聽成」留空就只是幫忙認字（人名、產品名）。打開「收集我的修改」會自動加入新發現的錯字（標「自動加入」）。")
            let prompt = store.prompt
            if store.entries.isEmpty {
                Text("還沒有詞。按右上角「新增…」加入第一個。").foregroundStyle(.secondary)
            } else {
                promptSummary(prompt)
                if store.entries.count > Self.recentCount {
                    TextField("搜尋", text: $query, prompt: Text("搜尋詞庫"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .focused($searchFocused)
                        .onAppear { DispatchQueue.main.async { searchFocused = false; NSApp.keyWindow?.makeFirstResponder(nil) } }
                }
                let rows = visible
                if rows.isEmpty {
                    Text("找不到「\(query)」").foregroundStyle(.secondary)
                }
                ForEach(rows, id: \.self) { entry in entryRow(entry, status: prompt.status(of: entry)) }
                if query.isEmpty, store.entries.count > Self.recentCount {
                    Button(showAll ? "只顯示最近 \(Self.recentCount) 個" : "顯示全部 \(store.entries.count) 個") {
                        showAll.toggle()
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }
            FeatureToggleRow(title: "注音相近的錯字也改",
                             summary: "例如「石庫」改成「詞庫」；改錯時可以關掉。",
                             isOn: $fuzzyOn)
            HStack(spacing: 8) {
                Button("匯入…", action: importDictionary)
                Button("匯出…", action: exportDictionary)
                    .disabled(store.entries.isEmpty)
                if Edition.offersPhoneApp {
                    Button("用 AirDrop 傳到 iPhone…", action: sendViaAirDrop)
                        .disabled(store.entries.isEmpty)
                        .help("選你的手機，手機上會直接打開 Talkiie、問你要不要匯入，按「匯入」就好。")
                }
                Spacer()
            }
            .controlSize(.small)
        } header: {
            HStack(alignment: .firstTextBaseline) {
                Text("個人詞庫・\(store.entries.count) 個詞")
                Spacer()
                Button("新增…") { adding = true }
                    .controlSize(.small)
                    .popover(isPresented: $adding, arrowEdge: .bottom) { addForm }
            }
        } footer: {
            SettingsHelp(text: Edition.Copy.personalDictionaryNote)
        }
    }

    @ViewBuilder
    private func promptSummary(_ prompt: TranscriptionPrompt) -> some View {
        if prompt.candidateCount > 0 {
            if prompt.isEmpty {
                Text(TranscriptionPrompt.belowMinimumSummary(candidateCount: prompt.candidateCount))
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(Edition.Copy.personalDictionaryPromptSummary(sent: prompt.terms.count, total: prompt.candidateCount)
                     + (prompt.counts.dropped > 0 ? "・提示詞放不下時，最舊的詞先不用" : ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func entryRow(_ entry: PersonalDictionary.Entry, status: TranscriptionPrompt.TermStatus) -> some View {
        let termOnly = PersonalDictionary.isTermOnly(entry)
        return HStack(spacing: 8) {
            if !termOnly {
                Text(entry.heard).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary).accessibilityLabel("改成")
            }
            Text(entry.replacement)
            Spacer(minLength: 8)
            if termOnly {
                TagBadge(text: "幫忙認字", symbol: "text.magnifyingglass",
                         help: "沒有「聽成」：用來幫 whisper 認得「\(entry.replacement)」")
            } else if entry.promptOnly {
                TagBadge(text: "只當提示詞", symbol: "lightbulb",
                         help: "「\(entry.heard)」不會被換掉（本身是常用字詞，精確替換容易誤傷）；「\(entry.replacement)」只用來幫忙認字")
            }
            if entry.origin == .learned {
                TagBadge(text: "自動加入", symbol: "sparkles", help: "從「收集我的修改」自動加入；不要的話按右邊刪除")
            }
            switch status {
            case .budgetFull:
                TagBadge(text: Edition.Copy.personalDictionaryNotSentFull, symbol: "tray.full",
                         help: "提示詞有上限，詞庫裡最舊的詞先不用；刪掉用不到的詞就能空出位置")
            case .notAWord:
                TagBadge(text: Edition.Copy.personalDictionaryNotSentNotAWord, symbol: "questionmark.circle",
                         help: "自動學到的「\(entry.replacement)」看起來不是一個詞（例如功能字片語），所以不拿來當提示詞；不要的話按右邊刪除")
            case .sent, .tooFewTerms, .unusable:
                EmptyView()
            }
            HoverDeleteButton(hovering: hovered == entry,
                              accessibilityLabel: "刪除「\(termOnly ? entry.replacement : entry.heard)」") {
                store.remove(entry)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = entry } else if hovered == entry { hovered = nil }
        }
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新增到個人詞庫").font(.headline)
            HStack {
                TextField("聽成", text: $heard, prompt: Text("聽成（可留空）"))
                    .frame(width: 130)
                    .onSubmit(add)
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("改成", text: $replacement, prompt: Text("改成（可以貼一串，用、分開）"))
                    .frame(width: 220)
                    .onSubmit(add)
            }
            .textFieldStyle(.roundedBorder)
            .labelsHidden()
            if let problem {
                SettingsHelp(text: problem.message, warn: true)
            } else {
                SettingsHelp(text: "「聽成」留空：「改成」可以一次貼一串詞，只幫忙認字。").font(.caption)
            }
            HStack {
                Spacer()
                Button("取消") { adding = false; problem = nil }
                    .keyboardShortcut(.cancelAction)
                Button("加入", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(replacement.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 420)
        .onChange(of: heard) { problem = nil }
        .onChange(of: replacement) { problem = nil }
    }

    private func sendViaAirDrop() {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            Self.alert("沒辦法用 AirDrop", "這台 Mac 找不到 AirDrop。可以改用「匯出詞庫…」存檔再傳。")
            return
        }
        AirDropHandoff.removeLeftovers()
        let url: URL
        do { url = try AirDropHandoff.write(store.exportData) } catch {
            Self.alert("沒有傳出", "暫存檔寫不進去，請再試一次。")
            return
        }
        guard service.canPerform(withItems: [url]) else {
            AirDropHandoff.remove(url)
            Self.alert("沒辦法用 AirDrop", "請確認這台 Mac 的 Wi-Fi 與藍牙都開著，iPhone 解鎖、AirDrop 允許接收。")
            return
        }
        AirDropHandoff.start(service, url: url)
    }

    private func exportDictionary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = PersonalDictionaryExchange.suggestedFileName
        panel.message = Edition.offersPhoneApp
            ? "存成詞庫檔（.json），可以用 AirDrop 傳到 iPhone，在 Talkiie app 的「個人詞庫」匯入。"
            : "存成詞庫檔（.json），可以拿到另一台 Mac 的 Talkiie 匯入。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData.write(to: url, options: .atomic)
        } catch {
            Self.alert("沒有匯出", "存不進這個位置，請換一個地方再試一次。")
        }
    }

    private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, AirDropHandoff.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "選 Talkiie 匯出的詞庫檔（.json 或 .talkiiedict）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > PersonalDictionaryExchange.maxBytes {
            Self.alert("沒有匯入", PersonalDictionaryExchange.ImportError.tooLarge.message)
            return
        }
        guard url.isFileURL, let data = PersonalDictionaryExchange.readImportFile(atPath: url.path) else { Self.alert("沒有匯入", "打不開這個檔。"); return }
        switch PersonalDictionaryExchange.decode(data) {
        case .failure(let e):
            Self.alert("沒有匯入", e.message)
        case .success(let imported):
            let preview = PersonalDictionaryExchange.merge(imported, into: store.entries)
            guard preview.changesSomething else {
                Self.alert("沒有要改的", "檔案裡的詞這台 Mac 上都有了（略過 \(preview.skipped) 條）。")
                return
            }
            let confirm = NSAlert()
            confirm.messageText = "匯入詞庫？"
            confirm.informativeText = "新增 \(preview.added) 條、更新 \(preview.updated) 條"
                + (preview.skipped > 0 ? "、略過 \(preview.skipped) 條（已經有了、或不能用）" : "")
                + (preview.removed > 0 ? "、自動加入的詞超過上限，會移除最舊的 \(preview.removed) 條" : "")
                + "。更新 = 同一個「聽成」換成檔案裡的。"
            confirm.addButton(withTitle: "匯入")
            confirm.addButton(withTitle: "取消")
            if confirm.runModal() == .alertFirstButtonReturn { store.importEntries(imported) }
        }
    }

    private static func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "好")
        a.runModal()
    }

    private func add() {
        guard !replacement.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.addTerms(replacement)
            replacement = ""
            adding = false
            return
        }
        if let p = store.add(heard: heard, replacement: replacement) {
            problem = p
        } else {
            heard = ""
            replacement = ""
            adding = false
        }
    }
}

@MainActor
private final class AirDropHandoff: NSObject, NSSharingServiceDelegate {
    static let contentType = UTType(filenameExtension: PersonalDictionaryExchange.fileExtension, conformingTo: .json) ?? .json
    private static let prefix = "TalkiieDictionaryAirDrop-"
    private static var current: AirDropHandoff?
    private let url: URL

    private init(url: URL) { self.url = url }

    static func write(_ data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let url = dir.appendingPathComponent(PersonalDictionaryExchange.airDropFileName)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func start(_ service: NSSharingService, url: URL) {
        let handoff = AirDropHandoff(url: url)
        current = handoff
        service.delegate = handoff
        service.perform(withItems: [url])
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    static func removeLeftovers() {
        let tmp = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: tmp.path)) ?? []
        for name in names where name.hasPrefix(prefix) && current?.url.deletingLastPathComponent().lastPathComponent != name {
            try? FileManager.default.removeItem(at: tmp.appendingPathComponent(name))
        }
    }

    private func finish() {
        Self.remove(url)
        if Self.current === self { Self.current = nil }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        MainActor.assumeIsolated { finish() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        MainActor.assumeIsolated { finish() }
    }
}
