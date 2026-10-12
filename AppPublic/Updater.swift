import AppKit
import Combine
import NaturalInputCore
import NaturalInputEgress
import NaturalInputEgressPublic
@preconcurrency import Sparkle

@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    @Published private(set) var canCheck = false
    @Published fileprivate(set) var available: String?

    static var availableInThisBuild: Bool {
        #if DEBUG
        false
        #else
        hasUsablePublicKey
        #endif
    }

    static var hasUsablePublicKey: Bool {
        PublicUpdatePolicy.isUsablePublicKey(Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    }

    private var controller: SPUStandardUpdaterController?
    private var postponed: (() -> Void)?
    private var subs = Set<AnyCancellable>()
    nonisolated private let gate = PublicUpdateGate(log: Edition.egressLog)

    func start() {
        guard Self.availableInThisBuild else {
            Log.record(.updater(Self.hasUsablePublicKey ? .disabledInDebug : .disabledNoPublicKey)); return
        }
        guard ConsentStore.allowsCapture else { Log.record(.updater(.notStartedNoConsent)); return }
        guard controller == nil else { return }
        let c = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        controller = c
        c.updater.sendsSystemProfile = false
        c.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheck = $0 }
            .store(in: &subs)
        AppModel.shared.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                guard phase == .idle else { return }
                self?.resumeWhenIdle()
            }
            .store(in: &subs)
        do {
            try c.updater.start()
            Log.record(.updater(.started(automaticChecks: c.updater.automaticallyChecksForUpdates)))
            c.updater.checkForUpdatesInBackground()
        } catch {
            Log.record(.updater(.startFailed))
        }
    }

    func checkForUpdates() { controller?.updater.checkForUpdates() }

    func showUpdate() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.updater.checkForUpdates()
    }

    fileprivate static var busy: Bool {
        !UpdateRelaunchGate.mayRelaunch(idle: AppModel.shared.phase == .idle,
                                        deliveringTranscript: AppModel.shared.deliveringNewTranscript,
                                        inserting: AppModel.shared.inserting)
    }

    fileprivate func resumeWhenIdle() {
        guard postponed != nil else { return }
        guard !Self.busy else {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.resumeWhenIdle()
            }
            return
        }
        let go = postponed
        postponed = nil
        Log.record(.updater(.relaunchResumed))
        go?()
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let (consented, busy, sendsProfile, feedURL) = MainActor.assumeIsolated {
            updater.sendsSystemProfile = false
            return (ConsentStore.allowsCapture, Updater.busy, updater.sendsSystemProfile, updater.feedURL)
        }
        guard consented else {
            MainActor.assumeIsolated { Log.record(.updater(.checkRefused(.notConsented))) }
            throw Self.error("no consent")
        }
        if updateCheck == .updatesInBackground, busy {
            MainActor.assumeIsolated { Log.record(.updater(.checkRefused(.busy))) }
            throw Self.error("recording in progress")
        }
        do {
            try gate.approveFeedCheck(feedURL, feedParameters: PublicUpdatePolicy.feedParameters, sendsSystemProfile: sendsProfile)
        } catch {
            MainActor.assumeIsolated { Log.record(.updater(.checkRefused(.gate))) }
            throw error
        }
    }

    nonisolated func feedParameters(for updater: SPUUpdater, sendingSystemProfile: Bool) -> [[String: String]] {
        PublicUpdatePolicy.feedParameters
    }

    nonisolated func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        PublicUpdatePolicy.allowedSystemProfileKeys
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem,
                             updateCheck: SPUUpdateCheck) throws {
        guard PublicUpdatePolicy.isAllowedDownload(updateItem.fileURL) else {
            MainActor.assumeIsolated { Log.record(.updater(.updateRejected)) }
            throw Self.error("update archive is not under the public download path")
        }
        guard PublicUpdatePolicy.isAllowedReleaseNotes(descriptionFormat: updateItem.itemDescriptionFormat,
                                                       hasDescription: updateItem.itemDescription != nil,
                                                       releaseNotesURL: updateItem.releaseNotesURL,
                                                       fullReleaseNotesURL: updateItem.fullReleaseNotesURL) else {
            MainActor.assumeIsolated { Log.record(.updater(.releaseNotesRejected)) }
            throw Self.error("release notes are not plain text")
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        false
    }

    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        UserDefaults.standard.set(true, forKey: WhatsNewPlan.Keys.relaunchedByUpdate)
        Task { @MainActor in Log.record(.updater(.relaunchingIntoUpdate)) }
    }

    nonisolated func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem,
                             with request: NSMutableURLRequest) {
        do {
            try gate.approveDownload(request.url)
        } catch {
            request.url = nil
            MainActor.assumeIsolated { Log.record(.updater(.updateRejected)) }
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                             untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        let handler = MainThreadHandler(run: installHandler)
        return MainActor.assumeIsolated {
            guard Updater.busy else { return false }
            Log.record(.updater(.relaunchPostponed))
            Updater.shared.postponed = { handler.run() }
            Task { @MainActor in Updater.shared.resumeWhenIdle() }
            return true
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let code = (error as NSError).code
        MainActor.assumeIsolated { Log.record(.updater(.aborted(code: code))) }
    }

    private nonisolated static func error(_ reason: String) -> NSError {
        NSError(domain: "app.yyt.talkiie.update", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }
}

private struct MainThreadHandler: @unchecked Sendable {
    let run: () -> Void
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let build = Int(update.versionString)
        let version = update.displayVersionString
        MainActor.assumeIsolated {
            Log.record(.updater(.updateFound(build: build)))
            if handleShowingUpdate {
                if !state.userInitiated { NSApp.activate(ignoringOtherApps: true) }
            } else {
                Log.record(.updater(.reminderPending(build: build)))
                Updater.shared.available = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { Updater.shared.available = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { Updater.shared.available = nil }
    }
}
