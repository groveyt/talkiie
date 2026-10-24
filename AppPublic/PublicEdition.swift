import AppKit
import NaturalInputCore
import NaturalInputEgress
import NaturalInputEgressPublic
import NaturalInputLocalASR
import NaturalInputModelDownload
import SwiftUI
import TalkiieLicensing

enum Edition {
    enum Copy {
        static let title = PublicConsentCopy.title
        static func points(hotkey: String) -> [String] { PublicConsentCopy.points(hotkey: hotkey) }
        static let acceptButton = PublicConsentCopy.acceptButton
        static let quitButton = PublicConsentCopy.quitButton
        static let destinationLine = PublicConsentCopy.destinationLine
        static let sendingLine = "轉錄中…"
        static let transcriptionPendingNotice = "上一句還在轉錄，這次沒有開始錄音；結果出來後再按"
        static func remoteUnreachableWarning(time: String) -> String { "⚠️ 上一次口述（\(time)）沒有轉錄成功" }
        static let correctionsSendPrivacyLine: String? = nil
        static let speculativeTailHelp: String? = nil
        static let speculativeTailToggle: String? = nil
        static let writtenStyleHelp: String? = nil
        static let timeoutMessage = "轉錄沒有回應，這段口述沒有轉錄"
        static let emptyTranscriptNotice = "沒有聽出任何文字"
        static let chunksSentLogSuffix = ""
        static let personalDictionaryNote = "這張表只存在這台 Mac；\(TranscriptionPrompt.whenUsedClause)，"
            + "「改成」那一欄的詞會在這台 Mac 上幫忙認字，不會送出。"
        static func personalDictionaryPromptSummary(sent: Int, total: Int) -> String { "目前用上 \(sent)/\(total) 個詞" }
        static let personalDictionaryNotSentFull = "沒用上：提示詞滿了"
        static let personalDictionaryNotSentNotAWord = "沒用上：不像一個詞"
        static let reportProblemNote = "會在瀏覽器打開 talkiie.yyt.app 的回報頁，只帶版本號與 macOS 版本；要寫什麼、送不送由你決定。"

        static func modelStatusLine(_ p: LocalModelPhase) -> String {
            switch p {
            case .checking: return "正在檢查本機語音模型…"
            case .notDownloaded: return "還沒下載語音模型，現在按熱鍵不會錄音"
            case .hostingUndecided: return "模型下載尚未開放，現在還不能口述"
            case .downloading(let f):
                return f.map { "下載語音模型中… \(Int(($0 * 100).rounded(.down)))%" } ?? "下載語音模型中…"
            case .installing: return "正在驗證並安裝語音模型…"
            case .preparing: return "第一次準備語音模型，約需一分鐘（之後開啟只要幾秒）"
            case .ready: return "本機語音模型已就緒"
            case .downloadFailed(let f): return "語音模型下載失敗：" + downloadFailureReason(f)
            case .prepareFailed(let m): return m
            }
        }

        static func modelDownloadButton(_ p: LocalModelPhase) -> String {
            switch p {
            case .downloadFailed(let f) where f.keepsPartialDownload: return "繼續下載語音模型…"
            case .downloadFailed, .prepareFailed: return "重試：下載並準備語音模型…"
            default: return "下載語音模型（約 2 GB）…"
            }
        }

        static func modelNotReadyNotice(_ p: LocalModelPhase) -> String {
            switch p {
            case .hostingUndecided: return "模型下載尚未開放，錄音沒有開始"
            case .downloading, .installing: return "語音模型還在下載，錄音沒有開始"
            case .preparing, .checking: return "正在準備語音模型，請稍候再按"
            case .notDownloaded, .downloadFailed, .prepareFailed:
                return "還沒下載語音模型，錄音沒有開始（選單列 Talkiie →「下載語音模型…」）"
            case .ready: return ""
            }
        }

        static func downloadFailureReason(_ f: ModelInstallFailure) -> String { ModelDownloadText.failureReason(f) }

        static func modelFailureOffersReport(_ p: LocalModelPhase) -> Bool {
            switch p {
            case .downloadFailed(let f): return ModelDownloadText.offersReport(for: f)
            case .prepareFailed: return true
            default: return false
            }
        }

