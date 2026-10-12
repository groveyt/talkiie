import Foundation

public enum LatencyMark: Int, CaseIterable, Sendable {
    case hotkeyPressed
    case engineRunning
    case firstAudio
    case stopPressed
    case targetFrozen
    case engineStopped
    case tailHandedOff
    case textReady
    case converted
    case insertionStarted
    case firstKeystroke
    case insertionDone
}

public struct RequestTiming: Equatable, Sendable {
    public var prepMillis: Int?
    public var networkMillis: Int?
    public var parseMillis: Int?
    public var hallucinationDrops: HallucinationFilter.Drops?

    public init(prepMillis: Int?, networkMillis: Int?, parseMillis: Int?,
                hallucinationDrops: HallucinationFilter.Drops? = nil) {
        self.prepMillis = prepMillis
        self.networkMillis = networkMillis
        self.parseMillis = parseMillis
        self.hallucinationDrops = hallucinationDrops
    }

    public static func millis(_ d: Duration) -> Int? {
        let ms = d / .milliseconds(1)
        return ms >= 0 ? Int(ms.rounded()) : nil
    }
}

public struct LatencyStages: Codable, Equatable, Sendable {
    public var pressToEngineRunningMillis: Int?
    public var pressToFirstAudioMillis: Int?
    public var recordingMillis: Int?
    public var stopToTargetFrozenMillis: Int?
    public var engineStopMillis: Int?
    public var tailHandoffMillis: Int?
    public var tailPrepMillis: Int?
    public var tailNetworkMillis: Int?
    public var tailParseMillis: Int?
    public var tailQueuedMillis: Int?
    public var tailRoundTripMillis: Int?
    public var stopToTextMillis: Int?
    public var punctuateMillis: Int?
    public var convertMillis: Int?
    public var preInsertMillis: Int?
    public var rewriteMillis: Int?
    public var firstKeystrokeMillis: Int?
    public var typingMillis: Int?
    public var stopToFirstKeystrokeMillis: Int?
    public var stopToInsertionDoneMillis: Int?
    public var chunks: Int?
    public var tailSent: Bool?
    public var timedOut: Bool?
    public var droppedSilentChunk: Int?
    public var droppedArtifact: Int?
    public var droppedBlacklist: Int?
    public var droppedPromptEcho: Int?
    public var droppedNoSpeech: Int?
    public var droppedRepetition: Int?

    public init() {}

    public enum TailWorkKey: String, Sendable, CaseIterable {
        case net
        case infer
    }

    public var compactDescription: String { compactDescription(tailWork: .net) }

    public func compactDescription(tailWork: TailWorkKey) -> String {
        func v(_ n: Int?) -> String { n.map(String.init) ?? "-" }
        let tail = tailSent.map { $0 ? "yes" : "no" } ?? "-"
        return "stop>key=\(v(stopToFirstKeystrokeMillis))"
            + " | press>engine=\(v(pressToEngineRunningMillis)) press>audio=\(v(pressToFirstAudioMillis)) rec=\(v(recordingMillis))"
            + " | freeze=\(v(stopToTargetFrozenMillis)) engineStop=\(v(engineStopMillis)) handoff=\(v(tailHandoffMillis))"
            + " | tail prep=\(v(tailPrepMillis)) \(tailWork.rawValue)=\(v(tailNetworkMillis)) parse=\(v(tailParseMillis))"
            + " queued=\(v(tailQueuedMillis)) rt=\(v(tailRoundTripMillis))"
            + " | stop>text=\(v(stopToTextMillis)) punct=\(v(punctuateMillis)) convert=\(v(convertMillis)) preInsert=\(v(preInsertMillis))"
            + " firstKey=\(v(firstKeystrokeMillis)) typing=\(v(typingMillis)) stop>done=\(v(stopToInsertionDoneMillis))"
            + (rewriteMillis.map { " rewrite=\($0)" } ?? "")
            + " | chunks=\(v(chunks)) tail=\(tail)"
            + (timedOut == true ? " timedOut=yes" : "")
            + droppedDescription
    }
}

extension LatencyStages {
    var droppedDescription: String {
        let counts = [droppedSilentChunk, droppedArtifact, droppedBlacklist, droppedPromptEcho, droppedNoSpeech,
                      droppedRepetition]
        guard counts.contains(where: { ($0 ?? 0) > 0 }) else { return "" }
        func v(_ n: Int?) -> String { n.map(String.init) ?? "-" }
        return " | dropped silent=\(v(droppedSilentChunk)) artifact=\(v(droppedArtifact))"
            + " blacklist=\(v(droppedBlacklist)) promptEcho=\(v(droppedPromptEcho)) noSpeech=\(v(droppedNoSpeech)) repetition=\(v(droppedRepetition))"
    }
}

