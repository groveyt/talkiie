import AppKit
import NaturalInputCore
import SwiftUI

let paneWidth: CGFloat = 520

var scrollingPaneHeight: CGFloat {
    let available = (NSScreen.main?.visibleFrame.height ?? 900) - 140
    return min(700, max(420, available))
}

struct SettingsHelp: View {
    let text: String
    var warn = false

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(warn ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
enum AboutInfo {
    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Talkiie \(short)（\(build)）" + (Updater.availableInThisBuild ? "" : " · 開發版，不自動更新")
    }

    static var versionNumber: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "版本 \(short)（\(build)）"
    }
}

struct HotkeySettingsSection: View {
    @EnvironmentObject var model: AppModel
    @State private var hotkeyMessage: String?
    @AppStorage(TapHotkey.defaultsKey) private var tap: TapHotkey = .off
    @AppStorage(StopTrigger.defaultsKey) private var storedStop = StopTrigger.defaultValue.rawValue

    var body: some View {
        FnHotkeySettingsSection()
        LabeledContent("快捷鍵") {
            HStack(spacing: 6) {
                HotkeyRecorder(message: $hotkeyMessage)
                if model.hotkey != .standard {
                    Button {
                        hotkeyMessage = model.setHotkey(.standard)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("恢復成 \(HotkeyCombo.standard.label)")
                    .accessibilityLabel("恢復成 \(HotkeyCombo.standard.label)")
                }
            }
        }
        if let m = hotkeyMessage {
            SettingsHelp(text: m, warn: true)
        } else if !model.hotkeyRegistered {
            SettingsHelp(text: "\(model.hotkey.label) 無法使用（可能被其他 app 佔用），請換一個。", warn: true)
        }
        SettingsHelp(text: StartStopSettings.summary(hotkey: model.hotkey.label, tap: tap,
                                                     stop: StopTrigger.resolve(stored: storedStop)))
    }
}

struct GeneralPane: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var launch = LaunchAtLogin.shared
    @ObservedObject private var settingsRefresh = SettingsRefresh.shared
    @AppStorage(StartChime.enabledDefaultsKey) private var chime = StartChime.enabledByDefault
    @AppStorage(FeatureNudgePlan.enabledDefaultsKey) private var nudgeEnabled = FeatureNudgePlan.enabledDefault
    @AppStorage(StartChime.presetDefaultsKey) private var presetRaw = StartChime.defaultPreset.rawValue
    @AppStorage(CapsuleStyle.defaultsKey) private var capsuleStyleRaw = CapsuleStyle.defaultValue.rawValue
    @AppStorage(HUDTheme.defaultsKey) private var themeRaw = HUDTheme.defaultValue.rawValue
    @ObservedObject private var themeTrial = ThemeTrialPreview.shared
    @State private var plusHint: String?

