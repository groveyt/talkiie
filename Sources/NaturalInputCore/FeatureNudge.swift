import Foundation

public enum NudgeFeature: Int, CaseIterable, Sendable {
    case editCapture = 1
    case dictionary = 2
    case fillerRemoval = 3
    case usageStats = 4

    public var target: FeatureTarget {
        switch self {
        case .editCapture: return .privacy
        case .dictionary, .fillerRemoval: return .text
        case .usageStats: return .stats
        }
    }
}

public enum FeatureTarget: String, CaseIterable, Sendable {
    case general, text, stats, privacy, permissions, about
}

public enum FeatureNudgeChannel: Sendable {
    case menuLine
}

public struct NudgeUsage: Equatable, Sendable {
    public var activeDays: Int
    public var insertions: Int
    public var weekCharacters: Int
    public var weekSavedMinutes: Int

    public init(activeDays: Int = 0, insertions: Int = 0, weekCharacters: Int = 0, weekSavedMinutes: Int = 0) {
        self.activeDays = activeDays
        self.insertions = insertions
        self.weekCharacters = weekCharacters
        self.weekSavedMinutes = weekSavedMinutes
    }

    public init(days: [UsageDay], now: Date, calendar: Calendar = UsageStatsLayout.calendar()) {
        let week = UsageSummary(days, lastDays: 7, now: now, calendar: calendar)
        self.init(activeDays: days.filter { $0.insertedRounds > 0 }.count,
                  insertions: days.reduce(0) { $0 + max(0, $1.insertedRounds) },
                  weekCharacters: week.charactersInserted,
                  weekSavedMinutes: Int((Double(week.savedSeconds) / 60).rounded()))
    }
}

public struct NudgeContext: Equatable, Sendable {
    public var now: Date
    public var enabled: Bool
    public var daysSinceOnboarding: Int?
    public var statsRecording: Bool
    public var usage: NudgeUsage
    public var busy: Bool
    public var editCaptureEnabled: Bool
    public var dictionaryEntryCount: Int
    public var fillerRemovalOff: Bool
    public var statsPaneVisited: Bool
    public var editShortcutLabel: String

    public init(now: Date, enabled: Bool = true, daysSinceOnboarding: Int?, statsRecording: Bool, usage: NudgeUsage = NudgeUsage(),
                busy: Bool = false, editCaptureEnabled: Bool = false, dictionaryEntryCount: Int = 0,
                fillerRemovalOff: Bool = false, statsPaneVisited: Bool = false, editShortcutLabel: String = "⌥K") {
        self.now = now
        self.enabled = enabled
        self.daysSinceOnboarding = daysSinceOnboarding
        self.statsRecording = statsRecording
        self.usage = usage
        self.busy = busy
        self.editCaptureEnabled = editCaptureEnabled
        self.dictionaryEntryCount = dictionaryEntryCount
        self.fillerRemovalOff = fillerRemovalOff
        self.statsPaneVisited = statsPaneVisited
        self.editShortcutLabel = editShortcutLabel
    }

    var activity: (days: Int, insertions: Int?) {
        statsRecording ? (usage.activeDays, usage.insertions) : (daysSinceOnboarding ?? 0, nil)
    }

    func meets(days: Int, insertions: Int) -> Bool {
        let a = activity
        return a.days >= days && (a.insertions.map { $0 >= insertions } ?? true)
    }
}

public enum FeatureNudgePlan {
    public static let stateDefaultsKey = "featureNudge.state"
    public static let enabledDefaultsKey = "featureNudge.enabled"
    public static let enabledDefault = true

    public static func isEnabled(fromDefaults value: Any?) -> Bool { (value as? Bool) ?? enabledDefault }

    public static let startActiveDays = 3
    public static let startInsertions = 30
    public static let startGraceDays = 3
    public static let globalIntervalDays = 7
    public static let maxShownPerFeature = 2
    public static let featureGapDays = 21
    public static let pendingExpiryDays = 7

    private static let day: TimeInterval = 86_400

    public static func isEligible(_ feature: NudgeFeature, _ c: NudgeContext) -> Bool {
        guard c.meets(days: startActiveDays, insertions: startInsertions) else { return false }
        switch feature {
        case .editCapture:
            return !c.editCaptureEnabled && c.meets(days: 5, insertions: 50)
        case .dictionary:
            return c.dictionaryEntryCount == 0 && c.meets(days: startActiveDays, insertions: 30)
        case .fillerRemoval:
            return c.fillerRemovalOff && c.meets(days: startActiveDays, insertions: 20)
        case .usageStats:
            return !c.statsPaneVisited && c.statsRecording && c.usage.weekCharacters > 0 && c.meets(days: 7, insertions: 0)
        }
    }

    public static func pendingFeature(state: NudgeState, now: Date) -> NudgeFeature? {
        guard let raw = state.pending, let f = NudgeFeature(rawValue: raw), let at = state.pendingAt,
              now.timeIntervalSince(at) < Double(pendingExpiryDays) * day else { return nil }
        return f
    }

    public static func next(state: NudgeState, context c: NudgeContext) -> NudgeFeature? {
        guard c.enabled, !c.busy, let since = c.daysSinceOnboarding, since >= startGraceDays,
              pendingFeature(state: state, now: c.now) == nil else { return nil }
        if let last = state.lastShownAt, c.now.timeIntervalSince(last) < Double(globalIntervalDays) * day { return nil }
        for f in NudgeFeature.allCases {
            let r = state.record(for: f.rawValue)
            guard !r.dismissed, !r.opened, r.shownCount < maxShownPerFeature else { continue }
            if let last = r.lastShownAt, c.now.timeIntervalSince(last) < Double(featureGapDays) * day { continue }
            if isEligible(f, c) { return f }
        }
        return nil
    }

    public static func armed(_ state: NudgeState, feature: NudgeFeature, now: Date) -> NudgeState {
        var next = state
        next.update(feature.rawValue) { $0.shownCount += 1; $0.lastShownAt = now }
        next.lastShownAt = now
        next.pending = feature.rawValue
        next.pendingAt = now
        return next
    }

    public static func opened(_ state: NudgeState, feature: NudgeFeature) -> NudgeState {
        var next = state
        next.update(feature.rawValue) { $0.opened = true }
        next.pending = nil
        next.pendingAt = nil
        return next
    }

    public static func dismissed(_ state: NudgeState, feature: NudgeFeature) -> NudgeState {
        var next = state
        next.update(feature.rawValue) { $0.dismissed = true }
        next.pending = nil
        next.pendingAt = nil
        return next
    }

    public static func expired(_ state: NudgeState) -> NudgeState {
        var next = state
        next.pending = nil
        next.pendingAt = nil
        return next
    }

    public static func text(for feature: NudgeFeature, context c: NudgeContext) -> String {
        switch feature {
        case .editCapture:
            return "收集我的修改：改完按 \(c.editShortcutLabel) 就會學起來"
        case .dictionary:
            return "個人詞庫：常被聽錯的人名、產品名加進來"
        case .fillerRemoval:
            return "刪除贅字：自動拿掉「嗯、那個、就是」"
        case .usageStats:
            return "這週用說的打了 \(c.usage.weekCharacters.formatted()) 字，約省下 \(c.usage.weekSavedMinutes) 分鐘 ›"
        }
    }

    public static func daysSince(_ completedAt: Date?, now: Date) -> Int? {
        completedAt.map { max(0, Int(now.timeIntervalSince($0) / day)) }
    }
}
