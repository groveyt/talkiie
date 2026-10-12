import Foundation

public enum UsageRoundResult: Int, CaseIterable, Sendable {
    case inserted
    case notInserted
    case failed
    case cancelled
}

public struct UsageRound: Equatable, Sendable {
    public var result: UsageRoundResult
    public var characters: Int
    public var recordingMillis: Int?
    public var stopToFirstKeystrokeMillis: Int?
    public var stopToTextMillis: Int?

    public init(result: UsageRoundResult, characters: Int = 0, recordingMillis: Int? = nil,
                stopToFirstKeystrokeMillis: Int? = nil, stopToTextMillis: Int? = nil) {
        self.result = result
        self.characters = characters
        self.recordingMillis = recordingMillis
        self.stopToFirstKeystrokeMillis = stopToFirstKeystrokeMillis
        self.stopToTextMillis = stopToTextMillis
    }

    public init(result: UsageRoundResult, characters: Int = 0, stages: LatencyStages?) {
        self.init(result: result, characters: characters,
                  recordingMillis: stages?.recordingMillis,
                  stopToFirstKeystrokeMillis: stages?.stopToFirstKeystrokeMillis,
                  stopToTextMillis: stages?.stopToTextMillis)
    }
}

public enum UsageStats {
    public static let typingCharactersPerMinute: Double = 40

    public static let retentionDays = 180

    public static let recordingDefaultsKey = "usageStatsRecording"
    public static let recordingDefault = true

    public static func recordingEnabled(fromDefaults value: Any?) -> Bool {
        (value as? Bool) ?? recordingDefault
    }

    public static let maxLatencySamplesPerDay = 1000

    public static func characterCount(_ text: String) -> Int {
        text.reduce(0) { n, ch in ch.isWhitespace || ch.isNewline ? n : n + 1 }
    }

    public static func median(_ samples: [Int]) -> Int? {
        guard !samples.isEmpty else { return nil }
        let s = samples.sorted()
        let mid = s.count / 2
        if s.count % 2 == 1 { return s[mid] }
        return Int((Double(s[mid - 1] + s[mid]) / 2).rounded())
    }
}

public struct UsageDay: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var dayStart: Date
    public var insertedRounds: Int
    public var notInsertedRounds: Int
    public var failedRounds: Int
    public var cancelledRounds: Int
    public var charactersInserted: Int
    public var recordingMillis: Int
    public var stopToFirstKeystrokeSamples: [Int]
    public var stopToTextSamples: [Int]

    public init(dayStart: Date) {
        schemaVersion = Self.currentSchemaVersion
        self.dayStart = dayStart
        insertedRounds = 0
        notInsertedRounds = 0
        failedRounds = 0
        cancelledRounds = 0
        charactersInserted = 0
        recordingMillis = 0
        stopToFirstKeystrokeSamples = []
        stopToTextSamples = []
    }

    public var sentRounds: Int { insertedRounds + notInsertedRounds + failedRounds }

    public mutating func record(_ round: UsageRound) {
        switch round.result {
        case .inserted:
            insertedRounds += 1
            charactersInserted += max(0, round.characters)
            Self.append(round.stopToFirstKeystrokeMillis, to: &stopToFirstKeystrokeSamples)
            Self.append(round.stopToTextMillis, to: &stopToTextSamples)
        case .notInserted:
            notInsertedRounds += 1
            Self.append(round.stopToTextMillis, to: &stopToTextSamples)
        case .failed:
            failedRounds += 1
        case .cancelled:
            cancelledRounds += 1
        }
        if round.result != .cancelled, let ms = round.recordingMillis, ms > 0 {
            recordingMillis += ms
        }
    }

    private static func append(_ ms: Int?, to samples: inout [Int]) {
        guard let ms, ms >= 0, samples.count < UsageStats.maxLatencySamplesPerDay else { return }
        samples.append(ms)
    }

    public func jsonData() throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return try e.encode(self)
    }

    public static func decode(_ data: Data) -> UsageDay? {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        guard let day = try? d.decode(UsageDay.self, from: data), day.schemaVersion == currentSchemaVersion else { return nil }
        return day
    }
}