    var body: some View {
        Form {
            Section("開始說話") {
                HotkeySettingsSection()
            }
            Section("結束說話") {
                StopTriggerSettingsSection()
            }
            Section("麥克風") {
                InputDeviceSettingsSection()
            }
            Section("提示音") {
                Toggle("開始與結束時播放提示音", isOn: $chime)
                Picker("樣式", selection: Binding(get: { StartChime.effectivePreset(stored: presetRaw, unlocked: Edition.plusUnlocked) },
                                                 set: { p in
                                                     guard !p.requiresPlus || Edition.plusUnlocked else {
                                                         plusHint = PaidFeatureCopy.lockedHint(p.title)
                                                         StartChimePlayer.shared.preview(p)
                                                         return
                                                     }
                                                     plusHint = nil
                                                     presetRaw = p.rawValue
                                                     StartChimePlayer.shared.preview(p)
                                                 })) {
                    ForEach(StartChime.Preset.pickerOptions(unlocked: Edition.plusUnlocked, offersPlus: Edition.offersPlus),
                            id: \.self) { preset in
                        Text(preset.title + (preset == StartChime.defaultPreset ? "（預設）" : "")
                             + (preset.requiresPlus && !Edition.plusUnlocked ? PaidFeatureCopy.lockedSuffix : "")).tag(preset)
                    }
                }
                .disabled(!chime)
                HStack {
                    SettingsHelp(text: "選了就試聽一次：先是開始的聲音，再是結束的聲音。")
                    Spacer()
                    Button("試聽") { StartChimePlayer.shared.preview(StartChimePlayer.preset) }
                }
                if let hint = plusHint {
                    SettingsHelp(text: hint + PaidFeatureCopy.unlockHowTo, warn: true)
                }
            }
            if HUDTheme.pickerOptions(unlocked: Edition.plusUnlocked, offersPlus: Edition.offersPlus).count > 1 {
                Section("佈景") {
                    Picker("樣式", selection: Binding(
                        get: { HUDTheme.effective(stored: themeRaw, unlocked: Edition.plusUnlocked) },
                        set: { t in
                            guard !t.requiresPlus || Edition.plusUnlocked else {
                                plusHint = PaidFeatureCopy.lockedHint(t.title)
                                themeTrial.start(t)
                                return
                            }
                            plusHint = nil
                            themeTrial.stop()
                            themeRaw = t.rawValue
                        })) {
                        ForEach(HUDTheme.pickerOptions(unlocked: Edition.plusUnlocked, offersPlus: Edition.offersPlus)) { t in
                            Text(t.title + (t.requiresPlus && !Edition.plusUnlocked ? PaidFeatureCopy.lockedSuffix : "")).tag(t)
                        }
                    }
                    if let active = themeTrial.active {
                        SettingsHelp(text: PaidFeatureCopy.previewLine(active.title))
                    } else {
                        SettingsHelp(text: HUDTheme.effective(stored: themeRaw, unlocked: Edition.plusUnlocked).detail)
                        if let hint = plusHint {
                            SettingsHelp(text: hint + PaidFeatureCopy.unlockHowTo, warn: true)
                        }
                    }
                }
            }
            Section("膠囊樣式") {
                Picker("樣式", selection: Binding(
                    get: { CapsuleStyle.resolve(stored: capsuleStyleRaw) },
                    set: { capsuleStyleRaw = $0.rawValue })) {
                    ForEach(CapsuleStyle.allCases, id: \.self) { s in
                        Text(s.title + (s == CapsuleStyle.defaultValue ? "（預設）" : "")).tag(s)
                    }
                }
                .pickerStyle(.segmented)
                SettingsHelp(text: CapsuleStyle.resolve(stored: capsuleStyleRaw).detail)
            }
            if Edition.offersSpeculativeTail {
                Section("速度") {
                    SpeculativeTailSettingsSection()
                }
            }
            Edition.ExtraSpeedSection()
            Section("功能提示") {
                Toggle("偶爾提示還沒用過的功能", isOn: $nudgeEnabled)
                SettingsHelp(text: "最多每週一則，出現在選單列最上面一行（「💡 試試：…」）；只會帶你去對應的設定頁，不會替你打開任何功能，也不連網。"
                             + "點「不用了」的功能不會再提。")
            }
            Section("啟動") {
                Toggle("登入 Mac 時自動打開 Talkiie", isOn: Binding(
                    get: { LaunchAtLoginPolicy.toggleIsOn(launch.status) },
                    set: { launch.set($0) }))
                if let hint = LaunchAtLoginPolicy.hint(launch.status, registerFailed: launch.registerFailed) {
                    SettingsHelp(text: hint.text, warn: true)
                    if hint.needsSettingsButton {
                        HStack {
                            Spacer()
                            Button("打開登入項目設定…") { launch.openLoginItemsSettings() }
                        }
                    }
                } else {
                    SettingsHelp(text: "建議打開：沒開著的 Talkiie 按熱鍵不會有反應。")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: scrollingPaneHeight)
    }
}

struct TextPane: View {
    @AppStorage(FillerRemoval.defaultsKey) private var fillerRaw = FillerRemoval.defaultStrength.rawValue
    @AppStorage(SpokenList.defaultsKey) private var spokenLists = SpokenList.defaultEnabled
    @AppStorage(ListToggle.defaultsKey) private var listToggle = ListToggle.defaultEnabled
    @AppStorage(SpokenCommands.defaultsKey) private var spokenCommands = SpokenCommands.defaultEnabled
    @AppStorage(SemanticParagraphs.defaultsKey) private var paragraphRaw = SemanticParagraphs.defaultStrength.rawValue

    var body: some View {
        let strength = FillerRemoval.strength(fromDefaults: fillerRaw)
        let paragraphing = SemanticParagraphs.strength(fromDefaults: paragraphRaw)
        Form {
            PersonalDictionarySection(store: .shared)

            Section {
                FeatureSegmentedRow(title: "刪除贅字", summary: "把「嗯」「那個」這類口頭禪刪掉，只刪不改。",
                                    options: FillerStrength.allCases, label: \.title,
                                    defaultValue: FillerRemoval.defaultStrength,
                                    selection: Binding(get: { strength }, set: { fillerRaw = $0.rawValue }))
                ExampleDisclosure {
                    let preview = strength == .off ? FillerStrength.medium : strength
                    SettingsHelp(text: "「\(preview.title)」：\(preview.detail)。刪超過四分之一就原樣保留。")
                    DeletionExample(original: FillerRemoval.example,
                                    result: FillerRemoval.apply(FillerRemoval.example, strength: preview).text,
                                    resultCaption: strength == .off ? "選「\(preview.title)」時打出來的是" : "打出來的是")
                }
            }

            if Edition.offersWrittenStyle {
                Section {
                    WrittenStyleSettingsSection()
                }
            }

            Section {
                FeatureToggleRow(title: "把口述的清單排成條列",
                                 summary: "說「第一點…第二點…」時自動排成編號清單；關掉就照原樣打成一段。",
                                 isOn: $spokenLists)
                FeatureToggleRow(title: "插完後讓我切換項目編號",
                                 summary: "跟清單有關的那一句插完後，膠囊旁邊會出現「移除項目編號」或「加入項目編號」，按了才換；"
                                    + "約 8 秒後、或你開始打字就消失。",
                                 isOn: $listToggle)
                    .disabled(!spokenLists)
                ExampleDisclosure {
                    ExampleBlock(caption: "說的是") { Text(SpokenList.example) }
                    ExampleBlock(caption: spokenLists ? "打出來的是" : "打開之後打出來的是") {
                        Text(TranscriptFormatter.format([TranscriptSegment(text: SpokenList.example, start: 0, end: 3)],
                                                        spokenLists: true))
                    }
                }
            }

            Section {
                FeatureSegmentedRow(title: "長口述自動分段", summary: "長的口述自動分段；積極會分得比較細。",
                                    options: ParagraphStrength.allCases, label: \.title,
                                    defaultValue: SemanticParagraphs.defaultStrength,
                                    selection: Binding(get: { paragraphing }, set: { paragraphRaw = $0.rawValue }))
                SettingsHelp(text: "多行欄位用 Shift+Return 換段；如果你的 app 把 Shift+Return 當成送出，請調低或關掉。")
                    .font(.caption)
                ExampleDisclosure {
                    let preview = paragraphing == .off ? ParagraphStrength.standard : paragraphing
                    SettingsHelp(text: "「\(preview.title)」：\(preview.detail)。")
                    ExampleBlock(caption: paragraphing == .off ? "選「\(preview.title)」時打出來的是" : "打出來的是") {
                        Text(TranscriptFormatter.format([TranscriptSegment(text: SemanticParagraphs.example, start: 0, end: 30)],
                                                        spokenLists: spokenLists, paragraphing: preview))
                    }
                }
            }

            Section {
                FeatureToggleRow(title: "口述「換行」「新段落」",
                                 summary: "單獨說一句「換行」就換一行，「新段落」或「下一段」就空一行。",
                                 isOn: $spokenCommands)
                ExampleDisclosure {
                    SettingsHelp(text: "只有指令單獨成一句時才算（「我要換行李」不會動）；指令詞本身不會打出來。")
                    ExampleBlock(caption: "說的是") { Text(SpokenCommands.example) }
                    ExampleBlock(caption: spokenCommands ? "打出來的是" : "打開之後打出來的是") {
                        Text(TranscriptFormatter.format([TranscriptSegment(text: SpokenCommands.example, start: 0, end: 3)],
                                                        spokenCommands: true))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: scrollingPaneHeight)
    }
}

struct PrivacyPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("資料去向") {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: Edition.destinationSymbol)
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                    Text(Edition.Copy.destinationLine)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 6) {
                    PrivacyFact(symbol: "doc.badge.ellipsis", crossed: true, text: "不存檔、不記你說了什麼。")
                    PrivacyFact(symbol: "lock", text: "其他資料只留在這台 Mac，不會外送。")
                }
                DisclosureGroup("完整說明（同意時看過的內容）") {
                    ForEach(Array(Edition.Copy.points(hotkey: AppModel.hotkeyStartPhrase).enumerated()), id: \.offset) { _, point in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            Text(point).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.callout)
                    }
                }
            }
            Section {
                EditCaptureSettingsSection()
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: scrollingPaneHeight)
    }
}

