import Foundation

public struct DictationHistory: Sendable {
    public static let defaultLimit = 20

    public struct Entry: Equatable, Sendable {
        public let text: String
        public let original: String?
        public let rewriteMode: WrittenStyleMode?
        public var listAlternate: String? = nil
        public var listKind: ListToggleKind? = nil
    }

    public let limit: Int
    private var entries: [Entry] = []

    public init(limit: Int = DictationHistory.defaultLimit) {
        precondition(limit > 0, "上限必須為正 —— 無上限等於建立一份沒人管理的逐字稿")
        self.limit = limit
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    public mutating func record(_ text: String, original: String? = nil, rewriteMode: WrittenStyleMode? = nil,
                                listAlternate: String? = nil, listKind: ListToggleKind? = nil) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let o = original?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = (o?.isEmpty == false && o != t) ? o : nil
        let a = listAlternate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternate = (a?.isEmpty == false && a != t) ? a : nil
        entries.append(Entry(text: t, original: kept, rewriteMode: kept == nil ? nil : rewriteMode,
                             listAlternate: alternate, listKind: alternate == nil ? nil : listKind))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    public func recent(_ n: Int) -> [String] {
        recentEntries(n).map(\.text)
    }

    public func recentEntries(_ n: Int) -> [Entry] {
        guard n > 0 else { return [] }
        return Array(entries.suffix(n))
    }

    public mutating func clear() {
        entries.removeAll(keepingCapacity: false)
    }
}