        static let modelBeforeDownloadNote = "建議用 Wi-Fi，約 2 GB"
        static let modelOneTimeNote = "這一步只需要做一次"
        static let modelRedownloadButton = "重新下載語音模型…"
    }

    static let logSubsystem = PublicIdentity.logSubsystem
    static let consentVersion = PublicIdentity.consentVersion
    static var dataDirectory: URL { PublicIdentity.dataDirectory }

    static let egressLog = EgressLog(directory: AppModel.egressLogDirectory)

    static let transcriptionFailureMessage = LocalWhisper.failureMessage
    static let transcriberSampleRate = LocalWhisper.sampleRate

    @MainActor static func consentGranted() {
        Updater.shared.start()
        LaunchAtLogin.shared.autoRegisterIfNeeded()
        PublicModelStatus.shared.start()
    }

    #if DEBUG
    static let launchAtLoginDefaultOn = false
    #else
    static let launchAtLoginDefaultOn = true
    #endif

    @MainActor static func reportProblem() { NSWorkspace.shared.open(feedbackURL) }

    static func isRemoteUnreachable(_ message: String) -> Bool { false }
    static let timeoutMeansRemoteUnreachable = false

    @MainActor static func recordingStartRefusal() -> String? {
        let phase = PublicModel.setup.phase
        return phase.allowsRecording ? nil : Copy.modelNotReadyNotice(phase)
    }

    static let tailWorkKey: LatencyStages.TailWorkKey = .infer

    static let offersSpeculativeTail = false
    @MainActor static var speculativeTailAllowed: Bool { offersPlus && PublicLicense.shared.entitlement.isUnlocked(.speed) }

    static let offersPlus = false

    @MainActor static var plusUnlocked: Bool { offersPlus && PublicLicense.shared.entitlement.isUnlocked(.themes) }

    static let offersWrittenStyle = false
    struct CorrectionsSendRow: View { var body: some View { EmptyView() } }
    static let offersCorrectionsSend = false
    static let destinationSymbol = "laptopcomputer"
    static let offersPhoneApp = false

    static let extraConsentDisclosures: [String] = []

    static let releaseNotesResource = "releases-public"

    struct MenuHeader: View {
        var body: some View { PendingUpdateSection() }
    }

    @MainActor static func launched(consented: Bool) { WhatsNew.shared.launched(consented: consented) }

    static let onboardingHasModelStep = true
    struct OnboardingModelStep: View {
        var body: some View { PublicOnboardingModelStep() }
    }
    struct OnboardingPracticeNotice: View {
        var body: some View { PublicOnboardingPracticeNotice() }
    }

    struct StatusSection: View {
        var body: some View { PublicModelStatusSection() }
    }

    @MainActor static func willFinishLaunching() {
        if offersPlus { PublicLicense.shared.installAtLaunch() }
    }

    struct ExtraSpeedSection: View {
        var body: some View {
            if Edition.offersPlus { PublicSpeedSection() }
        }
    }

    struct UpdateChecksSection: View {
        @ObservedObject private var updater = Updater.shared
        var body: some View {
            if Updater.availableInThisBuild {
                Section {
                    Toggle("自動檢查更新", isOn: Binding(get: { updater.autoChecks }, set: { updater.setAutoChecks($0) }))
                    Text("開著時，Talkiie 每天向 Talkiie 官網抓一份更新清單（不帶你的資料，見隱私頁）。關掉就不會自己連網，要更新時按「檢查更新…」。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @MainActor static var updateIdleStatusText: String {
        Updater.shared.autoChecks ? "每天自動檢查更新" : "自動檢查更新已關閉"
    }

    struct PlusSection: View {
        var body: some View {
            if Edition.offersPlus { PublicPlusSection() }
        }
    }

    static var version: (short: String, build: String) {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String ?? "?", info?["CFBundleVersion"] as? String ?? "?")
    }

    static var feedbackURL: URL {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return PublicUpdatePolicy.feedbackURL(build: "\(version.short) (\(version.build))",
                                              os: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    }
}

extension AppModel {
    static func makeTranscriber() -> LocalWhisper { PublicModel.whisper }

    static func makeWarmer(for transcriber: LocalWhisper) -> WhisperWarmer? { nil }

    static func makePunctuator() -> (any Punctuator)? { nil }

    static func makeRewriter() -> (any Rewriter)? { nil }
}