private struct PrivacyFact: View {
    let symbol: String
    var crossed = false
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .overlay {
                    if crossed {
                        Rectangle().fill(.secondary).frame(width: 20, height: 1.2).rotationEffect(.degrees(-35))
                    }
                }
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }
}

struct PermissionsPane: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var refresh = SettingsRefresh.shared
    @AppStorage(TapHotkey.defaultsKey) private var tapHotkey: TapHotkey = .off
    @AppStorage(StopTrigger.defaultsKey) private var storedStop = StopTrigger.defaultValue.rawValue

    private var needsInputMonitoring: Bool {
        tapHotkey.needsInputMonitoring || StopTrigger.resolve(stored: storedStop).needsInputMonitoring
    }

    var body: some View {
        let _ = refresh.generation
        Form {
            Section {
                PermissionSettingsRow(symbol: "mic", title: "麥克風", detail: "錄下你說的話",
                                      item: PermissionGuidance.microphoneItem(model.permissions.microphone))
                PermissionSettingsRow(symbol: "accessibility", title: "輔助使用", detail: "把文字打進其他 app",
                                      item: PermissionGuidance.accessibilityItem(
                                          trusted: model.permissions.accessibilityTrusted,
                                          prompted: model.permissions.accessibilityPrompted))
                PermissionSettingsRow(symbol: "keyboard", title: "輸入監控", detail: "只看 fn 有沒有按下，不看你打的字",
                                      item: Self.inputMonitoringItem(FnHotkeyMonitor.inputMonitoringAllowed),
                                      needed: needsInputMonitoring,
                                      notNeededReason: "只有選 fn 時才用到",
                                      extraAction: FnHotkeyMonitor.openInputMonitoringSettings)
            } footer: {
                SettingsHelp(text: "Talkiie 只需要麥克風與輔助使用。")
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refreshPermissions() }
    }
}

