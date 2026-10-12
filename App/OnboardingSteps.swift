import AppKit
import NaturalInputCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var controller: OnboardingController

    static let width: CGFloat = 580
    static let height: CGFloat = 680

    private var step: OnboardingPlan.Step { controller.currentStep }
    private var onlyFeatures: Bool { controller.steps == [.features] }

    private var title: String {
        switch step {
        case .permissions: return "先允許兩個權限"
        case .model: return "下載語音模型"
        case .start: return "怎麼開始說話"
        case .features: return onlyFeatures ? "Talkiie 還能做的事" : "你可能會想打開的"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch step {
                    case .permissions: OnboardingPermissionsStep()
                    case .model: Edition.OnboardingModelStep()
                    case .start: OnboardingStartStep()
                    case .features: OnboardingFeaturesStep(onlyFeatures: onlyFeatures)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: Self.width, height: Self.height)
        .environmentObject(AppModel.shared)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.title2.weight(.semibold))
                    Text(Edition.Copy.destinationLine).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if !onlyFeatures {
                    Button("略過導覽") { controller.skipForGood() }
                        .buttonStyle(.link)
                        .help("之後想再看：設定 › 關於 › 新手導覽…")
                }
            }
            if !onlyFeatures { progress }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<controller.steps.count, id: \.self) { i in
                Capsule()
                    .fill(i <= controller.index ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 4)
            }
            Text("步驟 \(controller.index + 1)／\(controller.steps.count)")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("步驟 \(controller.index + 1)，共 \(controller.steps.count) 步")
    }

    private var footer: some View {
        HStack {
            if !onlyFeatures {
                Button("稍後再說") { controller.later() }
                    .help("先關掉，選單列最上面會留一行「完成設定導覽」，隨時回來。")
            }
            Spacer()
            if controller.index > 0 {
                Button("上一步") { controller.back() }
            }
            Button(controller.isLast ? "完成" : "下一步") { controller.next() }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

struct OnboardingPermissionsStep: View {
    @EnvironmentObject var model: AppModel
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("Talkiie 只需要這兩個權限：「麥克風」錄下你說的話，「輔助使用」把文字打進你正在用的 app。允許之後這裡會自動打勾。")
            .fixedSize(horizontal: false, vertical: true)
        Form {
            Section {
                PermissionSettingsRow(symbol: "mic", title: "麥克風", detail: "錄下你說的話",
                                      item: PermissionGuidance.microphoneItem(model.permissions.microphone))
                PermissionSettingsRow(symbol: "accessibility", title: "輔助使用", detail: "把文字打進其他 app",
                                      item: PermissionGuidance.accessibilityItem(
                                          trusted: model.permissions.accessibilityTrusted,
                                          prompted: model.permissions.accessibilityPrompted))
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        HStack {
            Button("重新檢查") { model.refreshPermissions() }
            Spacer()
            if model.permissions.microphone == .granted, model.permissions.accessibilityTrusted {
                Label("兩個權限都允許了，可以按「下一步」", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        SettingsHelp(text: "按「允許…」後系統會跳出對話框；沒有跳出來的話，按「打開系統設定…」，在清單裡把 Talkiie 的開關打開。"
                     + "輔助使用打開之後如果這裡沒有馬上打勾，按「重新檢查」。")
            .onReceive(tick) { _ in model.refreshPermissions() }
    }
}

struct OnboardingStartStep: View {
    @EnvironmentObject var model: AppModel
    @AppStorage(TapHotkey.defaultsKey) private var tap: TapHotkey = .off

    var body: some View {
        VStack(spacing: 6) {
            if let phrase = tap.menuPhrase?.trimmingCharacters(in: .whitespaces) {
                Text(phrase)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                Text("或 \(model.hotkey.label)")
                    .font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    .accessibilityLabel("或 \(model.hotkey.spoken)")
            } else {
                Text(model.hotkey.label)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .accessibilityLabel(model.hotkey.spoken)
            }
            Text("文字會打在游標所在的地方")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .combine)

        Text("挑一個你順手的開始方式（預設可以不動）。想換就在這裡換，之後也能在 設定 › 一般 改。")
            .fixedSize(horizontal: false, vertical: true)
        Form {
            Section("開始說話") { HotkeySettingsSection() }
            Section("結束說話") { StopTriggerSettingsSection() }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)

        Label("選好之後，到任何 app 的輸入欄位按 \(model.hotkey.label)\(tap.menuPhrase.map { " 或\($0)" } ?? "") 試試。", systemImage: "arrow.right.circle")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct OnboardingFeaturesStep: View {
    let onlyFeatures: Bool
    @AppStorage(FillerRemoval.defaultsKey) private var fillerRaw = FillerRemoval.defaultStrength.rawValue
    @AppStorage(SpokenCommands.defaultsKey) private var spokenCommands = SpokenCommands.defaultEnabled

    var body: some View {
        Text(onlyFeatures
             ? "更新之後多了一些你可能會想用的功能。下面每一項都由你決定要不要打開，之後也能在 設定 隨時改。"
             : "下面這些功能預設沒有全部打開。每一項都由你決定，之後也能在 設定 隨時改。")
            .fixedSize(horizontal: false, vertical: true)

        let strength = FillerRemoval.strength(fromDefaults: fillerRaw)
        OnboardingCard(symbol: "scissors", title: "刪除贅字",
                       summary: "把「嗯」「那個」「就是」這類口頭禪自動刪掉，只刪不改。") {
            Picker("強度", selection: Binding(get: { strength }, set: { fillerRaw = $0.rawValue })) {
                ForEach(FillerStrength.allCases, id: \.self) { s in
                    Text(s.title + (s == FillerRemoval.defaultStrength ? "（預設）" : "")).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            SettingsHelp(text: strength.detail + "。刪超過四分之一就原樣保留。")
            VStack(alignment: .leading, spacing: 4) {
                Text("說的是").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(FillerRemoval.example).fixedSize(horizontal: false, vertical: true)
                Text("打出來的是").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
                Text(FillerRemoval.apply(FillerRemoval.example, strength: strength).text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }

        OnboardingCard(symbol: "character.book.closed", title: "個人詞庫",
                       summary: "人名、產品名、專有名詞老是被聽錯？加進詞庫，Talkiie 會幫忙認出來、改對。") {
            Button("打開詞庫設定") { SettingsWindow.show(.text) }
        }

        OnboardingCard(symbol: "pencil.and.list.clipboard", title: "收集我的修改",
                       summary: "改完剛打出來的字之後按一個快捷鍵，Talkiie 會從你的修改學習。預設關閉，由你自己打開。") {
            EditCaptureToggleRow()
        }

        if Edition.offersWrittenStyle {
            OnboardingCard(symbol: "text.badge.checkmark", title: "整理成書面語",
                           summary: "講完之後自動刪掉口語的贅字再打出來。預設關閉，由你自己打開。") {
                WrittenStyleToggleRow()
            }
        }

        OnboardingCard(symbol: "return", title: "排版指令「換行」「新段落」",
                       summary: "口述時單獨說一句「換行」或「新段落」，就直接換行、空一行。") {
            Toggle("口述「換行」「新段落」", isOn: $spokenCommands)
            SettingsHelp(text: "只有指令單獨成一句時才算（「我要換行李」不會動）；指令詞本身不會打出來。預設關。")
            VStack(alignment: .leading, spacing: 4) {
                Text("說的是").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(SpokenCommands.example).fixedSize(horizontal: false, vertical: true)
                Text("打出來的是").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 2)
                Text(TranscriptFormatter.format([TranscriptSegment(text: SpokenCommands.example, start: 0, end: 3)],
                                                spokenCommands: spokenCommands))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
        }

        Label("想找回剛說過的字：選單列 Talkiie →「最近口述」。想看用了多少：設定 › 統計。",
              systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

struct OnboardingCard<Content: View>: View {
    let symbol: String
    let title: String
    let summary: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.12)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(summary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        .accessibilityElement(children: .contain)
    }
}
