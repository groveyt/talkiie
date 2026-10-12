import Foundation

public final class PersonalDictionaryFileStore: @unchecked Sendable {
    public static let folderName = "dictionary"
    public static let fileName = "entries.json"

    public let root: URL
    public var fileURL: URL { root.appendingPathComponent(Self.fileName) }
    private let queue = DispatchQueue(label: "personal-dictionary", qos: .userInitiated)

    public init(root: URL) {
        self.root = root
    }

    public enum Loaded: Equatable, Sendable {
        case missing
        case unreadable
        case ok([PersonalDictionary.Entry])

        public var entries: [PersonalDictionary.Entry] {
            if case .ok(let e) = self { return e }
            return []
        }
    }

    public func load() -> Loaded {
        queue.sync { loadLocked() }
    }

    @discardableResult
    public func save(_ entries: [PersonalDictionary.Entry]) -> Bool {
        queue.sync {
            if case .unreadable = loadLocked() { return false }
            guard ensureRoot() else { return false }
            return replace(fileURL, PersonalDictionaryExchange.export(entries))
        }
    }

    @discardableResult
    public func deleteAll() -> Bool {
        queue.sync {
            var st = stat()
            guard lstat(root.path, &st) == 0 else { return errno == ENOENT }
            if (st.st_mode & S_IFMT) == S_IFLNK { return unlink(root.path) == 0 }
            do {
                try FileManager.default.removeItem(at: root)
                return true
            } catch {
                return Self.mode(fileURL.path) == nil
            }
        }
    }

    @discardableResult
    public static func removeReceivedCopy(_ url: URL, inbox: URL) -> Bool {
        let prefix = inbox.standardizedFileURL.path + "/"
        guard url.isFileURL, url.standardizedFileURL.path.hasPrefix(prefix) else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }

    private static func mode(_ path: String) -> mode_t? {
        var st = stat()
        return lstat(path, &st) == 0 ? st.st_mode : nil
    }

    private func loadLocked() -> Loaded {
        guard let m = Self.mode(fileURL.path) else { return .missing }
        guard (m & S_IFMT) == S_IFREG, let data = FileManager.default.contents(atPath: fileURL.path),
              case .success(let entries) = PersonalDictionaryExchange.decode(data) else { return .unreadable }
        return .ok(entries)
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
}
