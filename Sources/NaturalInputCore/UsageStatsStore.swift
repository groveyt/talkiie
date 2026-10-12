import Foundation

public final class UsageStatsStore: @unchecked Sendable {
    public let root: URL
    private let calendar: Calendar
    private let queue = DispatchQueue(label: "usage-stats", qos: .utility)
    private var minimumEpoch = 0

    public init(root: URL, calendar: Calendar = UsageStatsLayout.calendar()) {
        self.root = root
        self.calendar = calendar
    }

    @discardableResult
    public func record(_ round: UsageRound, switchSetting: Any?, epoch: Int = 0, now: Date = Date()) -> Bool {
        guard UsageStats.recordingEnabled(fromDefaults: switchSetting) else { return true }
        return record(round, epoch: epoch, now: now)
    }

    @discardableResult
    func record(_ round: UsageRound, epoch: Int = 0, now: Date = Date()) -> Bool {
        queue.sync {
            guard epoch >= minimumEpoch else { return true }
            guard ensureRoot() else { return false }
            let url = root.appendingPathComponent(UsageStatsLayout.fileName(for: now, calendar: calendar))
            var day: UsageDay
            switch readDay(url) {
            case .missing: day = UsageDay(dayStart: calendar.startOfDay(for: now))
            case .unreadable: return false
            case .ok(let d): day = d
            }
            day.record(round)
            guard let data = try? day.jsonData() else { return false }
            let ok = replace(url, data)
            _ = pruneLocked(now: now)
            return ok
        }
    }

    public func days(lastDays: Int, now: Date = Date()) -> [UsageDay] {
        queue.sync {
            let today = calendar.startOfDay(for: now)
            guard lastDays > 0, Self.isDirectory(root.path),
                  let first = calendar.date(byAdding: .day, value: -(lastDays - 1), to: today) else { return [] }
            var out: [UsageDay] = []
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
                guard let start = UsageStatsLayout.dayStart(fileName: name, calendar: calendar),
                      start >= first, start <= today,
                      case .ok(let day) = readDay(root.appendingPathComponent(name)) else { continue }
                out.append(day)
            }
            return out.sorted { $0.dayStart < $1.dayStart }
        }
    }

    @discardableResult
    public func prune(now: Date = Date()) -> Int {
        queue.sync { pruneLocked(now: now) }
    }

    @discardableResult
    public func deleteAll(dropRecordsBefore epoch: Int = 0) -> Bool {
        queue.sync {
            minimumEpoch = max(minimumEpoch, epoch)
            var st = stat()
            guard lstat(root.path, &st) == 0 else { return errno == ENOENT }
            if (st.st_mode & S_IFMT) == S_IFLNK { return unlink(root.path) == 0 }
            do {
                try FileManager.default.removeItem(at: root)
                return true
            } catch {
                return !hasDayFilesLocked()
            }
        }
    }

    private enum Read { case missing, unreadable, ok(UsageDay) }

    private static func mode(_ path: String) -> mode_t? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_mode : nil
    }

    private static func isDirectory(_ path: String) -> Bool {
        mode(path).map { ($0 & S_IFMT) == S_IFDIR } ?? false
    }

    private func hasDayFilesLocked() -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else {
            return Self.mode(root.path) != nil
        }
        return names.contains { UsageStatsLayout.dayStart(fileName: $0, calendar: calendar) != nil }
    }

    private func readDay(_ url: URL) -> Read {
        guard let m = Self.mode(url.path) else { return .missing }
        guard (m & S_IFMT) == S_IFREG, let data = FileManager.default.contents(atPath: url.path),
              let day = UsageDay.decode(data) else { return .unreadable }
        return .ok(day)
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
            chmod(root.path, 0o700)
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

    private func replace(_ url: URL, _ data: Data) -> Bool {
        let tmp = root.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString.prefix(8))")
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard fd >= 0 else { return false }
        let ok = fchmod(fd, 0o600) == 0 && Self.writeAll(fd, data) && fsync(fd) == 0
        close(fd)
        guard ok, rename(tmp.path, url.path) == 0 else { unlink(tmp.path); return false }
        return true
    }

    private func pruneLocked(now: Date) -> Int {
        guard Self.isDirectory(root.path) else { return 0 }
        var removed = 0
        for name in (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? [] {
            let path = root.appendingPathComponent(name).path
            guard let m = Self.mode(path), (m & S_IFMT) == S_IFREG,
                  UsageStatsLayout.isExpired(fileName: name, now: now, calendar: calendar) else { continue }
            if unlink(path) == 0 { removed += 1 }
        }
        return removed
    }
}
