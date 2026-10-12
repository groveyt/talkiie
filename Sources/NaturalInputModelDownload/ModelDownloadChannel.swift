import Foundation
import NaturalInputEgress

final class ModelDownloadChannel: Sendable {
    enum Failure: Error, Equatable, Sendable {
        case notInManifest
        case logUnavailable
        case redirectRefused
        case httpStatus(Int)
        case unexpectedRange
        case sizeMismatch
        case interrupted
        case fileSystem
        case cancelled
    }

    static let fixedHeaders: [String: String] = [
        "User-Agent": "Talkiie",
        "Accept-Language": "en",
        "Accept-Encoding": "identity",
    ]

    private let log: EgressLog
    private let allowlist: [ModelArtifact]
    private let protocolClasses: [AnyClass]?

    convenience init(log: EgressLog) {
        self.init(log: log, allowlist: ModelManifest.artifacts, protocolClasses: nil)
    }

    init(log: EgressLog, allowlist: [ModelArtifact], protocolClasses: [AnyClass]?) {
        self.log = log
        self.allowlist = allowlist
        self.protocolClasses = protocolClasses
    }

    static func makeConfiguration(protocolClasses: [AnyClass]?) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        config.httpAdditionalHeaders = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        if let protocolClasses { config.protocolClasses = protocolClasses }
        return config
    }

    static func makeRequest(for file: ModelFile, resumingAt offset: Int64) -> URLRequest {
        var r = URLRequest(url: file.url)
        r.httpMethod = "GET"
        r.httpShouldHandleCookies = false
        r.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        for (name, value) in fixedHeaders { r.setValue(value, forHTTPHeaderField: name) }
        if offset > 0 { r.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        return r
    }

    func fetch(_ file: ModelFile, of artifact: ModelArtifact, into partial: URL,
               progress: @escaping @Sendable (Int64) -> Void) async throws -> Int64 {
        guard allowlist.contains(artifact), artifact.files.contains(file),
              ModelManifest.isWellFormed(artifact), !artifact.isPlaceholder else {
            throw Failure.notInManifest
        }
        let offset = Self.fileSize(partial) ?? 0
        guard offset < file.bytes else { throw Failure.sizeMismatch }

        do {
            try log.recordTransfer(kind: .modelDownload, endpoint: file.url, outcome: .started,
                                   receivedBytes: 0, durationMillis: nil)
        } catch {
            throw Failure.logUnavailable
        }

        let clock = ContinuousClock()
        let started = clock.now
        let delegate = FetchDelegate(partial: partial, offset: offset, expectedTotal: file.bytes,
                                     progress: progress)
        let session = URLSession(configuration: Self.makeConfiguration(protocolClasses: protocolClasses),
                                 delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: Self.makeRequest(for: file, resumingAt: offset))

        let result: Result<Int64, Failure> = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<Result<Int64, Failure>, Never>) in
                delegate.setContinuation(c)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }

        let millis = Self.millis(clock.now - started)
        switch result {
        case .success(let size):
            do {
                try log.recordTransfer(kind: .modelDownload, endpoint: file.url, outcome: .succeeded,
                                       receivedBytes: delegate.receivedBytes, durationMillis: millis)
            } catch {
                throw Failure.logUnavailable
            }
            return size
        case .failure(let failure):
            try? log.recordTransfer(kind: .modelDownload, endpoint: file.url, outcome: .failed,
                                    receivedBytes: delegate.receivedBytes, durationMillis: millis)
            throw failure
        }
    }

    static func fileSize(_ url: URL) -> Int64? {
        var st = stat()
        guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else { return nil }
        return Int64(st.st_size)
    }

    private static func millis(_ d: Duration) -> Int {
        let (s, atto) = d.components
        return Int(s) * 1000 + Int(atto / 1_000_000_000_000_000)
    }
}

private final class FetchDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let partial: URL
    private var offset: Int64
    private let expectedTotal: Int64
    private let progress: @Sendable (Int64) -> Void
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var failure: ModelDownloadChannel.Failure?
    private var continuation: CheckedContinuation<Result<Int64, ModelDownloadChannel.Failure>, Never>?
    private var finished: Result<Int64, ModelDownloadChannel.Failure>?

    init(partial: URL, offset: Int64, expectedTotal: Int64, progress: @escaping @Sendable (Int64) -> Void) {
        self.partial = partial
        self.offset = offset
        self.expectedTotal = expectedTotal
        self.progress = progress
    }

    var receivedBytes: Int64 { lock.lock(); defer { lock.unlock() }; return received }

    func setContinuation(_ c: CheckedContinuation<Result<Int64, ModelDownloadChannel.Failure>, Never>) {
        lock.lock()
        if let finished { lock.unlock(); c.resume(returning: finished); return }
        continuation = c
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard let http = response as? HTTPURLResponse else {
            failure = .interrupted; completionHandler(.cancel); return
        }
        let declared = http.expectedContentLength
        switch http.statusCode {
        case 200:
            offset = 0
            if declared >= 0 && declared != expectedTotal {
                failure = .sizeMismatch; completionHandler(.cancel); return
            }
        case 206:
            guard let range = Self.parseContentRange(http.value(forHTTPHeaderField: "Content-Range")),
                  range.start == offset, range.total == expectedTotal, range.end == expectedTotal - 1 else {
                failure = .unexpectedRange; completionHandler(.cancel); return
            }
            if declared >= 0 && declared != expectedTotal - offset {
                failure = .sizeMismatch; completionHandler(.cancel); return
            }
        case 300..<400:
            failure = .redirectRefused; completionHandler(.cancel); return
        default:
            failure = .httpStatus(http.statusCode); completionHandler(.cancel); return
        }
        do {
            handle = try Self.openForWriting(partial, truncatingTo: offset)
        } catch {
            failure = .fileSystem; completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard failure == nil, let handle else { lock.unlock(); return }
        guard offset + received + Int64(data.count) <= expectedTotal else {
            failure = .sizeMismatch
            lock.unlock()
            dataTask.cancel()
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            failure = .fileSystem
            lock.unlock()
            dataTask.cancel()
            return
        }
        received += Int64(data.count)
        let total = offset + received
        lock.unlock()
        progress(total)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if let handle {
            try? handle.synchronize()
            try? handle.close()
            self.handle = nil
        }
        let result: Result<Int64, ModelDownloadChannel.Failure>
        if let failure {
            result = .failure(failure)
        } else if let error {
            result = .failure((error as? URLError)?.code == .cancelled ? .cancelled : .interrupted)
        } else if offset + received != expectedTotal {
            result = .failure(.interrupted)
        } else {
            result = .success(offset + received)
        }
        finished = result
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: result)
    }

    private static func openForWriting(_ url: URL, truncatingTo offset: Int64) throws -> FileHandle {
        let fd = open(url.path, O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ModelDownloadChannel.Failure.fileSystem }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        try handle.truncate(atOffset: UInt64(offset))
        try handle.seekToEnd()
        return handle
    }

    static func parseContentRange(_ value: String?) -> (start: Int64, end: Int64, total: Int64)? {
        guard let value else { return nil }
        let v = value.trimmingCharacters(in: .whitespaces)
        guard v.lowercased().hasPrefix("bytes ") else { return nil }
        let spec = v.dropFirst("bytes ".count)
        let parts = spec.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, let total = Int64(parts[1]) else { return nil }
        let se = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard se.count == 2, let start = Int64(se[0]), let end = Int64(se[1]), start <= end, end < total else {
            return nil
        }
        return (start, end, total)
    }
}
