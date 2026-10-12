import AppKit
import Combine
import NaturalInputCore
import SwiftUI

@MainActor
final class OnboardingController: ObservableObject {
    static let shared = OnboardingController()

    static var defaults: UserDefaults = .standard

    @Published private(set) var state: OnboardingPlan.State

    @Published private(set) var steps: [OnboardingPlan.Step] = []
    @Published private(set) var index = 0
    private(set) var reopened = false
    private var window: NSWindow?
    private let closer = Closer()
    private var waiting: Task<Void, Never>?

    private init() { state = Self.loadState() }

    var currentStep: OnboardingPlan.Step { steps.indices.contains(index) ? steps[index] : .features }
    var isOpen: Bool { window != nil }
    var isLast: Bool { index >= steps.count - 1 }

    private static func loadState() -> OnboardingPlan.State {
        let d = defaults
        return .init(completedVersion: d.object(forKey: OnboardingPlan.Keys.completedVersion) as? Int,
                     audience: (d.object(forKey: OnboardingPlan.Keys.audience) as? Int).flatMap(OnboardingPlan.Audience.init(rawValue:)),
                     lastStep: (d.object(forKey: OnboardingPlan.Keys.lastStep) as? Int).flatMap(OnboardingPlan.Step.init(rawValue:)))
    }

