import AppKit
import NaturalInputCore
import SwiftUI

@MainActor
enum SettingsWindow {
    fileprivate static var window: NSWindow?
    private static let closer = Closer()
    static let paneDefaultsKey = "settingsPane"

    static func show(_ tab: SettingsTab? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        AppModel.shared.refreshPermissions()
        LaunchAtLogin.shared.refresh()
        SettingsRefresh.shared.bump()
        if let w = window {
            if let tab { select(tab) }
            w.makeKeyAndOrderFront(nil)
            return
        }
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        for p in SettingsTab.allCases {
            let host = NSHostingController(rootView: p.view.environmentObject(AppModel.shared))
            host.sizingOptions = [.preferredContentSize]
            host.title = p.title
            let item = NSTabViewItem(viewController: host)
            item.label = p.title
            item.image = NSImage(systemSymbolName: p.symbol, accessibilityDescription: p.title)
            item.identifier = p.rawValue
            tabs.addTabViewItem(item)
        }
        let w = SettingsNSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.delegate = closer
        window = w
        if let tab {
            select(tab)
        } else {
            let last = UserDefaults.standard.string(forKey: paneDefaultsKey).flatMap(SettingsTab.init(rawValue:))
            select(last ?? .general)
        }
        tabs.fit()
        if !w.setFrameUsingName("TalkiieSettings") { w.center() }
        tabs.fit()
        w.setFrameAutosaveName("TalkiieSettings")
        w.makeKeyAndOrderFront(nil)
    }

    static var isOpen: Bool { window != nil }

    private static func select(_ tab: SettingsTab) {
        guard let tabs = window?.contentViewController as? NSTabViewController,
              let i = tabs.tabViewItems.firstIndex(where: { $0.identifier as? String == tab.rawValue }) else { return }
        tabs.selectedTabViewItemIndex = i
    }

    private final class Closer: NSObject, NSWindowDelegate {
        func windowWillClose(_ n: Notification) {
            MainActor.assumeIsolated { SettingsWindow.window = nil }
        }
        func windowDidBecomeKey(_ n: Notification) {
            MainActor.assumeIsolated {
                AppModel.shared.refreshPermissions()
                LaunchAtLogin.shared.refresh()
                SettingsRefresh.shared.bump()
            }
        }
    }
}

final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        if let id = item?.identifier as? String {
            UserDefaults.standard.set(id, forKey: SettingsWindow.paneDefaultsKey)
            if id == SettingsTab.stats.rawValue { MainActor.assumeIsolated { FeatureNudgeCenter.shared.statsPaneVisited() } }
        }
        fit()
    }

    func fit() {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex), let w = view.window else { return }
        let vc = tabViewItems[selectedTabViewItemIndex].viewController
        var size = vc?.preferredContentSize ?? .zero
        if size.width < 1 || size.height < 1 { size = vc?.view.fittingSize ?? size }
        guard size.width >= 1, size.height >= 1 else { return }
        let screenHeight = (w.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        size.height = min(size.height, max(360, screenHeight - 120))
        let content = w.contentRect(forFrameRect: w.frame)
        let target = w.frameRect(forContentRect: NSRect(x: content.minX, y: content.maxY - size.height,
                                                        width: size.width, height: size.height))
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        w.setFrame(target, display: true, animate: w.isVisible && !reduce)
    }
}

private final class SettingsNSWindow: NSWindow {
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if (firstResponder as? KeyCatcherView)?.isRecording == true { return super.performKeyEquivalent(with: e) }
        if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           e.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: e)
    }
}

@MainActor
final class SettingsRefresh: ObservableObject {
    static let shared = SettingsRefresh()
    @Published private(set) var generation = 0
    func bump() { generation += 1 }
}

enum SettingsTab: String, CaseIterable {
    case general, text, stats, privacy, permissions, about
    #if DEBUG
    case developer
    #endif

    init(_ target: FeatureTarget) {
        switch target {
        case .general: self = .general
        case .text: self = .text
        case .stats: self = .stats
        case .privacy: self = .privacy
        case .permissions: self = .permissions
        case .about: self = .about
        }
    }

