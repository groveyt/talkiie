import Foundation

public struct NudgeState: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public var feature: Int
        public var shownCount: Int
        public var lastShownAt: Date?
        public var dismissed: Bool
        public var opened: Bool

        public init(feature: Int, shownCount: Int = 0, lastShownAt: Date? = nil, dismissed: Bool = false, opened: Bool = false) {
            self.feature = feature
            self.shownCount = shownCount
            self.lastShownAt = lastShownAt
            self.dismissed = dismissed
            self.opened = opened
        }
    }

    public var records: [Record]
    public var lastShownAt: Date?
    public var pending: Int?
    public var pendingAt: Date?
    public var statsPaneVisited: Bool

    public init(records: [Record] = [], lastShownAt: Date? = nil, pending: Int? = nil, pendingAt: Date? = nil,
                statsPaneVisited: Bool = false) {
        self.records = records
        self.lastShownAt = lastShownAt
        self.pending = pending
        self.pendingAt = pendingAt
        self.statsPaneVisited = statsPaneVisited
    }

    public func record(for feature: Int) -> Record {
        records.first { $0.feature == feature } ?? Record(feature: feature)
    }

    public mutating func update(_ feature: Int, _ change: (inout Record) -> Void) {
        var r = record(for: feature)
        change(&r)
        if let i = records.firstIndex(where: { $0.feature == feature }) { records[i] = r } else { records.append(r) }
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }
    public static func decode(_ data: Data?) -> NudgeState {
        guard let data, let s = try? JSONDecoder().decode(NudgeState.self, from: data) else { return NudgeState() }
        return s
    }
}
