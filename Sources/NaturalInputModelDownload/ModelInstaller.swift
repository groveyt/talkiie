import Foundation
import NaturalInputEgress

public final class ModelInstaller: @unchecked Sendable {
    public static let diskSafetyMarginBytes: Int64 = 1 << 30

    public let artifact: ModelArtifact

    private let store: ModelStore
    private let channel: ModelDownloadChannel
    private let allowlist: [ModelArtifact]
    private let extractor: ModelArchiveExtracting
    private let freeSpace: @Sendable (URL) throws -> Int64
    private let onChange: @Sendable (ModelInstallState) -> Void

    private let lock = NSLock()
    private var _state: ModelInstallState = .notDownloaded
    private var inFlight: Task<ModelInstallState, Never>?
    private var lastReportedBytes: Int64 = 0

    public convenience init(artifact: ModelArtifact = ModelManifest.breezeASR25,
                            log: EgressLog,
                            root: URL,
                            onChange: @escaping @Sendable (ModelInstallState) -> Void = { _ in }) {
        self.init(artifact: artifact, log: log, root: root, allowlist: ModelManifest.artifacts,
                  protocolClasses: nil, extractor: ZipExtractor(),
                  freeSpace: { try ModelStore.availableCapacity(at: $0) }, onChange: onChange)
    }

    init(artifact: ModelArtifact, log: EgressLog, root: URL, allowlist: [ModelArtifact],
         protocolClasses: [AnyClass]?, extractor: ModelArchiveExtracting,
         freeSpace: @escaping @Sendable (URL) throws -> Int64,
         onChange: @escaping @Sendable (ModelInstallState) -> Void) {
        self.artifact = artifact
        self.store = ModelStore(root: root)
        self.channel = ModelDownloadChannel(log: log, allowlist: allowlist, protocolClasses: protocolClasses)
        self.allowlist = allowlist
        self.extractor = extractor
        self.freeSpace = freeSpace
        self.onChange = onChange
        if store.isInstalled(artifact) { _state = .available(store.finalDirectory(for: artifact)) }
    }

