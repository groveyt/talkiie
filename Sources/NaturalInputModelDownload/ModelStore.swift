import CryptoKit
import Foundation
import NaturalInputEgress

struct ModelStore: Sendable {
    static let receiptName = ".talkiie-model-receipt.json"

    let root: URL

    var staging: URL { root.appendingPathComponent(".staging", isDirectory: true) }
    var lockFile: URL { staging.appendingPathComponent(".lock") }

    func partialFile(for f: ModelFile, of a: ModelArtifact) -> URL {
        staging.appendingPathComponent("\(a.id)-\(a.version)-\(f.name).partial")
    }

    func finalDirectory(for a: ModelArtifact) -> URL {
        root.appendingPathComponent("\(a.id)-\(a.version)", isDirectory: true)
    }

    enum Failure: Error, Equatable, Sendable {
        case fileSystem
        case contentsInvalid
    }

    struct Receipt: Codable, Equatable {
        struct File: Codable, Equatable {
            let name: String
            let sha256: String
        }
        let id: String
        let version: String
        let files: [File]

        init(_ a: ModelArtifact) {
            id = a.id
            version = a.version
            files = a.files.map { File(name: $0.name, sha256: $0.sha256) }
        }
    }

    func prepareStaging() throws {
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            throw Failure.fileSystem
        }
    }

    func placeRaw(_ partial: URL, as name: String, in dir: URL) throws {
        guard link(partial.path, dir.appendingPathComponent(name).path) == 0 else { throw Failure.fileSystem }
    }

    func makeWorkDirectory() throws -> URL {
        try prepareStaging()
        let dir = staging.appendingPathComponent("extract-\(UUID().uuidString)", isDirectory: true)
        guard mkdir(dir.path, 0o755) == 0 else { throw Failure.fileSystem }
        return dir
    }

    func removeStaleWorkDirectories() {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: staging.path) else { return }
        for name in items where name.hasPrefix("extract-") || name.hasPrefix("replaced-") {
            try? FileManager.default.removeItem(at: staging.appendingPathComponent(name))
        }
    }

    func tryLock() throws -> Int32? {
        try prepareStaging()
        let fd = open(lockFile.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.fileSystem }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return nil
        }
        return fd
    }

    func releaseLock(_ fd: Int32) {
        flock(fd, LOCK_UN)
        close(fd)
    }

    static func availableCapacity(at url: URL) throws -> Int64 {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path) && probe.pathComponents.count > 1 {
            probe = probe.deletingLastPathComponent()
        }
        let values = try probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let cap = values.volumeAvailableCapacityForImportantUsage else { throw Failure.fileSystem }
        return cap
    }

    static func sha256Hex(of url: URL) throws -> String {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.fileSystem }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var hasher = SHA256()
        while true {
            let chunk: Data?
            do { chunk = try handle.read(upToCount: 8 << 20) } catch { throw Failure.fileSystem }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func validateContents(of dir: URL, for a: ModelArtifact) throws {
        let fm = FileManager.default
        guard let top = try? fm.contentsOfDirectory(atPath: dir.path) else { throw Failure.contentsInvalid }
        guard Set(top) == Set(a.contents) else { throw Failure.contentsInvalid }
        guard let walker = fm.enumerator(atPath: dir.path) else { throw Failure.contentsInvalid }
        while let rel = walker.nextObject() as? String {
            var st = stat()
            guard lstat(dir.appendingPathComponent(rel).path, &st) == 0 else { throw Failure.contentsInvalid }
            let type = st.st_mode & S_IFMT
            guard type == S_IFREG || type == S_IFDIR else { throw Failure.contentsInvalid }
        }
    }

    func writeReceipt(in dir: URL, for a: ModelArtifact) throws {
        let receipt = Receipt(a)
        guard let data = try? JSONEncoder().encode(receipt) else { throw Failure.fileSystem }
        let path = dir.appendingPathComponent(Self.receiptName).path
        let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o644)
        guard fd >= 0 else { throw Failure.fileSystem }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            throw Failure.fileSystem
        }
    }

    func commit(_ workDir: URL, as a: ModelArtifact) throws {
        let final = finalDirectory(for: a)
        if renamex_np(workDir.path, final.path, UInt32(RENAME_EXCL)) == 0 {
            syncDirectory(root)
            return
        }
        guard errno == EEXIST else { throw Failure.fileSystem }
        let aside = staging.appendingPathComponent("replaced-\(UUID().uuidString)", isDirectory: true)
        guard rename(final.path, aside.path) == 0 else { throw Failure.fileSystem }
        guard renamex_np(workDir.path, final.path, UInt32(RENAME_EXCL)) == 0 else { throw Failure.fileSystem }
        syncDirectory(root)
        try? FileManager.default.removeItem(at: aside)
    }

    func isInstalled(_ a: ModelArtifact) -> Bool {
        let final = finalDirectory(for: a)
        var st = stat()
        guard lstat(final.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else { return false }
        let receiptURL = final.appendingPathComponent(Self.receiptName)
        guard lstat(receiptURL.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
              let handle = FileHandle(forReadingAtPath: receiptURL.path),
              let data = try? handle.readToEnd(),
              let receipt = try? JSONDecoder().decode(Receipt.self, from: data),
              receipt == Receipt(a)
        else { return false }
        guard let top = try? FileManager.default.contentsOfDirectory(atPath: final.path),
              Set(top) == Set(a.contents + [Self.receiptName]) else { return false }
        return true
    }

    private func syncDirectory(_ dir: URL) {
        let fd = open(dir.path, O_RDONLY | O_CLOEXEC)
        guard fd >= 0 else { return }
        if fcntl(fd, F_FULLFSYNC) != 0 { _ = fsync(fd) }
        close(fd)
    }
}