    var title: String {
        switch self {
        case .general: return "一般"
        case .text: return "文字"
        case .stats: return "統計"
        case .privacy: return "隱私"
        case .permissions: return "權限"
        case .about: return "關於"
        #if DEBUG
        case .developer: return "開發"
        #endif
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .text: return "character.cursor.ibeam"
        case .stats: return "chart.bar.xaxis"
        case .privacy: return "hand.raised"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        #if DEBUG
        case .developer: return "hammer"
        #endif
        }
    }

    @MainActor
    var view: AnyView {
        switch self {
        case .general: return AnyView(GeneralPane())
        case .text: return AnyView(TextPane())
        case .stats: return AnyView(UsageStatsPane())
        case .privacy: return AnyView(PrivacyPane())
        case .permissions: return AnyView(PermissionsPane())
        case .about: return AnyView(AboutPane())
        #if DEBUG
        case .developer: return AnyView(DeveloperPane())
        #endif
        }
    }
}

#if DEBUG
@MainActor
enum SettingsSelfTest {
    static func run() async {
        if let missing = ConsentDisclosureCheck.firstMissing(in: Edition.Copy.points(hotkey: AppModel.hotkeyStartPhrase)) {
            SettingsSelfTestLine.emit(.consentMissing(index: missing)); exit(42)
        }
        if let code = PlusVisibilityCheck.lockedOptionsListed() {
            SettingsSelfTestLine.emit(.plusVisible(tab: -1, term: code)); exit(43)
        }
        let args = CommandLine.arguments
        var dir: URL?
        if let i = args.firstIndex(of: "--settings-selftest"), i + 1 < args.count, !args[i + 1].hasPrefix("--") {
            dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        }
        let statsSample = args.contains("--stats-sample")
        if statsSample { UsageStatsModel.shared.useSample() }
        SelfTestEnvironment.exitIfUnusable(.settings)
        for (n, tab) in SettingsTab.allCases.enumerated() {
            SettingsWindow.show(tab)
            try? await Task.sleep(for: .seconds(0.6))
            guard let w = SettingsWindow.debugWindow, let frame = w.contentView?.superview ?? w.contentView else {
                SelfTestEnvironment.exitIfUnusable(.settings, during: true)
                SettingsSelfTestLine.emit(.failed(tab: n, width: 0, height: 0)); exit(40)
            }
            let content = w.contentRect(forFrameRect: w.frame).size
            let screen = w.screen?.visibleFrame.height ?? 2000
            guard content.width >= 400, content.height >= 120, w.frame.height <= screen else {
                SelfTestEnvironment.exitIfUnusable(.settings, during: true)
                SettingsSelfTestLine.emit(.failed(tab: n, width: Int(content.width), height: Int(content.height))); exit(41)
            }
            let (texts, screens) = await PlusVisibilityCheck.textsWholePage(in: frame)
            if let sentinel = PlusVisibilityCheck.sentinel(for: tab), !texts.contains(where: { $0.contains(sentinel) }) {
                SelfTestEnvironment.exitIfUnusable(.settings, during: true)
                SettingsSelfTestLine.emit(.textWalkBlind(tab: n, rows: texts.count, screens: screens)); exit(44)
            }
            if let term = PlusVisibilityCheck.firstForbidden(in: texts) {
                SettingsSelfTestLine.emit(.plusVisible(tab: n, term: term)); exit(43)
            }
            if let dir, let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    FileManager.default.createFile(atPath: dir.appendingPathComponent("settings-\(tab.rawValue).png").path,
                                                   contents: png)
                }
            }
            if let dir, tab == .stats, statsSample {
                await captureStatsVariants(window: w, frame: frame, dir: dir)
            }
            SettingsSelfTestLine.emit(.pane(tab: n, width: Int(content.width), height: Int(content.height)))
        }
        SettingsSelfTestLine.emit(.passed(tabs: SettingsTab.allCases.count))
        exit(0)
    }
}

enum PlusVisibilityCheck {
    static let forbidden = ["Plus", "購買", "啟用碼", "啟用授權"]

