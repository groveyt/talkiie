import AppKit
import Darwin
import Foundation
import NaturalInputCore
import SwiftUI

@MainActor
final class EditCaptureSettings: ObservableObject {
    static let shared = EditCaptureSettings()

    static var isEnabled: Bool {
        #if DEBUG
        if let debugOverride { return debugOverride }
        #endif
        return UserDefaults.standard.bool(forKey: EditCaptureSettingsKey.enabled)
    }

    static var retention: CorrectionRetention {
        CorrectionRetention(fromDefaults: UserDefaults.standard.string(forKey: EditCaptureSettingsKey.retention))
    }

    static var shortcut: EditCaptureShortcut {
        EditCaptureShortcut(fromDefaults: UserDefaults.standard.string(forKey: EditCaptureShortcut.defaultsKey))
    }

    @Published private(set) var enabled = EditCaptureSettings.isEnabled
    @Published private(set) var shortcut = EditCaptureSettings.shortcut
    @Published private(set) var retention = EditCaptureSettings.retention

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: EditCaptureSettingsKey.enabled)
        enabled = Self.isEnabled
        if !enabled { EditCaptureController.shared.forget() }
        AppModel.shared.syncEditCaptureKey()
    }

    func setShortcut(_ new: EditCaptureShortcut) {
        UserDefaults.standard.set(new.rawValue, forKey: EditCaptureShortcut.defaultsKey)
        shortcut = new
        AppModel.shared.syncEditCaptureKey()
    }

    func setRetention(_ r: CorrectionRetention) {
        UserDefaults.standard.set(r.rawValue, forKey: EditCaptureSettingsKey.retention)
        retention = r
        EditCorrectionStore.shared.prune(r)
    }

    #if DEBUG
    static var debugOverride: Bool? = nil
    func debugRefresh() { enabled = Self.isEnabled }
    #endif
}

@MainActor
final class EditCaptureController {
    static let shared = EditCaptureController()

    private(set) var lastInsertion: InsertionRecord?
    private var capturing = false

    func makeTrace() -> TranscriptDelivery.Trace? {
        EditCaptureSettings.isEnabled ? TranscriptDelivery.Trace() : nil
    }

    func deliveryFinished(_ outcome: TranscriptDelivery.Outcome, trace: TranscriptDelivery.Trace?) {
        if case .busy = outcome { return }
        guard EditCaptureSettings.isEnabled, case .inserted = outcome else { lastInsertion = nil; return }
        lastInsertion = trace?.record
    }

    func forget() { lastInsertion = nil }

    @discardableResult
    func pressed(inserting: Bool) -> EditCaptureRefusal? {
        let consented = ConsentStore.allowsCapture
        if !consented { ConsentWindow.shared.presentIfNeeded() }
        guard let permit = EditCaptureGate.press(enabled: EditCaptureSettings.isEnabled && consented) else {
            return report(.refused(.disabled))
        }
        guard !inserting, !capturing else { return report(.refused(.insertionInProgress)) }
        capturing = true
        let record = lastInsertion
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                EditReadback.capture(permit: permit, record: record, inspector: LiveFocusInspector(),
                                     reader: LiveFieldTextReader())
            }.value
            self.capturing = false
            self.finish(outcome)
        }
        return nil
    }

    private func finish(_ outcome: EditCaptureOutcome) {
        guard case .captured(let correction, let percent) = outcome else { report(outcome); return }
        guard EditCaptureSettings.isEnabled else { report(.refused(.disabledAfterRead)); return }
        let retention = EditCaptureSettings.retention
        Task {
            let saved = await EditCorrectionStore.shared.append(correction, retention: retention)
            if saved {
                Log.record(.editCapture(.saved(changed: correction.changed, alignedPercent: percent)))
                let learned = correction.changed
                    ? PersonalDictionaryStore.shared.learn(inserted: correction.inserted, edited: correction.edited)
                    : (added: 0, refreshed: 0, promptOnly: 0)
                if learned.added + learned.refreshed > 0 {
                    Log.record(.dictionaryLearned(added: learned.added, refreshed: learned.refreshed,
                                                  promptOnly: learned.promptOnly))
                }
                let notice = !correction.changed ? "已收下（這段沒有改動）"
                    : learned.added > 0 ? "已收下這次修改，\(learned.added) 個詞加進個人詞庫" : "已收下這次修改"
                RecordingHUD.showNotice(notice, seconds: 1.5)
            } else {
                self.report(.refused(.saveFailed))
            }
        }
    }

    @discardableResult
    private func report(_ outcome: EditCaptureOutcome) -> EditCaptureRefusal? {
        guard case .refused(let reason) = outcome else { return nil }
        Log.record(.editCapture(.refused(reason)))
        RecordingHUD.showNotice(reason.message, seconds: 2.5)
        return reason
    }
}