extension PermissionsPane {
    static func inputMonitoringItem(_ allowed: Bool) -> PermissionGuidance.Item {
        allowed ? PermissionGuidance.Item(status: "已允許")
            : PermissionGuidance.Item(status: "允許之後要重新打開 Talkiie", buttonTitle: "打開系統設定…")
    }
}

struct PermissionSettingsRow: View {
    @EnvironmentObject var model: AppModel
    var symbol: String?
    let title: String
    let detail: String
    let item: PermissionGuidance.Item
    var needed = true
    var notNeededReason: String?
    var extraAction: (() -> Void)? = nil

    private var granted: Bool { item.status.hasSuffix("已允許") }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let symbol { SettingsIcon(symbol: symbol, size: 26) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if needed, !granted, let note = Self.note(item, title: title) {
                    Text(note).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            status
        }
        .opacity(needed || granted ? 1 : 0.85)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var status: some View {
        if !needed {
            VStack(alignment: .trailing, spacing: 1) {
                Text(granted ? "已允許・目前用不到" : "不需要").foregroundStyle(.secondary)
                if !granted, let notNeededReason {
                    Text(notNeededReason).font(.caption).foregroundStyle(.tertiary)
                }
            }
        } else if granted {
            Label("已允許", systemImage: "checkmark.circle.fill")
                .labelStyle(GrantedLabelStyle())
        } else if let t = item.buttonTitle {
            Button(Self.buttonTitle(t, action: item.action)) {
                if let action = item.action { model.perform(action) } else { extraAction?() }
            }
        } else {
            Text(Self.shortStatus(item.status, title: title)).foregroundStyle(.secondary)
        }
    }

    static func buttonTitle(_ original: String, action: PermissionGuidance.Action?) -> String {
        switch action {
        case .requestMicrophone, .promptAccessibility: return "允許…"
        case .openMicrophoneSettings, .openAccessibilitySettings: return "打開系統設定…"
        case nil: return original
        }
    }

    static func note(_ item: PermissionGuidance.Item, title: String) -> String? {
        let s = shortStatus(item.status, title: title)
        if let r = s.range(of: " —— ") { return String(s[r.upperBound...]) }
        if item.action == nil, item.buttonTitle != nil { return s }
        return nil
    }

    static func shortStatus(_ status: String, title: String) -> String {
        status.hasPrefix(title + "：") ? String(status.dropFirst(title.count + 1)) : status
    }
}

private struct GrantedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.foregroundStyle(.green)
            configuration.title.foregroundStyle(.secondary)
        }
    }
}