public struct LatencyTimeline: Equatable, Sendable {
    public private(set) var marks: [LatencyMark: UInt64] = [:]
    public var chunksSent: Int?
    public var tailSent: Bool?
    public private(set) var tail: RequestTiming?
    public private(set) var tailRoundTripMillis: Int?
    public private(set) var tailQueuedMillis: Int?
    public private(set) var punctuateMillis: Int?
    public private(set) var rewriteMillis: Int?
    public private(set) var hallucinationDrops: HallucinationFilter.Drops?

    public init() {}

    public static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    public mutating func mark(_ m: LatencyMark, at nanos: UInt64 = LatencyTimeline.now()) {
        if marks[m] == nil { marks[m] = nanos }
    }

    public mutating func record(_ report: StreamingTranscription.ChunkReport) {
        if let drops = report.timing?.hallucinationDrops {
            hallucinationDrops = (hallucinationDrops ?? HallucinationFilter.Drops()) + drops
        }
        guard report.isTail else { return }
        tail = report.timing
        tailRoundTripMillis = report.millis
        tailQueuedMillis = report.queuedMillis
    }

    public mutating func record(_ report: PunctuationReport) {
        punctuateMillis = report.millis
    }

    public mutating func record(_ report: RewriteReport) {
        rewriteMillis = report.millis
    }

    public func millis(from a: LatencyMark, to b: LatencyMark) -> Int? {
        guard let start = marks[a], let end = marks[b], end >= start else { return nil }
        return Int((Double(end - start) / 1_000_000).rounded())
    }

    public func stages() -> LatencyStages {
        var s = LatencyStages()
        s.pressToEngineRunningMillis = millis(from: .hotkeyPressed, to: .engineRunning)
        s.pressToFirstAudioMillis = millis(from: .hotkeyPressed, to: .firstAudio)
        s.recordingMillis = millis(from: .hotkeyPressed, to: .stopPressed)
        s.stopToTargetFrozenMillis = millis(from: .stopPressed, to: .targetFrozen)
        s.engineStopMillis = millis(from: .targetFrozen, to: .engineStopped)
        s.tailHandoffMillis = millis(from: .engineStopped, to: .tailHandedOff)
        s.tailPrepMillis = tail?.prepMillis
        s.tailNetworkMillis = tail?.networkMillis
        s.tailParseMillis = tail?.parseMillis
        s.tailQueuedMillis = tailQueuedMillis
        s.tailRoundTripMillis = tailRoundTripMillis
        s.stopToTextMillis = millis(from: .stopPressed, to: .textReady)
        s.punctuateMillis = punctuateMillis
        s.convertMillis = millis(from: .textReady, to: .converted)
        s.preInsertMillis = millis(from: .converted, to: .insertionStarted)
        s.rewriteMillis = rewriteMillis
        s.firstKeystrokeMillis = millis(from: .insertionStarted, to: .firstKeystroke)
        s.typingMillis = millis(from: .firstKeystroke, to: .insertionDone)
        s.stopToFirstKeystrokeMillis = millis(from: .stopPressed, to: .firstKeystroke)
        s.stopToInsertionDoneMillis = millis(from: .stopPressed, to: .insertionDone)
        s.chunks = chunksSent
        s.tailSent = tailSent
        if let d = hallucinationDrops {
            s.droppedSilentChunk = d.silentChunk
            s.droppedArtifact = d.artifact
            s.droppedBlacklist = d.blacklist
            s.droppedPromptEcho = d.promptEcho
            s.droppedNoSpeech = d.noSpeech
            s.droppedRepetition = d.repetition
        }
        return s
    }

    public static func queuedMillis(tailStartedAt: Double, tailFinishedAt: Double,
                                    earlierFinishedAt: [Double?]) -> Int? {
        guard tailFinishedAt >= tailStartedAt else { return nil }
        let blockedUntil = earlierFinishedAt.compactMap { $0 }.map { min($0, tailFinishedAt) }.max()
        guard let blockedUntil, blockedUntil > tailStartedAt else { return 0 }
        return Int(((blockedUntil - tailStartedAt) * 1000).rounded())
    }
}
