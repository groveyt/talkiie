import Foundation
import NaturalInputCore
import NaturalInputEgress
import NaturalInputEgressPublic
import NaturalInputLocalASR
import NaturalInputModelDownload
import SwiftUI

enum PublicModel {
    final class Relay: @unchecked Sendable {
        private let lock = NSLock()
        private var target: LocalModelSetup?
        func connect(_ s: LocalModelSetup) { lock.withLock { target = s } }
        func forward(_ state: ModelInstallState) { lock.withLock { target }?.installerDidChange(state) }
    }

    private static let relay = Relay()

    static let installer = ModelInstaller(log: Edition.egressLog, root: PublicIdentity.modelsDirectory,
                                          onChange: { state in
                                              relay.forward(state)
                                              let now = ProcessInfo.processInfo.systemUptime
                                              Task { @MainActor in PublicModelStatus.shared.noteInstall(state, at: now) }
                                          })

    static let whisper = LocalWhisper(model: LocalWhisperModel(directory: installer.modelDirectory))

    static let setup: LocalModelSetup = {
        let s = LocalModelSetup(
            installer: installer,
            prepare: {
                do {
                    let report = try await whisper.prepare()
                    Log.record(.localModelPrepared(millis: report?.totalMillis))
                    return nil
                } catch let error as LocalWhisperError {
                    Log.record(.localModelPrepareFailed)
                    return error.userMessage
                } catch {
                    Log.record(.localModelPrepareFailed)
                    return LocalWhisper.failureMessage
                }
            },
            onChange: { _ in Task { @MainActor in PublicModelStatus.shared.phase = PublicModel.setup.phase } })
        relay.connect(s)
        return s
    }()
}

@MainActor
final class PublicModelStatus: ObservableObject {
    static let shared = PublicModelStatus()
    @Published var phase: LocalModelPhase = .checking
    @Published private(set) var progressLine: String?
    private var estimator = DownloadProgressEstimator()

    func noteInstall(_ state: ModelInstallState, at now: Double) {
        guard case .downloading(let received, let total) = state else {
            estimator.reset()
            progressLine = nil
            return
        }
        estimator.note(receivedBytes: received, totalBytes: total, at: now)
        progressLine = ModelDownloadText.progressLine(receivedBytes: received, totalBytes: total,
                                                      remainingSeconds: estimator.remainingSeconds)
    }

    func start() {
        Task.detached { await PublicModel.setup.start() }
    }

    func download() {
        Log.record(.localModelDownloadRequested)
        Task.detached { await PublicModel.setup.downloadAndPrepare() }
    }

    func cancelDownload() { PublicModel.setup.cancelDownload() }

    func redownload() {
        Log.record(.localModelDownloadRequested)
        Task.detached { await PublicModel.setup.redownloadAndPrepare() }
    }
}

struct PublicModelProgressBlock: View {
    let phase: LocalModelPhase
    let progressLine: String?
    @ObservedObject var status = PublicModelStatus.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch phase {
            case .notDownloaded:
                Label(Edition.Copy.modelBeforeDownloadNote, systemImage: "wifi")
                    .foregroundStyle(.secondary)
            case .downloading(let fraction):
                if let fraction { ProgressView(value: fraction) } else { ProgressView().controlSize(.small) }
                if let progressLine { Text(progressLine).font(.callout).foregroundStyle(.secondary).monospacedDigit() }
            case .installing, .preparing:
                ProgressView().controlSize(.small)
                Text(Edition.Copy.modelOneTimeNote).font(.callout).foregroundStyle(.secondary)
            case .downloadFailed, .prepareFailed:
                HStack {
                    if case .prepareFailed = phase {
                        Button(Edition.Copy.modelRedownloadButton) { status.redownload() }
                    }
                    if Edition.Copy.modelFailureOffersReport(phase) {
                        Button("回報問題…") { Edition.reportProblem() }
                    }
                }
            case .checking, .hostingUndecided, .ready:
                EmptyView()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct PublicOnboardingPracticeNotice: View {
    @ObservedObject var status = PublicModelStatus.shared

    var body: some View {
        let phase = status.phase
        if phase != .ready, phase != .checking {
            VStack(alignment: .leading, spacing: 8) {
                Label(Edition.Copy.modelStatusLine(phase), systemImage: "info.circle")
                    .fixedSize(horizontal: false, vertical: true)
                PublicModelProgressBlock(phase: phase, progressLine: status.progressLine)
                if phase.canStartDownload {
                    Button(Edition.Copy.modelDownloadButton(phase)) { status.download() }
                }
                Text("語音模型好之前還不能口述 —— 可以先按「完成」或「稍後再說」，之後模型好了再回來試（設定 › 關於 › 新手導覽…）。")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.35)))
        }
    }
}

struct PublicOnboardingModelStep: View {
    @ObservedObject var status = PublicModelStatus.shared

    var body: some View {
        let phase = status.phase
        VStack(alignment: .leading, spacing: 14) {
            Text("要口述之前，需要先下載語音模型（約 2 GB）。下載好之後第一次準備約需一分鐘。")
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Image(systemName: phase.allowsRecording ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(phase.allowsRecording ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(Edition.Copy.modelStatusLine(phase)).fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
            PublicModelProgressBlock(phase: phase, progressLine: status.progressLine)
            HStack {
                if phase.canStartDownload {
                    Button(Edition.Copy.modelDownloadButton(phase)) { status.download() }
                }
                if case .downloading = phase {
                    Button("取消下載（已下載的部分會保留）") { status.cancelDownload() }
                }
            }
            Text("不想現在下載也可以按「稍後再說」；之後在選單列 Talkiie →「下載語音模型…」隨時開始。沒有模型之前按熱鍵不會錄音。")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PublicModelStatusSection: View {
    @ObservedObject var status = PublicModelStatus.shared

    var body: some View {
        let phase = status.phase
        Text(Edition.Copy.modelStatusLine(phase)).foregroundStyle(phase.allowsRecording ? .secondary : .primary)
        switch phase {
        case .notDownloaded: Text(Edition.Copy.modelBeforeDownloadNote).foregroundStyle(.secondary)
        case .downloading: if let line = status.progressLine { Text(line).foregroundStyle(.secondary) }
        case .installing, .preparing: Text(Edition.Copy.modelOneTimeNote).foregroundStyle(.secondary)
        default: EmptyView()
        }
        if phase.canStartDownload {
            Button(Edition.Copy.modelDownloadButton(phase)) { status.download() }
        }
        if case .prepareFailed = phase {
            Button(Edition.Copy.modelRedownloadButton) { status.redownload() }
        }
        if Edition.Copy.modelFailureOffersReport(phase) {
            Button("回報問題…") { Edition.reportProblem() }
        }
        if case .downloading = phase {
            Button("取消下載（已下載的部分會保留）") { status.cancelDownload() }
        }
    }
}
