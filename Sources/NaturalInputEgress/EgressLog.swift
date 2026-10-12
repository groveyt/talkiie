import CryptoKit
import Foundation
import NaturalInputCore

public protocol EgressSpeakerTag: Sendable {
    var egressLogValue: String { get }
}

public final class EgressLog: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let ts: Date
        public let kind: String
        public let endpoint: String
        public let payloadBytes: Int
        public let payloadSHA256: String
        public var receivedBytes: Int64? = nil
        public var outcome: String? = nil
        public var durationMillis: Int? = nil
        public var attempt: String? = nil
        public var speaker: String? = nil

        enum CodingKeys: String, CodingKey {
            case ts, kind, endpoint
            case payloadBytes = "payload_bytes"
            case payloadSHA256 = "payload_sha256"
            case receivedBytes = "received_bytes"
            case outcome
            case durationMillis = "duration_ms"
            case attempt
            case speaker
        }
    }

    public enum Attempt: String, Sendable {
        case speculative
        case warmUp
        case ready
        case retry
    }

    public enum Outcome: String, Sendable {
        case started, succeeded, failed
    }

    public enum Failure: Error, Equatable, Sendable {
        case directory(errno: Int32)
        case open(errno: Int32)
        case write(errno: Int32)
        case fsync(errno: Int32)
        case prune
    }

    public static let retention: TimeInterval = 7 * 24 * 60 * 60
    public static let fileName = "egress.jsonl"

    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(directory: URL,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.now = now
    }

    public func record(kind: EgressKind, endpoint: URL, payload: Data, attempt: Attempt? = nil,
                       speaker: (any EgressSpeakerTag)? = nil) throws {
        var entry = Entry(ts: now(), kind: kind.rawValue, endpoint: endpoint.absoluteString,
                          payloadBytes: payload.count,
                          payloadSHA256: Self.sha256Hex(payload))
        entry.attempt = attempt?.rawValue
        entry.speaker = speaker?.egressLogValue
        try append(entry)
    }

    public func recordTransfer(kind: EgressKind, endpoint: URL, outcome: Outcome,
                               receivedBytes: Int64, durationMillis: Int?) throws {
        var entry = Entry(ts: now(), kind: kind.rawValue, endpoint: endpoint.absoluteString,
                          payloadBytes: 0, payloadSHA256: Self.sha256Hex(Data()))
        entry.receivedBytes = receivedBytes
        entry.outcome = outcome.rawValue
        entry.durationMillis = durationMillis
        try append(entry)
    }

    private func append(_ entry: Entry) throws {
        lock.lock(); defer { lock.unlock() }
        try ensureDirectory()
        try pruneLocked()
        var line = try Self.encoder.encode(entry)
        line.append(0x0A)
        try appendAndSync(line)
    }

    public func prune() throws {
        lock.lock(); defer { lock.unlock() }
        try pruneLocked()
    }

    public func entries() throws -> [Entry] {
        lock.lock(); defer { lock.unlock() }
        return try readLocked().compactMap { try? Self.decoder.decode(Entry.self, from: $0) }
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func ensureDirectory() throws {
        let path = directory.path
        if mkdir(path, 0o700) != 0 && errno != EEXIST {
            do {
                try FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
            } catch {
                throw Failure.directory(errno: errno)
            }
        }
        var st = stat()
        guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
            throw Failure.directory(errno: ENOTDIR)
        }
        if chmod(path, 0o700) != 0 { throw Failure.directory(errno: errno) }
    }

    private func readLocked() throws -> [Data] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        return data.split(separator: 0x0A).map { Data($0) }
    }

    private func pruneLocked() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let lines: [Data]
        do { lines = try readLocked() } catch { throw Failure.prune }
        let cutoff = now().addingTimeInterval(-Self.retention)
        let kept = lines.filter { line in
            guard let e = try? Self.decoder.decode(Entry.self, from: line) else { return false }
            return e.ts >= cutoff
        }
        guard kept.count != lines.count else { return }

        var out = Data()
        for line in kept { out.append(line); out.append(0x0A) }
        let tmp = directory.appendingPathComponent(Self.fileName + ".tmp")
        try write(out, to: tmp, flags: O_WRONLY | O_CREAT | O_TRUNC)
        guard rename(tmp.path, fileURL.path) == 0 else { throw Failure.prune }
        syncDirectory()
    }

    private func appendAndSync(_ line: Data) throws {
        let existed = FileManager.default.fileExists(atPath: fileURL.path)
        try write(line, to: fileURL, flags: O_WRONLY | O_CREAT | O_APPEND)
        if !existed { syncDirectory() }
    }

    private func write(_ data: Data, to url: URL, flags: Int32) throws {
        let fd = open(url.path, flags | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw Failure.open(errno: errno) }
        defer { close(fd) }
        guard fchmod(fd, 0o600) == 0 else { throw Failure.open(errno: errno) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    throw Failure.write(errno: errno)
                }
                offset += n
            }
        }
        guard Self.fullSync(fd) else { throw Failure.fsync(errno: errno) }
    }

    private func syncDirectory() {
        let fd = open(directory.path, O_RDONLY)
        guard fd >= 0 else { return }
        _ = Self.fullSync(fd)
        close(fd)
    }

    private static func fullSync(_ fd: Int32) -> Bool {
        if fcntl(fd, F_FULLFSYNC) == 0 { return true }
        return fsync(fd) == 0
    }
}
