import AppKit
import Charts
import NaturalInputCore
import SwiftUI

@MainActor
enum UsageStatsRecorder {
    static let store = UsageStatsStore(
        root: Edition.dataDirectory.appendingPathComponent(UsageStatsLayout.folderName, isDirectory: true))

    static var enabled = true

    private(set) static var epoch = 0

    static func record(_ round: UsageRound) {
        guard enabled else { return }
        let store = self.store, epoch = self.epoch
        let switchSetting = UserDefaults.standard.object(forKey: UsageStats.recordingDefaultsKey) as? Bool
        DispatchQueue.global(qos: .utility).async {
            let ok = store.record(round, switchSetting: switchSetting, epoch: epoch)
            Task { @MainActor in
                if !ok { Log.record(.usageStatsWriteFailed) }
                UsageStatsModel.shared.roundRecorded()
            }
        }
    }

    @discardableResult
    static func deleteAll() -> Bool {
        epoch += 1
        return store.deleteAll(dropRecordsBefore: epoch)
    }

    static func launchMaintenance() {
        let store = self.store
        DispatchQueue.global(qos: .utility).async {
            let n = store.prune()
            if n > 0 { Task { @MainActor in Log.record(.usageStatsPruned(files: n)) } }
        }
    }
}

@MainActor
final class UsageStatsModel: ObservableObject {
    static let shared = UsageStatsModel()

    @Published private(set) var days: [UsageDay] = []
    @Published private(set) var now = Date()
    private var visible = false

    func appeared() { visible = true; reload() }
    func disappeared() { visible = false }

    fileprivate func roundRecorded() { if visible { reload() } }

    private var reloadToken = 0

    func reload() {
        #if DEBUG
        if sampleOnly { return }
        #endif
        let store = UsageStatsRecorder.store
        reloadToken += 1
        let token = reloadToken
        DispatchQueue.global(qos: .userInitiated).async {
            let now = Date()
            let days = store.days(lastDays: UsageStats.retentionDays, now: now)
            Task { @MainActor in
                guard token == self.reloadToken else { return }
                self.now = now
                self.days = days
            }
        }
    }

    #if DEBUG
    private var sampleOnly = false
    func useSample(now: Date = Date()) {
        sampleOnly = true
        self.now = now
        days = Self.sampleDays(now: now)
    }

    static func sampleDays(now: Date) -> [UsageDay] {
        let cal = UsageStatsLayout.calendar()
        let today = cal.startOfDay(for: now)
        var out: [UsageDay] = []
        for back in 0..<100 {
            guard back == 0 || (back % 9 != 4 && back % 13 != 7), let start = cal.date(byAdding: .day, value: -back, to: today) else { continue }
            var day = UsageDay(dayStart: start)
            let rounds = back == 0 ? 29 : 3 + (back * 7) % 14
            for r in 0..<rounds {
                let chars = back == 0 ? 243 : 25 + (back * 13 + r * 29) % 90
                day.record(UsageRound(result: .inserted, characters: chars,
                                      recordingMillis: back == 0 ? 27_000 : 9_000 + (r * 1700) % 10_000,
                                      stopToFirstKeystrokeMillis: 1_100 + (r * 90) % 500,
                                      stopToTextMillis: 1_200 + (r * 70) % 400))
            }
            if back % 5 == 1 { day.record(UsageRound(result: .failed, recordingMillis: 4_000)) }
            if back % 4 == 2 { day.record(UsageRound(result: .notInserted, recordingMillis: 6_000, stopToTextMillis: 1_500)) }
            if back % 3 == 0 { day.record(UsageRound(result: .cancelled)) }
            out.append(day)
        }
        return out.sorted { $0.dayStart < $1.dayStart }
    }
    #endif

    func confirmDeleteAll() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "刪除全部統計？"
        alert.informativeText = "會刪除 Application Support/\(Edition.dataDirectory.lastPathComponent)/\(UsageStatsLayout.folderName) 裡所有的使用統計（只有次數、字數與時間），無法復原。之後的口述會重新開始累計。"
        alert.addButton(withTitle: "刪除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let deleted = UsageStatsRecorder.deleteAll()
        if deleted { Log.record(.usageStatsDeleted) }
        reload()
        if !deleted {
            let failed = NSAlert()
            failed.alertStyle = .warning
            failed.messageText = "沒有刪乾淨，請再試一次"
            failed.addButton(withTitle: "好")
            failed.runModal()
        }
    }
}
