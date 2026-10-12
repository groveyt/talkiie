import Foundation

protocol ModelArchiveExtracting: Sendable {
    func extract(zip: URL, expectingTop top: String, into directory: URL) throws
}

struct ZipExtractor: ModelArchiveExtracting {
    enum Failure: Error, Equatable {
        case unreadable
        case rejectedEntry
        case extract
    }

    func extract(zip: URL, expectingTop top: String, into directory: URL) throws {
        try ZipCentralDirectory.validate(zip, top: top)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", "--norsrc", "--noextattr", "--noacl", zip.path, directory.path]
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { throw Failure.extract }
        p.waitUntilExit()
        guard p.terminationReason == .exit, p.terminationStatus == 0 else { throw Failure.extract }
    }
}

enum ZipCentralDirectory {
    struct Entry: Equatable {
        let name: String
        let unixMode: UInt32?
    }

    static let maxCentralDirectoryBytes: UInt64 = 16 << 20

    static func validate(_ url: URL, top: String) throws {
        let entries = try read(url)
        guard !entries.isEmpty else { throw ZipExtractor.Failure.rejectedEntry }
        for e in entries where !isAllowed(e, top: top) {
            throw ZipExtractor.Failure.rejectedEntry
        }
    }

    static func isAllowed(_ e: Entry, top: String) -> Bool {
        let n = e.name
        guard !n.isEmpty, !n.hasPrefix("/"), !n.contains("\\"), !n.contains("\0") else { return false }
        let parts = n.split(separator: "/", omittingEmptySubsequences: false)
        let body = n.hasSuffix("/") ? parts.dropLast() : parts[...]
        guard !body.isEmpty, body.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        guard body.first.map(String.init) == top else { return false }
        if let mode = e.unixMode {
            let type = mode & 0o170000
            guard type == 0 || type == 0o100000 || type == 0o040000 else { return false }
        }
        return true
    }

    static func read(_ url: URL) throws -> [Entry] {
        let fd = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw ZipExtractor.Failure.unreadable }
        let h = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            let size = try h.seekToEnd()
            guard size >= 22 else { throw ZipExtractor.Failure.unreadable }
            let tailLen = min(size, 22 + 65_535)
            let tail = try readAt(h, offset: size - tailLen, count: Int(tailLen))
            guard let eocd = lastIndex(of: [0x50, 0x4b, 0x05, 0x06], in: tail, from: tail.count - 22) else {
                throw ZipExtractor.Failure.unreadable
            }
            var count = UInt64(le16(tail, eocd + 10))
            var cdSize = UInt64(le32(tail, eocd + 12))
            var cdOffset = UInt64(le32(tail, eocd + 16))
            if count == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
                let locPos = eocd - 20
                guard locPos >= 0, le32(tail, locPos) == 0x0706_4b50 else { throw ZipExtractor.Failure.unreadable }
                let z64Offset = le64(tail, locPos + 8)
                guard z64Offset + 56 <= size else { throw ZipExtractor.Failure.unreadable }
                let z = try readAt(h, offset: z64Offset, count: 56)
                guard le32(z, 0) == 0x0606_4b50 else { throw ZipExtractor.Failure.unreadable }
                count = le64(z, 32)
                cdSize = le64(z, 40)
                cdOffset = le64(z, 48)
            }
            guard cdSize <= maxCentralDirectoryBytes, cdOffset + cdSize <= size, count <= cdSize / 46 + 1 else {
                throw ZipExtractor.Failure.unreadable
            }
            let cd = try readAt(h, offset: cdOffset, count: Int(cdSize))
            var entries: [Entry] = []
            var p = 0
            for _ in 0..<count {
                guard p + 46 <= cd.count, le32(cd, p) == 0x0201_4b50 else { throw ZipExtractor.Failure.unreadable }
                let madeBy = le16(cd, p + 4)
                let nameLen = Int(le16(cd, p + 28)), extraLen = Int(le16(cd, p + 30)), commentLen = Int(le16(cd, p + 32))
                let external = le32(cd, p + 38)
                guard p + 46 + nameLen + extraLen + commentLen <= cd.count,
                      let name = String(data: cd.subdata(in: (p + 46)..<(p + 46 + nameLen)), encoding: .utf8)
                else { throw ZipExtractor.Failure.unreadable }
                entries.append(Entry(name: name, unixMode: (madeBy >> 8) == 3 ? external >> 16 : nil))
                p += 46 + nameLen + extraLen + commentLen
            }
            return entries
        } catch let e as ZipExtractor.Failure {
            throw e
        } catch {
            throw ZipExtractor.Failure.unreadable
        }
    }

    private static func readAt(_ h: FileHandle, offset: UInt64, count: Int) throws -> Data {
        try h.seek(toOffset: offset)
        guard let d = try h.read(upToCount: count), d.count == count else { throw ZipExtractor.Failure.unreadable }
        return d
    }

    private static func lastIndex(of sig: [UInt8], in d: Data, from start: Int) -> Int? {
        var i = start
        while i >= 0 {
            if d[d.startIndex + i] == sig[0], d[d.startIndex + i + 1] == sig[1],
               d[d.startIndex + i + 2] == sig[2], d[d.startIndex + i + 3] == sig[3] { return i }
            i -= 1
        }
        return nil
    }

    private static func le16(_ d: Data, _ o: Int) -> UInt16 {
        UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8
    }
    private static func le32(_ d: Data, _ o: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(d[d.startIndex + o + $1]) << (8 * UInt32($1)) }
    }
    private static func le64(_ d: Data, _ o: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(d[d.startIndex + o + $1]) << (8 * UInt64($1)) }
    }
}