final class EditCorrectionStore: @unchecked Sendable {
    static var defaultRoot: URL {
        Edition.dataDirectory.appendingPathComponent(CorrectionLayout.folderName, isDirectory: true)
    }

    static let shared = EditCorrectionStore(root: defaultRoot)

    let root: URL
    private let queue = DispatchQueue(label: "edit-corrections", qos: .utility)

    init(root: URL) { self.root = root }

    func append(_ correction: EditCorrection, retention: CorrectionRetention, now: Date = Date()) async -> Bool {
        guard let encoded = try? correction.jsonLine() else { return false }
        return await appendEncoded(encoded, retention: retention, now: now)
    }

    func appendRevert(_ record: RewriteRevertRecord, retention: CorrectionRetention, now: Date = Date()) async -> Bool {
        guard let encoded = try? record.jsonLine() else { return false }
        return await appendEncoded(encoded, retention: retention, now: now)
    }

    private func appendEncoded(_ encoded: Data, retention: CorrectionRetention, now: Date) async -> Bool {
        await withCheckedContinuation { cont in
            queue.async {
                var line = encoded
                defer { line.resetBytes(in: 0..<line.count) }
                let ok = self.appendLine(line, now: now)
                _ = self.retention(retention, now: now)
                cont.resume(returning: ok)
            }
        }
    }

    func prune(_ retention: CorrectionRetention, now: Date = Date()) {
        queue.async {
            let n = self.retention(retention, now: now)
            if n > 0 { Log.record(.editCorrectionsPruned(files: n)) }
        }
    }

    func deleteAll() {
        queue.sync {
            var st = stat()
            guard lstat(root.path, &st) == 0 else { return }
            if (st.st_mode & S_IFMT) == S_IFLNK { unlink(root.path) } else { try? FileManager.default.removeItem(at: root) }
        }
        Log.record(.editCorrectionsDeleted)
    }

    func flush() { queue.sync {} }

    func readAll() -> [EditCorrection] {
        queue.sync {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return [] }
            var out: [EditCorrection] = []
            for name in names.sorted() where CorrectionLayout.dayStart(fileName: name) != nil {
                let url = root.appendingPathComponent(name)
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      attrs[.type] as? FileAttributeType == .typeRegular,
                      let data = FileManager.default.contents(atPath: url.path) else { continue }
                for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
                    if let c = EditCorrection.decode(line: Data(line)) { out.append(c) }
                }
            }
            return out
        }
    }

    func runRetentionNow(_ r: CorrectionRetention, now: Date) -> Int { queue.sync { retention(r, now: now) } }

    private static func mode(_ path: String) -> mode_t? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_mode : nil
    }

    private func ensureRoot() -> Bool {
        if let m = Self.mode(root.path) {
            guard (m & S_IFMT) == S_IFDIR else { return false }
            if m & 0o777 != 0o700 { chmod(root.path, 0o700) }
        } else {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            } catch { return false }
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = root
        try? url.setResourceValues(values)
        return true
    }

    private static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return buf.count == 0 }
            var done = 0
            while done < buf.count {
                let n = write(fd, base + done, buf.count - done)
                if n < 0 { if errno == EINTR { continue }; return false }
                done += n
            }
            return true
        }
    }

    private func appendLine(_ line: Data, now: Date) -> Bool {
        guard ensureRoot() else { return false }
        let file = root.appendingPathComponent(CorrectionLayout.fileName(for: now))
        let fd = open(file.path, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG, fchmod(fd, 0o600) == 0 else { return false }
        return Self.writeAll(fd, line) && fsync(fd) == 0
    }

    private func retention(_ r: CorrectionRetention, now: Date) -> Int {
        guard let m = Self.mode(root.path), (m & S_IFMT) == S_IFDIR else { return 0 }
        var touched = 0
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
            let url = root.appendingPathComponent(name)
            guard let fm = Self.mode(url.path), (fm & S_IFMT) == S_IFREG else { continue }
            switch r.action(forFile: name, now: now) {
            case .keep:
                continue
            case .delete:
                if unlink(url.path) == 0 { touched += 1 }
            case .filter(let cutoff):
                guard var data = FileManager.default.contents(atPath: url.path) else { continue }
                var kept = CorrectionRetention.retainedLines(data, cutoff: cutoff)
                defer { data.resetBytes(in: 0..<data.count); kept.resetBytes(in: 0..<kept.count) }
                guard kept.count != data.count else { continue }
                if kept.isEmpty {
                    if unlink(url.path) == 0 { touched += 1 }
                } else if rewrite(url, kept) {
                    touched += 1
                }
            }
        }
        return touched
    }

    private func rewrite(_ url: URL, _ data: Data) -> Bool {
        let tmp = root.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { return false }
        let ok = fchmod(fd, 0o600) == 0 && Self.writeAll(fd, data) && fsync(fd) == 0
        close(fd)
        guard ok, rename(tmp.path, url.path) == 0 else { unlink(tmp.path); return false }
        return true
    }
}

