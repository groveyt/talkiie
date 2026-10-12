import Foundation

public struct UsageOverview: Equatable, Sendable {
    public static let phoneTypingCharactersPerMinute: Double = 40

    public var characters: Int
    public var dictationMillis: Int
    public var waitMillis: Int
    public var rounds: Int
    public var activeDays: Int
    public var currentStreak: Int
    public var longestStreak: Int

    public init(characters: Int = 0, dictationMillis: Int = 0, waitMillis: Int = 0, rounds: Int = 0,
                activeDays: Int = 0, currentStreak: Int = 0, longestStreak: Int = 0) {
        self.characters = characters
        self.dictationMillis = dictationMillis
        self.waitMillis = waitMillis
        self.rounds = rounds
        self.activeDays = activeDays
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
    }

    public init(days: [UsageDay], now: Date, calendar: Calendar = UsageStatsLayout.calendar()) {
        self.init()
        var active = Set<Date>()
        for d in days {
            characters += max(0, d.charactersInserted)
            dictationMillis += max(0, d.recordingMillis)
            waitMillis += d.stopToTextSamples.reduce(0) { $0 + max(0, $1) }
            rounds += max(0, d.insertedRounds)
            if UsageOverview.isActive(d) { active.insert(calendar.startOfDay(for: d.dayStart)) }
        }
        activeDays = active.count
        currentStreak = UsageOverview.currentStreak(active, now: now, calendar: calendar)
        longestStreak = UsageOverview.longestStreak(active, calendar: calendar)
    }

    public static func isActive(_ day: UsageDay) -> Bool { day.insertedRounds > 0 }

    public var charactersPerMinute: Int? {
        guard dictationMillis > 0 else { return nil }
        return Int((Double(characters) / (Double(dictationMillis) / 60_000)).rounded())
    }

    public func savedSeconds(typingCharactersPerMinute: Double = UsageOverview.phoneTypingCharactersPerMinute) -> Int {
        guard typingCharactersPerMinute > 0 else { return 0 }
        let typing = Double(characters) / typingCharactersPerMinute * 60
        let spent = Double(dictationMillis + waitMillis) / 1000
        return max(0, Int((typing - spent).rounded()))
    }

    static func currentStreak(_ active: Set<Date>, now: Date, calendar: Calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        guard var day = active.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var n = 0
        while active.contains(day) {
            n += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return n
    }

    static func longestStreak(_ active: Set<Date>, calendar: Calendar) -> Int {
        var best = 0
        for start in active {
            if let prev = calendar.date(byAdding: .day, value: -1, to: start), active.contains(prev) { continue }
            var n = 0
            var day = start
            while active.contains(day) {
                n += 1
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            best = max(best, n)
        }
        return best
    }
}

public struct UsageHeatmap: Equatable, Sendable {
    public static let defaultWeeks = 12
    public static let levels = 4

    public struct Cell: Equatable, Sendable {
        public var dayStart: Date
        public var characters: Int
        public var level: Int
    }

    public struct Week: Equatable, Sendable {
        public var days: [Cell?]
        public var monthLabel: Int?
    }

    public var weeks: [Week]

    public init(weeks: [Week]) { self.weeks = weeks }

    public static func level(characters: Int, max maxCharacters: Int) -> Int {
        guard characters > 0, maxCharacters > 0 else { return 0 }
        let ratio = Double(min(characters, maxCharacters)) / Double(maxCharacters)
        return Swift.max(1, Swift.min(levels, Int((ratio * Double(levels)).rounded(.up))))
    }

    public init(days: [UsageDay], weeks count: Int = UsageHeatmap.defaultWeeks, now: Date,
                calendar: Calendar = UsageStatsLayout.calendar()) {
        let today = calendar.startOfDay(for: now)
        var chars: [Date: Int] = [:]
        for d in days { chars[calendar.startOfDay(for: d.dayStart), default: 0] += max(0, d.charactersInserted) }
        let weekday = calendar.component(.weekday, from: today)
        guard count > 0, let lastSunday = calendar.date(byAdding: .day, value: -(weekday - 1), to: today),
              let firstSunday = calendar.date(byAdding: .day, value: -7 * (count - 1), to: lastSunday) else {
            self.init(weeks: []); return
        }
        var dates: [[Date]] = []
        for w in 0..<count {
            dates.append((0..<7).compactMap { calendar.date(byAdding: .day, value: 7 * w + $0, to: firstSunday) })
        }
        let visible = dates.joined().filter { $0 <= today }
        let maxChars = visible.map { chars[$0] ?? 0 }.max() ?? 0
        func firstOfMonth(_ column: [Date]) -> Date? { column.first { calendar.component(.day, from: $0) == 1 } }
        var out: [Week] = []
        for (i, column) in dates.enumerated() {
            let cells: [Cell?] = column.map { day in
                guard day <= today else { return nil }
                let c = chars[day] ?? 0
                return Cell(dayStart: day, characters: c, level: UsageHeatmap.level(characters: c, max: maxChars))
            }
            let label: Int?
            if let first = firstOfMonth(column) {
                label = calendar.component(.month, from: first)
            } else if i == 0, !dates.prefix(3).contains(where: { firstOfMonth($0) != nil }) {
                label = calendar.component(.month, from: column[0])
            } else {
                label = nil
            }
            out.append(Week(days: cells, monthLabel: label))
        }
        self.init(weeks: out)
    }
}
