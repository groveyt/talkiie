import Foundation

public struct DictationHistory: Sendable {
    public static let defaultLimit = 20

    public struct Entry: Equatable, Sendable {
        public let serial: Int
        public fileprivate(set) var text: String
        public fileprivate(set) var original: String?
        public fileprivate(set) var rewriteMode: WrittenStyleMode?
        public fileprivate(set) var rewritten: String? = nil
        public fileprivate(set) var rewrittenMode: WrittenStyleMode? = nil
        public var listAlternate: String? = nil
        public var listKind: ListToggleKind? = nil
    }

    public let limit: Int
    private var entries: [Entry] = []
    private var nextSerial = 0

    public init(limit: Int = DictationHistory.defaultLimit) {
        precondition(limit > 0, "上限必須為正 —— 無上限等於建立一份沒人管理的逐字稿")
        self.limit = limit
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }

    @discardableResult
    public mutating func record(_ text: String, original: String? = nil, rewriteMode: WrittenStyleMode? = nil,
                                listAlternate: String? = nil, listKind: ListToggleKind? = nil) -> Int? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let o = original?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kept = (o?.isEmpty == false && o != t) ? o : nil
        let a = listAlternate?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alternate = (a?.isEmpty == false && a != t) ? a : nil
        nextSerial += 1
        entries.append(Entry(serial: nextSerial, text: t, original: kept, rewriteMode: kept == nil ? nil : rewriteMode,
                             listAlternate: alternate, listKind: alternate == nil ? nil : listKind))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
        return nextSerial
    }

    @discardableResult
    public mutating func attachRewritten(_ rewritten: String, mode: WrittenStyleMode, to serial: Int) -> Bool {
        guard let i = entries.firstIndex(where: { $0.serial == serial }) else { return false }
        let r = rewritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, r != entries[i].text, entries[i].original == nil else { return false }
        entries[i].rewritten = r
        entries[i].rewrittenMode = mode
        return true
    }

    @discardableResult
    public mutating func applyRewritten(to serial: Int) -> Bool {
        guard let i = entries.firstIndex(where: { $0.serial == serial }),
              let r = entries[i].rewritten, let mode = entries[i].rewrittenMode else { return false }
        entries[i].original = entries[i].text
        entries[i].rewriteMode = mode
        entries[i].text = r
        entries[i].rewritten = nil
        entries[i].rewrittenMode = nil
        entries[i].listAlternate = nil
        entries[i].listKind = nil
        return true
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
