#if DEBUG
import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
enum OnboardingSelfTest {
    private static var shots = 0
    private static var checks = 0

    static func run() async {
        SelfTestEnvironment.exitIfUnusable(.onboarding)
        var dir: URL?
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--onboarding-selftest"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
            dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
            try? FileManager.default.createDirectory(at: dir!, withIntermediateDirectories: true)
        }

        let suite = Edition.logSubsystem + ".onboarding-selftest"
        UserDefaults().removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite)!
        let ob = OnboardingController.shared
        let nudge = FeatureNudgeCenter.shared
        ob.debugUse(defaults: defaults)
        nudge.debugUse(defaults: defaults)
        let savedConsent = ConsentStore.debugOverride
        defer {
            ConsentStore.debugOverride = savedConsent
            ob.debugCloseWindow()
            UserDefaults().removePersistentDomain(forName: suite)
        }
        func fail(_ n: Int) -> Never {
            SelfTestEnvironment.exitIfUnusable(.onboarding, during: true)
            OnboardingSelfTestLine.emit(.failed(check: n))
            exit(Int32(50 + n))
        }
        func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
        func ok(_ n: Int, _ cond: Bool) { if !cond { fail(n) } }

        ConsentStore.debugOverride = .some(nil)
        ob.debugReset()
        ob.evaluateAtLaunch(consentedBefore: false, hasInsertionsOverride: false)
        ob.reopen()
        ok(1, !ob.isOpen)
        ob.resume()
        ok(1, !ob.isOpen)
        ok(1, ob.presentAfterConsent() == false)
        ok(1, !ob.isOpen)
        ob.launchedConsented()
        await wait(3.3)
        ok(1, !ob.isOpen)
        ok(1, ob.menuProgress == nil)
        ok(1, ob.open(steps: [.features], startAt: 0, reopened: true) == false && !ob.isOpen)
        checks += 1

        ConsentStore.debugOverride = .some(Edition.consentVersion)
        ob.debugReset()
        ob.evaluateAtLaunch(consentedBefore: false, hasInsertionsOverride: false)
        ok(2, ob.state.audience == .fullTour)
        ok(2, ob.presentAfterConsent() == true)
        ok(2, ob.isOpen)
        let expected = OnboardingPlan.steps(audience: .fullTour, hasModelStep: Edition.onboardingHasModelStep)
        ok(2, ob.steps == expected)
        ok(2, ob.currentStep == .permissions)
        checks += 1

        var n = 0
        while true {
            n += 1
            await wait(0.5)
            await shoot(ob.debugWindow, name: "onboarding-\(n)-\(String(describing: ob.currentStep))", dir: dir)
            if ob.isLast { break }
            ob.next()
        }
        ok(3, n == expected.count)
        ob.finish()
        ok(3, ob.state.isCompleted)
        ok(3, defaults.object(forKey: OnboardingPlan.Keys.completedAt) as? Date != nil)
        ok(3, !ob.isOpen)
        ok(3, ob.menuProgress == nil)
        checks += 1

        ob.debugReset()
        ob.evaluateAtLaunch(consentedBefore: false, hasInsertionsOverride: false)
        _ = ob.presentAfterConsent()
        ob.next()
        let atStep = ob.currentStep
        ob.later()
        await wait(0.3)
        ok(4, !ob.isOpen)
        let progress = ob.menuProgress
        ok(4, progress?.step == 2 && progress?.of == expected.count)
        ok(4, !ob.state.isCompleted)
        ob.resume()
        ok(4, ob.isOpen && ob.currentStep == atStep)
        checks += 1
        nudge.debugReset()
        let context = NudgeContext(now: Date(), daysSinceOnboarding: 30, statsRecording: true,
                                   usage: NudgeUsage(activeDays: 9, insertions: 120, weekCharacters: 3_420, weekSavedMinutes: 41),
                                   editShortcutLabel: EditCaptureSettings.shortcut.label)
        if let dir {
            ob.debugCloseWindow()
            await wait(0.2)
            save(MenuMock(lines: [.item("完成設定導覽（\(progress?.step ?? 0)/\(progress?.of ?? 0)）")]), "menu-onboarding-progress.png", dir: dir)
            for f in NudgeFeature.allCases {
                nudge.debugArm(f, context: context)
                save(MenuMock(lines: [.item("💡 試試：\(nudge.pendingText)"), .item("不用了，這個不再提示")]),
                     "menu-nudge-\(f.rawValue)-\(String(describing: f)).png", dir: dir)
                shots += 1
            }
            nudge.debugReset()
            shots += 1
        }

        ob.debugReset()
        ob.evaluateAtLaunch(consentedBefore: true, hasInsertionsOverride: false)
        ok(5, ob.state.audience == .featuresOnly)
        ob.launchedConsented()
        await wait(3.5)
        ok(5, ob.isOpen)
        ok(5, ob.steps == [.features])
        ok(5, ob.state.isCompleted)
        await shoot(ob.debugWindow, name: "onboarding-existing-user-features", dir: dir)
        ob.debugCloseWindow()
        await wait(0.3)
        ok(5, OnboardingPlan.presentation(state: ob.state, allowsCapture: true) == .none)
        ob.launchedConsented()
        await wait(3.3)
        ok(5, !ob.isOpen)
        ok(5, ob.menuProgress == nil)
        checks += 1

        ob.reopen()
        ok(6, ob.isOpen && ob.steps == expected && ob.currentStep == .permissions)
        ob.debugCloseWindow()
        await wait(0.3)
        ok(6, ob.state.isCompleted)
        checks += 1

        nudge.debugReset()
        nudge.debugArm(.editCapture, context: context)
        ok(7, nudge.pending == .editCapture)
        ok(7, nudge.pendingText.contains(EditCaptureSettings.shortcut.label))
        ok(7, nudge.debugState.record(for: NudgeFeature.editCapture.rawValue).shownCount == 1)
        nudge.open()
        ok(7, nudge.pending == nil)
        ok(7, nudge.debugState.record(for: NudgeFeature.editCapture.rawValue).opened)
        ok(7, SettingsWindow.isOpen)
        SettingsWindow.debugWindow?.close()
        nudge.debugArm(.dictionary, context: context)
        nudge.dismiss()
        ok(7, nudge.pending == nil)
        ok(7, nudge.debugState.record(for: NudgeFeature.dictionary.rawValue).dismissed)
        nudge.debugArm(.usageStats, context: context)
        ok(7, nudge.pendingText.contains("3,420") && nudge.pendingText.contains("41 分鐘"))
        nudge.debugReset()
        checks += 1

        FeatureMapWindow.show()
        await wait(0.6)
        ok(8, FeatureMapWindow.debugWindow != nil)
        await shoot(FeatureMapWindow.debugWindow, name: "feature-map", dir: dir)
        let rows = FeatureMapView().rows
        ok(8, rows.count >= 12)
        ok(8, rows.allSatisfy { !$0.state.isEmpty && !$0.summary.isEmpty })
        FeatureMapWindow.debugClose()
        checks += 1

        ok(9, UsageStatsRecorder.enabled == false)
        nudge.afterSuccessfulInsertion()
        await wait(0.2)
        ok(9, nudge.pending == nil)
        checks += 1

        OnboardingSelfTestLine.emit(.passed(checks: checks, shots: shots))
        exit(0)
    }

    private static func shoot(_ window: NSWindow?, name: String, dir: URL?) async {
        guard let window, let frame = window.contentView?.superview ?? window.contentView else { return }
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            frame.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .seconds(0.35))
            guard let dir, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                FileManager.default.createFile(atPath: dir.appendingPathComponent("\(name)-\(suffix).png").path, contents: png)
                shots += 1
            }
        }
        window.appearance = nil
    }

    private static func save<V: View>(_ view: V, _ name: String, dir: URL) {
        for (suffix, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme).fixedSize())
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            let size = host.fittingSize
            guard size.width > 0, size.height > 0 else { return }
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                let base = name.replacingOccurrences(of: ".png", with: "")
                FileManager.default.createFile(atPath: dir.appendingPathComponent("\(base)-\(suffix).png").path, contents: png)
                shots += 1
            }
        }
    }
}

private struct MenuMock: View {
    enum Line { case item(String) }
    let lines: [Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if case .item(let t) = line { row(t, primary: true) }
            }
            Divider().padding(.vertical, 4)
            row("待命中 · \(AppModel.hotkeyLabel) 開始口述", primary: true)
            row(Edition.Copy.destinationLine, primary: false)
            Divider().padding(.vertical, 4)
            row("最近口述", primary: true)
            Text("（示意：選單最上面的位置與長度；實際是系統選單）").font(.caption2).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func row(_ text: String, primary: Bool) -> some View {
        Text(text)
            .foregroundStyle(primary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10).padding(.vertical, 3)
    }
}
#endif