public struct UsageSummary: Equatable, Sendable {
    public var insertedRounds = 0
    public var notInsertedRounds = 0
    public var failedRounds = 0
    public var cancelledRounds = 0
    public var charactersInserted = 0
    public var recordingMillis = 0
    public var waitMillis = 0
    public var medianStopToFirstKeystrokeMillis: Int?
    public var medianStopToTextMillis: Int?

    public init() {}

    public init(_ days: [UsageDay]) {
        var firstKey: [Int] = []
        var text: [Int] = []
        for d in days {
            insertedRounds += d.insertedRounds
            notInsertedRounds += d.notInsertedRounds
            failedRounds += d.failedRounds
            cancelledRounds += d.cancelledRounds
            charactersInserted += d.charactersInserted
            recordingMillis += d.recordingMillis
            waitMillis += d.stopToTextSamples.reduce(0) { $0 + max(0, $1) }
            firstKey += d.stopToFirstKeystrokeSamples
            text += d.stopToTextSamples
        }
        medianStopToFirstKeystrokeMillis = UsageStats.median(firstKey)
        medianStopToTextMillis = UsageStats.median(text)
    }

    public init(_ days: [UsageDay], lastDays: Int, now: Date, calendar: Calendar = UsageStatsLayout.calendar()) {
        let today = calendar.startOfDay(for: now)
        guard lastDays > 0, let first = calendar.date(byAdding: .day, value: -(lastDays - 1), to: today) else {
            self.init(); return
        }
        self.init(days.filter { $0.dayStart >= first && $0.dayStart <= today })
    }

    public var sentRounds: Int { insertedRounds + notInsertedRounds + failedRounds }

    public var successPercent: Int? {
        sentRounds > 0 ? Int((Double(insertedRounds) * 100 / Double(sentRounds)).rounded()) : nil
    }

    public var savedSeconds: Int {
        UsageOverview(characters: charactersInserted, dictationMillis: recordingMillis, waitMillis: waitMillis)
            .savedSeconds(typingCharactersPerMinute: UsageStats.typingCharactersPerMinute)
    }
}

public struct UsageDailyPoint: Equatable, Sendable {
    public var dayStart: Date
    public var sentRounds: Int
    public var charactersInserted: Int
}

public enum UsageStatsLayout {
    public static let folderName = "stats"
    public static let fileExtension = "json"

    public static func calendar(_ timeZone: TimeZone = .current) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    public static func fileName(for date: Date, calendar: Calendar = UsageStatsLayout.calendar()) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d.%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, fileExtension)
    }

    public static func dayStart(fileName name: String, calendar: Calendar = UsageStatsLayout.calendar()) -> Date? {
        let suffix = "." + fileExtension
        guard name.hasSuffix(suffix) else { return nil }
        let parts = name.dropLast(suffix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let dc = DateComponents(year: y, month: m, day: d)
        guard let date = calendar.date(from: dc),
              calendar.dateComponents([.year, .month, .day], from: date) == dc else { return nil }
        return date
    }

    public static func isExpired(fileName name: String, now: Date, retentionDays: Int = UsageStats.retentionDays,
                                 calendar: Calendar = UsageStatsLayout.calendar()) -> Bool {
        guard let day = dayStart(fileName: name, calendar: calendar),
              let cutoff = calendar.date(byAdding: .day, value: -(retentionDays - 1), to: calendar.startOfDay(for: now))
        else { return false }
        return day < cutoff
    }

    public static func dailySeries(_ days: [UsageDay], count: Int, now: Date,
                                   calendar: Calendar = UsageStatsLayout.calendar()) -> [UsageDailyPoint] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: UsageDay] = [:]
        for d in days { byDay[calendar.startOfDay(for: d.dayStart)] = d }
        return (0..<max(0, count)).reversed().compactMap { back in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            let d = byDay[day]
            return UsageDailyPoint(dayStart: day, sentRounds: d?.sentRounds ?? 0,
                                   charactersInserted: d?.charactersInserted ?? 0)
        }
    }
}
