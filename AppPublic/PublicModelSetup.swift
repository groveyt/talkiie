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
                                          onChange: { relay.forward($0) })

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

    func start() {
        Task.detached { await PublicModel.setup.start() }
    }

    func download() {
        Log.record(.localModelDownloadRequested)
        Task.detached { await PublicModel.setup.downloadAndPrepare() }
    }

    func cancelDownload() { PublicModel.setup.cancelDownload() }
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
            if case .downloading(let fraction) = phase, let fraction {
                ProgressView(value: fraction)
            } else if case .downloading = phase {
                ProgressView().controlSize(.small)
            }
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
        if phase.canStartDownload {
            Button(Edition.Copy.modelDownloadButton(phase)) { status.download() }
        }
        if case .downloading = phase {
            Button("取消下載（已下載的部分會保留）") { status.cancelDownload() }
        }
    }
}