    static func sentinel(for tab: SettingsTab) -> String? {
        switch tab {
        case .general: return "功能提示"
        case .about: return "第三方授權"
        default: return nil
        }
    }

    @MainActor static func lockedOptionsListed() -> Int? {
        let unlocked = Edition.plusUnlocked
        if HUDTheme.pickerOptions(unlocked: unlocked, offersPlus: Edition.offersPlus).contains(where: { $0.requiresPlus && !unlocked }) { return 1 }
        if StartChime.Preset.pickerOptions(unlocked: unlocked, offersPlus: Edition.offersPlus)
            .contains(where: { $0.requiresPlus && !unlocked }) { return 2 }
        return nil
    }

    static func firstForbidden(in texts: [String]) -> Int? {
        for (i, word) in forbidden.enumerated() where texts.contains(where: { $0.contains(word) }) { return i }
        return nil
    }

    @MainActor static func textsWholePage(in root: NSView) async -> (texts: [String], screens: Int) {
        func scrollViews(in view: NSView) -> [NSScrollView] {
            var out: [NSScrollView] = []
            if let s = view as? NSScrollView { out.append(s) }
            for sub in view.subviews { out += scrollViews(in: sub) }
            return out
        }
        var texts = texts(in: root) + PlusVisibilityOCR.texts(in: root)
        guard let scroll = scrollViews(in: root).max(by: {
            ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0)
        }) else { return (texts, 0) }
        let visible = scroll.contentView.bounds.height
        let maxY = max(0, (scroll.documentView?.frame.height ?? 0) - visible)
        guard maxY > 0, visible > 80 else { return (texts, 0) }
        var y: CGFloat = 0
        var screens = 0
        while y < maxY, screens < 20 {
            y = min(maxY, y + visible - 60)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            try? await Task.sleep(for: .seconds(0.4))
            texts += self.texts(in: root) + PlusVisibilityOCR.texts(in: root)
            screens += 1
        }
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try? await Task.sleep(for: .seconds(0.3))
        return (texts, screens)
    }

    @MainActor static func texts(in root: NSView) -> [String] {
        var out: [String] = []
        var seen = Set<ObjectIdentifier>()
        func visit(_ element: Any, depth: Int) {
            guard depth < 60, out.count < 20_000 else { return }
            let obj = element as AnyObject
            guard seen.insert(ObjectIdentifier(obj)).inserted else { return }
            if let e = element as? NSAccessibilityProtocol {
                for s in [e.accessibilityLabel(), e.accessibilityTitle(), e.accessibilityValue() as? String,
                          e.accessibilityPlaceholderValue(), e.accessibilityHelp()] {
                    if let s, !s.isEmpty { out.append(s) }
                }
                for child in e.accessibilityChildren() ?? [] { visit(child, depth: depth + 1) }
            }
            if let v = element as? NSView {
                if let f = v as? NSTextField { out.append(f.stringValue) }
                if let b = v as? NSButton { out.append(b.title) }
                for sub in v.subviews { visit(sub, depth: depth + 1) }
            }
        }
        visit(root, depth: 0)
        return out
    }
}

extension SettingsSelfTest {
    static func captureStatsVariants(window w: NSWindow, frame: NSView, dir: URL) async {
        func scrollView(in view: NSView) -> NSScrollView? {
            if let s = view as? NSScrollView { return s }
            for sub in view.subviews { if let s = scrollView(in: sub) { return s } }
            return nil
        }
        func shot(_ name: String) {
            guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
            frame.cacheDisplay(in: frame.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: png)
            }
        }
        let saved = w.appearance
        for (label, appearance) in [("light", NSAppearance(named: .aqua)), ("dark", NSAppearance(named: .darkAqua))] {
            w.appearance = appearance
            let scroll = scrollView(in: w.contentView ?? frame)
            var page = 0
            while page < 6 {
                let visible = scroll?.contentView.bounds.height ?? 500
                let maxY = max(0, (scroll?.documentView?.frame.height ?? 0) - visible)
                let y = min(maxY, CGFloat(page) * (visible - 60))
                scroll?.contentView.scroll(to: NSPoint(x: 0, y: y))
                if let clip = scroll?.contentView { scroll?.reflectScrolledClipView(clip) }
                try? await Task.sleep(for: .seconds(0.5))
                shot("settings-stats-\(label)-\(page).png")
                if y >= maxY { break }
                page += 1
            }
            scroll?.contentView.scroll(to: .zero)
            scroll?.reflectScrolledClipView(scroll!.contentView)
        }
        w.appearance = saved
        let m = UsageStatsModel.shared
        let card = StatsShareCard(summary: UsageSummary(m.days, lastDays: 1, now: m.now), period: .today,
                                  series: UsageStatsLayout.dailySeries(m.days, count: UsageStatsPane.chartDays, now: m.now),
                                  metric: .characters)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        if let tiff = renderer.nsImage?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            FileManager.default.createFile(atPath: dir.appendingPathComponent("settings-stats-share.png").path, contents: png)
        }
    }
}