    public var state: ModelInstallState {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    public var modelDirectory: URL { store.finalDirectory(for: artifact) }

    @discardableResult
    public func refresh() -> ModelInstallState {
        lock.lock()
        if inFlight != nil { let s = _state; lock.unlock(); return s }
        lock.unlock()
        return set(store.isInstalled(artifact) ? .available(modelDirectory) : .notDownloaded)
    }

    @discardableResult
    public func install() async -> ModelInstallState {
        let task: Task<ModelInstallState, Never> = lock.withLock {
            if let running = inFlight { return running }
            let t = Task { () -> ModelInstallState in
                let result = await self.run()
                self.lock.withLock { self.inFlight = nil }
                return result
            }
            inFlight = t
            return t
        }
        return await task.value
    }

    @discardableResult
    public func discardInstalledModel() -> ModelInstallState {
        lock.lock()
        if inFlight != nil { let s = _state; lock.unlock(); return s }
        lock.unlock()
        try? FileManager.default.removeItem(at: modelDirectory)
        return refresh()
    }

    public func cancel() {
        lock.lock(); let t = inFlight; lock.unlock()
        t?.cancel()
    }

    private func run() async -> ModelInstallState {
        guard allowlist.contains(artifact), ModelManifest.isWellFormed(artifact) else {
            return fail(.notInManifest)
        }
        guard !artifact.isPlaceholder else { return fail(.hostingUndecided) }
        if store.isInstalled(artifact) { return set(.available(modelDirectory)) }

        let lockFD: Int32
        do {
            guard let fd = try store.tryLock() else { return fail(.alreadyInProgressElsewhere) }
            lockFD = fd
        } catch {
            return fail(.fileSystem)
        }
        defer { store.releaseLock(lockFD) }
        if store.isInstalled(artifact) { return set(.available(modelDirectory)) }
        store.removeStaleWorkDirectories()

        var have: [Int64] = artifact.files.map { f in
            let partial = store.partialFile(for: f, of: artifact)
            let size = ModelDownloadChannel.fileSize(partial) ?? 0
            if size > f.bytes { try? FileManager.default.removeItem(at: partial); return 0 }
            return size
        }

        let remaining = zip(artifact.files, have).reduce(Int64(0)) { $0 + ($1.0.bytes - $1.1) }
        let required = remaining + unpackedBytes + Self.diskSafetyMarginBytes
        if let failure = checkSpace(required: required) { return fail(failure) }

        for (i, file) in artifact.files.enumerated() where have[i] < file.bytes {
            let partial = store.partialFile(for: file, of: artifact)
            let base = have.enumerated().reduce(Int64(0)) { $0 + ($1.offset == i ? 0 : $1.element) }
            lock.withLock { lastReportedBytes = base + have[i] }
            set(.downloading(receivedBytes: base + have[i], totalBytes: artifact.downloadBytes))
            do {
                have[i] = try await channel.fetch(file, of: artifact, into: partial) { [weak self] bytes in
                    self?.reportProgress(base + bytes)
                }
            } catch let e as ModelDownloadChannel.Failure {
                return fail(Self.map(e), deletingPartial: Self.discardsPartial(e) ? partial : nil)
            } catch {
                return fail(.interrupted)
            }
            if Task.isCancelled { return fail(.cancelled) }
        }

        set(.verifying)
        for file in artifact.files {
            let partial = store.partialFile(for: file, of: artifact)
            let digest: String
            do { digest = try ModelStore.sha256Hex(of: partial) } catch { return fail(.fileSystem) }
            guard digest == file.sha256 else {
                return fail(.checksumMismatch, deletingPartial: partial)
            }
        }

        set(.installing)
        if let failure = checkSpace(required: unpackedBytes + Self.diskSafetyMarginBytes) {
            return fail(failure)
        }
        let workDir: URL
        do {
            workDir = try store.makeWorkDirectory()
        } catch {
            return fail(.fileSystem)
        }
        do {
            for file in artifact.files {
                let partial = store.partialFile(for: file, of: artifact)
                switch file.format {
                case .raw: try store.placeRaw(partial, as: file.name, in: workDir)
                case .zip: try extractor.extract(zip: partial, expectingTop: file.name, into: workDir)
                }
            }
            try store.validateContents(of: workDir, for: artifact)
            try store.writeReceipt(in: workDir, for: artifact)
            try store.commit(workDir, as: artifact)
        } catch {
            try? FileManager.default.removeItem(at: workDir)
            switch error as? ModelStore.Failure {
            case .contentsInvalid?: return fail(.contentsInvalid)
            case .fileSystem?: return fail(.fileSystem)
            case nil: return fail(.extractionFailed)
            }
        }
        for file in artifact.files {
            try? FileManager.default.removeItem(at: store.partialFile(for: file, of: artifact))
        }
        return set(.available(modelDirectory))
    }

    private var unpackedBytes: Int64 {
        artifact.files.filter { $0.format == .zip }.reduce(0) { $0 + $1.installedBytes }
    }

    private func checkSpace(required: Int64) -> ModelInstallFailure? {
        let available: Int64
        do { available = try freeSpace(store.root) } catch { return .fileSystem }
        return available < required ? .insufficientDiskSpace(requiredBytes: required, availableBytes: available) : nil
    }

    private func reportProgress(_ bytes: Int64) {
        let total = artifact.downloadBytes
        let step = max(total / 100, 8 << 20)
        lock.lock()
        guard bytes - lastReportedBytes >= step || bytes == total else { lock.unlock(); return }
        lastReportedBytes = bytes
        lock.unlock()
        set(.downloading(receivedBytes: bytes, totalBytes: total))
    }

    @discardableResult
    private func set(_ s: ModelInstallState) -> ModelInstallState {
        lock.lock(); _state = s; lock.unlock()
        onChange(s)
        return s
    }

    private func fail(_ f: ModelInstallFailure, deletingPartial partial: URL? = nil) -> ModelInstallState {
        if let partial { try? FileManager.default.removeItem(at: partial) }
        return set(.failed(f))
    }

    private static func map(_ e: ModelDownloadChannel.Failure) -> ModelInstallFailure {
        switch e {
        case .notInManifest: return .notInManifest
        case .logUnavailable: return .logUnavailable
        case .redirectRefused: return .redirectRefused
        case .httpStatus(let code): return .httpStatus(code)
        case .unexpectedRange: return .unexpectedRange
        case .sizeMismatch: return .sizeMismatch
        case .interrupted: return .interrupted
        case .fileSystem: return .fileSystem
        case .cancelled: return .cancelled
        }
    }

    private static func discardsPartial(_ e: ModelDownloadChannel.Failure) -> Bool {
        e == .unexpectedRange || e == .sizeMismatch
    }
}
