import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
final class FeatureNudgeCenter: ObservableObject {
    static let shared = FeatureNudgeCenter()

    static var defaults: UserDefaults = .standard
    static var settleSeconds: Double = 1.5

    @Published private(set) var pending: NudgeFeature?
    @Published private(set) var pendingText = ""

    private var state: NudgeState
    private var evaluating = false

    private init() {
        state = NudgeState.decode(Self.defaults.data(forKey: FeatureNudgePlan.stateDefaultsKey))
        reloadPending()
    }

    var enabled: Bool {
        FeatureNudgePlan.isEnabled(fromDefaults: Self.defaults.object(forKey: FeatureNudgePlan.enabledDefaultsKey))
    }

    private var statsRecording: Bool {
        UsageStats.recordingEnabled(fromDefaults: UserDefaults.standard.object(forKey: UsageStats.recordingDefaultsKey))
    }

    private var onboardingCompletedAt: Date? {
        Self.defaults.object(forKey: OnboardingPlan.Keys.completedAt) as? Date
    }

    private func save() {
        if let data = state.encoded() { Self.defaults.set(data, forKey: FeatureNudgePlan.stateDefaultsKey) }
    }

    private func context(usage: NudgeUsage, busy: Bool, now: Date) -> NudgeContext {
        NudgeContext(now: now,
                     enabled: enabled,
                     daysSinceOnboarding: FeatureNudgePlan.daysSince(onboardingCompletedAt, now: now),
                     statsRecording: statsRecording,
                     usage: usage,
                     busy: busy,
                     editCaptureEnabled: EditCaptureSettings.isEnabled,
                     dictionaryEntryCount: PersonalDictionaryStore.shared.entries.count,
                     fillerRemovalOff: FillerRemoval.strength(fromDefaults: UserDefaults.standard.string(forKey: FillerRemoval.defaultsKey)) == .off,
                     statsPaneVisited: state.statsPaneVisited,
                     editShortcutLabel: EditCaptureSettings.shortcut.label)
    }

    private var busyNow: Bool {
        let m = AppModel.shared
        return m.phase != .idle || m.deliveringNewTranscript || m.inserting
    }

    func afterSuccessfulInsertion() {
        guard UsageStatsRecorder.enabled else { return }
        guard enabled, onboardingCompletedAt != nil, !evaluating else { return }
        evaluating = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleSeconds))
            await self?.evaluate(now: Date())
        }
    }

    func evaluate(now: Date) async {
        defer { evaluating = false }
        reloadPending(now: now)
        guard enabled, !busyNow, onboardingCompletedAt != nil, pending == nil else { return }
        var usage = NudgeUsage()
        if statsRecording {
            let store = UsageStatsRecorder.store
            usage = await Task.detached(priority: .utility) {
                NudgeUsage(days: store.days(lastDays: UsageStats.retentionDays, now: now), now: now)
            }.value
        }
        guard !busyNow else { return }
        let c = context(usage: usage, busy: false, now: now)
        guard let feature = FeatureNudgePlan.next(state: state, context: c) else { return }
        deliver(feature, context: c)
    }

    private func deliver(_ feature: NudgeFeature, context c: NudgeContext) {
        state = FeatureNudgePlan.armed(state, feature: feature, now: c.now)
        save()
        pending = feature
        pendingText = FeatureNudgePlan.text(for: feature, context: c)
        Log.record(.featureNudge(.shown(feature)))
    }

    func reloadPending(now: Date = Date()) {
        if state.pending != nil, FeatureNudgePlan.pendingFeature(state: state, now: now) == nil {
            let old = state.pending.flatMap(NudgeFeature.init(rawValue:))
            state = FeatureNudgePlan.expired(state)
            save()
            if let old { Log.record(.featureNudge(.expired(old))) }
        }
        let f = FeatureNudgePlan.pendingFeature(state: state, now: now)
        guard f != pending else { return }
        pending = f
        pendingText = ""
        if let f { refreshText(for: f, now: now) }
    }

    private func refreshText(for f: NudgeFeature, now: Date) {
        let store = UsageStatsRecorder.store
        let needsUsage = f == .usageStats && statsRecording
        Task { @MainActor [weak self] in
            var usage = NudgeUsage()
            if needsUsage {
                usage = await Task.detached(priority: .utility) {
                    NudgeUsage(days: store.days(lastDays: UsageStats.retentionDays, now: now), now: now)
                }.value
            }
            guard let self, self.pending == f else { return }
            self.pendingText = FeatureNudgePlan.text(for: f, context: self.context(usage: usage, busy: false, now: now))
        }
    }

    func open() {
        guard let f = pending else { return }
        state = FeatureNudgePlan.opened(state, feature: f)
        save()
        pending = nil
        Log.record(.featureNudge(.opened(f)))
        SettingsWindow.show(SettingsTab(f.target))
    }

    func dismiss() {
        guard let f = pending else { return }
        state = FeatureNudgePlan.dismissed(state, feature: f)
        save()
        pending = nil
        Log.record(.featureNudge(.dismissed(f)))
    }

    func statsPaneVisited() {
        guard !state.statsPaneVisited else { return }
        state.statsPaneVisited = true
        save()
    }

    #if DEBUG
    func debugArm(_ feature: NudgeFeature, context c: NudgeContext) { deliver(feature, context: c) }
    func debugUse(defaults d: UserDefaults) {
        Self.defaults = d
        state = NudgeState.decode(d.data(forKey: FeatureNudgePlan.stateDefaultsKey))
        pending = nil
        pendingText = ""
    }
    func debugReset() {
        state = NudgeState()
        Self.defaults.removeObject(forKey: FeatureNudgePlan.stateDefaultsKey)
        pending = nil
        pendingText = ""
    }
    var debugState: NudgeState { state }
    #endif
}

struct FeatureNudgeMenuSection: View {
    @ObservedObject var center = FeatureNudgeCenter.shared

    var body: some View {
        if center.pending != nil, !center.pendingText.isEmpty {
            Button("💡 試試：\(center.pendingText)") { center.open() }
            Button("不用了，這個不再提示") { center.dismiss() }
            Divider()
        }
    }
}