    private func store(_ new: OnboardingPlan.State) {
        let d = Self.defaults
        func put(_ v: Int?, _ k: String) { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } }
        put(new.completedVersion, OnboardingPlan.Keys.completedVersion)
        put(new.audience?.rawValue, OnboardingPlan.Keys.audience)
        put(new.lastStep?.rawValue, OnboardingPlan.Keys.lastStep)
        state = new
    }

    var menuProgress: (step: Int, of: Int)? {
        OnboardingPlan.menuProgress(state: state, allowsCapture: ConsentStore.allowsCapture,
                                    hasModelStep: Edition.onboardingHasModelStep)
    }

    func evaluateAtLaunch(consentedBefore: Bool, hasInsertionsOverride: Bool? = nil) {
        guard state.audience == nil else { return }
        let hasInsertions = hasInsertionsOverride
            ?? UsageStatsRecorder.store.days(lastDays: UsageStats.retentionDays, now: Date()).contains { $0.insertedRounds > 0 }
        let audience = OnboardingPlan.audience(consentedBeforeThisLaunch: consentedBefore, hasSuccessfulInsertions: hasInsertions)
        var next = state
        next.audience = audience
        self.store(next)
        Log.record(.onboarding(.audience(audience)))
    }

    func presentAfterConsent() -> Bool {
        let takesOverPermissions = state.audience == .fullTour && !state.isCompleted
        autoPresentIfNeeded(immediately: true)
        return takesOverPermissions && window != nil
    }

    func launchedConsented() {
        autoPresentIfNeeded(immediately: false)
    }

    private func autoPresentIfNeeded(immediately: Bool) {
        guard OnboardingPlan.presentation(state: state, allowsCapture: ConsentStore.allowsCapture) == .window,
              let audience = state.audience else { return }
        let steps = OnboardingPlan.steps(audience: audience, hasModelStep: Edition.onboardingHasModelStep)
        if immediately {
            open(steps: steps, startAt: startIndex(in: steps), reopened: false)
        } else {
            showWhenFree(steps: steps)
        }
    }

    private func showWhenFree(steps: [OnboardingPlan.Step]) {
        waiting?.cancel()
        waiting = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            while !Task.isCancelled {
                let m = AppModel.shared
                if ConsentStore.allowsCapture, m.phase == .idle, !m.deliveringNewTranscript, !m.inserting, !WhatsNewWindow.isOpen {
                    guard let self else { return }
                    self.open(steps: steps, startAt: self.startIndex(in: steps), reopened: false)
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startIndex(in steps: [OnboardingPlan.Step]) -> Int {
        state.lastStep.flatMap { steps.firstIndex(of: $0) } ?? 0
    }

    func reopen() {
        _ = open(steps: OnboardingPlan.steps(audience: .fullTour, hasModelStep: Edition.onboardingHasModelStep),
                 startAt: 0, reopened: true)
    }

    func resume() {
        let all = OnboardingPlan.steps(audience: .fullTour, hasModelStep: Edition.onboardingHasModelStep)
        _ = open(steps: all, startAt: startIndex(in: all), reopened: false)
    }

    @discardableResult
    func open(steps: [OnboardingPlan.Step], startAt: Int, reopened: Bool) -> Bool {
        guard OnboardingPlan.mayOpen(allowsCapture: ConsentStore.allowsCapture) else {
            Log.record(.onboarding(.refusedNoConsent))
            return false
        }
        waiting?.cancel(); waiting = nil
        self.steps = steps
        self.index = min(max(0, startAt), max(0, steps.count - 1))
        self.reopened = reopened
        Log.record(.onboarding(.opened(currentStep, reopened: reopened)))
        remember(currentStep)
        if state.audience == .featuresOnly, !reopened, !state.isCompleted { complete(skipped: false, closeWindow: false) }
        show()
        return true
    }

    private func remember(_ step: OnboardingPlan.Step) {
        guard !reopened, state.audience == .fullTour, !state.isCompleted else { return }
        store(OnboardingPlan.moved(state, to: step))
    }

    func next() {
        guard !isLast else { finish(); return }
        index += 1
        remember(currentStep)
    }

    func back() {
        guard index > 0 else { return }
        index -= 1
        remember(currentStep)
    }

    func finish() {
        complete(skipped: false, closeWindow: true)
    }

    func skipForGood() {
        complete(skipped: true, closeWindow: true)
    }

    func later() {
        window?.performClose(nil)
    }

    private func complete(skipped: Bool, closeWindow: Bool) {
        if !state.isCompleted {
            store(OnboardingPlan.completed(state))
            if Self.defaults.object(forKey: OnboardingPlan.Keys.completedAt) == nil {
                Self.defaults.set(Date(), forKey: OnboardingPlan.Keys.completedAt)
            }
            Log.record(.onboarding(.completed(skipped: skipped)))
        }
        if closeWindow { window?.close() }
    }

    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(controller: self))
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable]
        w.title = "Talkiie 設定導覽"
        w.isReleasedWhenClosed = false
        w.delegate = closer
        closer.owner = self
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
    }

    fileprivate func windowClosed() {
        if !state.isCompleted { Log.record(.onboarding(.leftEarly(currentStep))) }
        window = nil
        objectWillChange.send()
    }

    private final class Closer: NSObject, NSWindowDelegate {
        weak var owner: OnboardingController?
        func windowWillClose(_ n: Notification) {
            MainActor.assumeIsolated { owner?.windowClosed() }
        }
        func windowDidBecomeKey(_ n: Notification) {
            MainActor.assumeIsolated {
                AppModel.shared.refreshPermissions()
                SettingsRefresh.shared.bump()
            }
        }
    }

    #if DEBUG
    var debugWindow: NSWindow? { window }
    func debugCloseWindow() { window?.close() }
    func debugUse(defaults d: UserDefaults) {
        window?.close()
        Self.defaults = d
        state = Self.loadState()
        steps = []
        index = 0
        reopened = false
    }
    func debugReset() {
        window?.close()
        for k in [OnboardingPlan.Keys.completedVersion, OnboardingPlan.Keys.completedAt, OnboardingPlan.Keys.audience, OnboardingPlan.Keys.lastStep] {
            Self.defaults.removeObject(forKey: k)
        }
        state = Self.loadState()
        steps = []
        index = 0
        reopened = false
    }
    #endif
}

struct OnboardingMenuSection: View {
    @ObservedObject var controller = OnboardingController.shared

    var body: some View {
        if let p = controller.menuProgress {
            Button("完成設定導覽（\(p.step)/\(p.of)）") { controller.resume() }
            Divider()
        }
    }
}