struct EditCaptureSettingsSection: View {
    @ObservedObject var settings = EditCaptureSettings.shared
    @EnvironmentObject var model: AppModel

    var body: some View {
        EditCaptureToggleRow()
        VStack(alignment: .leading, spacing: 4) {
            Picker("收下修改的快捷鍵", selection: Binding(get: { settings.shortcut }, set: { settings.setShortcut($0) })) {
                ForEach(EditCaptureShortcut.allCases, id: \.self) { s in
                    Text(s.label).tag(s)
                }
            }
            DefaultHint(defaultTitle: EditCaptureShortcut.defaultValue.label,
                        isDefault: settings.shortcut == EditCaptureShortcut.defaultValue) {
                settings.setShortcut(EditCaptureShortcut.defaultValue)
            }
        }
        .disabled(!settings.enabled)
        if let caveat = settings.shortcut.caveat {
            SettingsHelp(text: caveat, warn: true)
        }
        if settings.enabled, !model.editCaptureKeyRegistered {
            SettingsHelp(text: "\(settings.shortcut.label) 註冊失敗（可能被其他 app 佔用），目前無法收下。", warn: true)
        }
        VStack(alignment: .leading, spacing: 4) {
            Picker("修改紀錄保留", selection: Binding(get: { settings.retention }, set: { settings.setRetention($0) })) {
                ForEach(CorrectionRetention.allCases, id: \.self) { r in
                    Text(r.title).tag(r)
                }
            }
            DefaultHint(defaultTitle: CorrectionRetention.defaultValue.title,
                        isDefault: settings.retention == CorrectionRetention.defaultValue) {
                settings.setRetention(CorrectionRetention.defaultValue)
            }
        }
        Edition.CorrectionsSendRow()
        HStack {
            Button("打開資料夾") { EditCorrectionMenuActions.openFolder() }
            Spacer()
            Button(role: .destructive) { EditCorrectionMenuActions.confirmDeleteAll() } label: {
                Text("刪除全部修改紀錄…").foregroundStyle(.red)
            }
        }
    }
}

struct EditCaptureToggleRow: View {
    @ObservedObject var settings = EditCaptureSettings.shared

    static func actionLine(shortcut: EditCaptureShortcut) -> String {
        "改完剛打出來的字後按 \(shortcut.label)，Talkiie 會學起來；聽錯的字會自動加進個人詞庫（設定 › 文字）。"
    }

    static var privacyLine: String {
        if Edition.offersCorrectionsSend, let line = Edition.Copy.correctionsSendPrivacyLine { return line }
        return "只讀一次那段文字、只存在這台 Mac，不送出；沒按就什麼都不讀。"
    }

    static func help(shortcut: EditCaptureShortcut) -> String { actionLine(shortcut: shortcut) + privacyLine }

    var body: some View {
        Toggle(isOn: Binding(get: { settings.enabled }, set: { settings.setEnabled($0) })) {
            VStack(alignment: .leading, spacing: 3) {
                Text("收集我的修改")
                Text(Self.actionLine(shortcut: settings.shortcut))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Label(Self.privacyLine, systemImage: "lock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor
enum EditCorrectionMenuActions {
    static func openFolder() {
        let root = EditCorrectionStore.shared.root
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue {
            NSWorkspace.shared.open(root)
        } else {
            RecordingHUD.showNotice("還沒有修改紀錄（打開收集、按 \(EditCaptureSettings.shortcut.label) 收下之後才會建立）")
        }
    }

    static func confirmDeleteAll() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "刪除全部修改紀錄？"
        alert.informativeText = "會刪除 Application Support/\(Edition.dataDirectory.lastPathComponent)/\(CorrectionLayout.folderName) 裡所有「插入 → 改後」的紀錄，無法復原。"
        alert.addButton(withTitle: "刪除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        EditCorrectionStore.shared.deleteAll()
        RecordingHUD.showNotice("修改紀錄已全部刪除", seconds: 2)
    }
}