struct AboutPane: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Talkiie").font(.title2.weight(.semibold))
                        Text(AboutInfo.versionNumber).foregroundStyle(.secondary).textSelection(.enabled)
                        updateStatus
                    }
                    Spacer(minLength: 8)
                    if Updater.availableInThisBuild {
                        if updater.available != nil {
                            Button("更新…") { updater.showUpdate() }
                        } else {
                            Button("檢查更新…") { updater.checkForUpdates() }
                                .disabled(!updater.canCheck)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            Edition.UpdateChecksSection()
            Edition.PlusSection()
            Section("了解 Talkiie") {
                NavigationRow(symbol: "sparkles", title: "這一版的新功能",
                              enabled: WhatsNew.hasNotesForCurrent) { WhatsNew.shared.show() }
                NavigationRow(symbol: "graduationcap", title: "新手導覽") {
                    OnboardingController.shared.reopen()
                }
                NavigationRow(symbol: "square.grid.2x2", title: "Talkiie 能做的事") { FeatureMapWindow.show() }
            }
            Section("支援") {
                NavigationRow(symbol: "exclamationmark.bubble", title: "回報問題…", detail: Edition.Copy.reportProblemNote,
                              showsChevron: false) { Edition.reportProblem() }
            }
            Section {
                NavigationRow(symbol: "doc.text", title: "第三方授權") { NoticesWindow.show() }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var updateStatus: some View {
        if !Updater.availableInThisBuild {
            Text("開發版・不自動更新").font(.callout).foregroundStyle(.secondary)
        } else if let v = updater.available {
            Label("有新版可以更新（\(v)）", systemImage: "arrow.down.circle.fill")
                .font(.callout).foregroundStyle(.primary)
        } else {
            Text(Edition.updateIdleStatusText).font(.callout).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
struct DeveloperPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            #if RESEARCH_CAPTURE
            Section("研究錄音（decisions/0013）") {
                ResearchMenuSection()
            }
            ReadScriptDeveloperSection()
            #endif
            Section("預覽 HUD（debug）") {
                HStack {
                    Button("錄音中") { model.debugPreviewRecording() }
                    Button("轉錄完成") { model.debugPreviewTranscriptionDone() }
                    Button("轉錄失敗") { model.debugPreviewTranscriptionFailed() }
                }
                Menu("插字結果") {
                    ForEach(Array(HUDSelfTest.deliveryOutcomes.enumerated()), id: \.offset) { i, outcome in
                        Button("插字結果 \(i + 1)：\(DeliveryContent(outcome).title)") {
                            model.debugFinishRound("HUD 預覽用的假口述文字。", simulated: outcome)
                        }
                    }
                }
                Menu("停止原因") {
                    ForEach(RecordingStopReasonMenu.all, id: \.self) { reason in
                        Button("停止：\(reason.rawValue)") { model.recordingStopped(reason) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
#endif

private struct SpeculativeTailSettingsSection: View {
    @AppStorage(SpeculativeTailSetting.defaultsKey) private var enabled = SpeculativeTailSetting.defaultEnabled

    var body: some View {
        if let label = Edition.Copy.speculativeTailToggle { Toggle(label, isOn: $enabled) }
        if let help = Edition.Copy.speculativeTailHelp { SettingsHelp(text: help) }
    }
}
