import Foundation

public protocol ModelInstalling: AnyObject, Sendable {
    var modelDirectory: URL { get }
    @discardableResult func refresh() -> ModelInstallState
    @discardableResult func install() async -> ModelInstallState
    func cancel()
}

extension ModelInstaller: ModelInstalling {}

public enum LocalModelPhase: Sendable, Equatable {
    case checking
    case notDownloaded
    case hostingUndecided
    case downloading(fraction: Double?)
    case installing
    case preparing
    case ready
    case downloadFailed(ModelInstallFailure)
    case prepareFailed(message: String)

    public var allowsRecording: Bool { self == .ready }

    public var canStartDownload: Bool {
        switch self {
        case .notDownloaded, .downloadFailed, .prepareFailed: return true
        case .checking, .hostingUndecided, .downloading, .installing, .preparing, .ready: return false
        }
    }

    static func from(_ s: ModelInstallState) -> LocalModelPhase {
        switch s {
        case .notDownloaded: return .notDownloaded
        case .downloading: return .downloading(fraction: s.fractionCompleted)
        case .verifying, .installing: return .installing
        case .available: return .preparing
        case .failed(.hostingUndecided): return .hostingUndecided
        case .failed(.cancelled): return .notDownloaded
        case .failed(let f): return .downloadFailed(f)
        }
    }
}

public final class LocalModelSetup: @unchecked Sendable {
    public typealias Prepare = @Sendable () async -> String?

    private let installer: any ModelInstalling
    private let prepare: Prepare
    private let onChange: @Sendable (LocalModelPhase) -> Void

    private let lock = NSLock()
    private var _phase: LocalModelPhase = .checking
    private var inFlight: Task<LocalModelPhase, Never>?

    public init(installer: any ModelInstalling, prepare: @escaping Prepare,
                onChange: @escaping @Sendable (LocalModelPhase) -> Void = { _ in }) {
        self.installer = installer
        self.prepare = prepare
        self.onChange = onChange
    }

    public var phase: LocalModelPhase { lock.withLock { _phase } }
    public var modelDirectory: URL { installer.modelDirectory }

    public func installerDidChange(_ s: ModelInstallState) {
        switch s {
        case .downloading, .verifying, .installing:
            lock.lock()
            guard inFlight != nil, _phase != .preparing, _phase != .ready else { lock.unlock(); return }
            let p = LocalModelPhase.from(s)
            _phase = p
            lock.unlock()
            onChange(p)
        case .notDownloaded, .available, .failed:
            return
        }
    }

    @discardableResult
    public func start() async -> LocalModelPhase {
        await run(download: false)
    }

    @discardableResult
    public func downloadAndPrepare() async -> LocalModelPhase {
        await run(download: true)
    }

    public func cancelDownload() { installer.cancel() }

    private func run(download: Bool) async -> LocalModelPhase {
        let task: Task<LocalModelPhase, Never> = lock.withLock {
            if let running = inFlight { return running }
            let t = Task { () -> LocalModelPhase in
                let result = await self.flow(download: download)
                self.lock.withLock { self.inFlight = nil }
                return result
            }
            inFlight = t
            return t
        }
        return await task.value
    }

    private func flow(download: Bool) async -> LocalModelPhase {
        if phase == .ready { return .ready }
        var state = installer.refresh()
        if case .available = state {
        } else if download {
            state = await installer.install()
        }
        guard case .available = state else {
            return set(LocalModelPhase.from(state))
        }
        set(.preparing)
        if let message = await prepare() {
            return set(.prepareFailed(message: message))
        }
        return set(.ready)
    }

    @discardableResult
    private func set(_ p: LocalModelPhase) -> LocalModelPhase {
        lock.withLock { _phase = p }
        onChange(p)
        return p
    }
}