extension SettingsWindow {
    static var debugWindow: NSWindow? { window }
}

@MainActor
enum SettingsSnapshots {
    static func run() async {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--settings-snapshots"), i + 1 < args.count, !args[i + 1].hasPrefix("--") else {
            SettingsSnapshotsLine.emit(.usage)
            exit(2)
        }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var tabs = SettingsTab.allCases
        if let t = args.firstIndex(of: "--tabs"), t + 1 < args.count {
            let wanted = args[t + 1].split(separator: ",").map(String.init)
            tabs = tabs.filter { wanted.contains($0.rawValue) }
        }
        if args.contains("--dictionary-sample") { PersonalDictionaryStore.shared.useSample() }
        let suffix = args.contains("--expand-examples") ? "-expanded" : ""
        var count = 0
        for tab in tabs {
            SettingsWindow.show(tab)
            try? await Task.sleep(for: .seconds(0.6))
            guard let w = SettingsWindow.debugWindow, let frame = w.contentView?.superview ?? w.contentView else { exit(40) }
            count += await capturePages(window: w, frame: frame, dir: dir, prefix: "settings-\(tab.rawValue)\(suffix)")
        }
        SettingsSnapshotsLine.emit(.saved(count: count))
        exit(0)
    }

    static func capturePages(window w: NSWindow, frame: NSView, dir: URL, prefix: String) async -> Int {
        func scrollView(in view: NSView) -> NSScrollView? {
            if let s = view as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { return s }
            for sub in view.subviews { if let s = scrollView(in: sub) { return s } }
            return nil
        }
        var saved = 0
        let original = w.appearance
        for (label, appearance) in [("light", NSAppearance(named: .aqua)), ("dark", NSAppearance(named: .darkAqua))] {
            w.appearance = appearance
            try? await Task.sleep(for: .seconds(0.3))
            let scroll = scrollView(in: w.contentView ?? frame)
            var page = 0
            while page < 8 {
                let visible = scroll?.contentView.bounds.height ?? 500
                let maxY = max(0, (scroll?.documentView?.frame.height ?? 0) - visible)
                let y = min(maxY, CGFloat(page) * (visible - 60))
                if let scroll {
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                try? await Task.sleep(for: .seconds(0.4))
                if let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                    frame.cacheDisplay(in: frame.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        FileManager.default.createFile(atPath: dir.appendingPathComponent("\(prefix)-\(label)-\(page).png").path,
                                                       contents: png)
                        saved += 1
                    }
                }
                if scroll == nil || y >= maxY { break }
                page += 1
            }
            if let scroll {
                scroll.contentView.scroll(to: .zero)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        w.appearance = original
        return saved
    }
}

enum ConsentDisclosureCheck {
    static let required = [
        "按兩下 ⌃／⌥／⌘",
        "記下使用統計", "不記你說了什麼", "設定 › 統計 關掉或全部刪除",
        "「個人詞庫」", "「改成」那一欄的詞", "自動加進個人詞庫", "「自動加入」",
        "收集我的修改",
    ]

    static func firstMissing(in points: [String], extra: [String] = Edition.extraConsentDisclosures) -> Int? {
        let all = points.joined(separator: "\n")
        return (required + extra).firstIndex { !all.contains($0) }
    }
}
#endif
