import Foundation

public enum ListToggleKind: String, Equatable, Sendable {
    case remove
    case apply

    public var buttonTitle: String {
        switch self {
        case .remove: return "移除項目編號"
        case .apply: return "加入項目編號"
        }
    }

    public var caption: String {
        switch self {
        case .remove: return "已排成條列"
        case .apply: return "這段像是清單"
        }
    }
}

public struct ListToggleOffer: Equatable, Sendable {
    public let kind: ListToggleKind
    public let alternate: String

    public init(kind: ListToggleKind, alternate: String) {
        self.kind = kind
        self.alternate = alternate
    }
}

public enum ListLayoutMode: Equatable, Sendable {
    case plain
    case strict
    case loose
}

public enum ListToggle {
    public static let defaultsKey = "listToggleAfterInsert"
    public static let defaultEnabled = true
    public static let visibleSeconds: Double = 8

    public static func enabled(fromDefaults value: Any?) -> Bool {
        (value as? Bool) ?? defaultEnabled
    }

    public static func offer(spokenLists: Bool, toggleEnabled: Bool,
                             render: (ListLayoutMode) -> (text: String, hasList: Bool)) -> ListToggleOffer? {
        guard spokenLists, toggleEnabled else { return nil }
        let strict = render(.strict)
        if strict.hasList {
            let plain = render(.plain)
            guard !plain.hasList, plain.text != strict.text, !plain.text.isEmpty else { return nil }
            return ListToggleOffer(kind: .remove, alternate: plain.text)
        }
        let loose = render(.loose)
        guard loose.hasList, loose.text != strict.text else { return nil }
        return ListToggleOffer(kind: .apply, alternate: loose.text)
    }

    public static func offers(separator: ParagraphSeparator) -> Bool {
        separator == .shiftReturn
    }
}

public struct SelectionRange: Equatable, Sendable {
    public let location: Int
    public let length: Int
    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
}

public protocol SelectionProbing: InsertionProbing {
    func selectedRange() -> SelectionRange?
}

public protocol SelectionKeyPosting {
    func postShiftLeft() -> Bool
    func postRightArrow() -> Bool
}

public struct InsertionSpot<Element: Equatable>: Equatable {
    public let target: FocusIdentity<Element>
    public let start: Int
    public let typedText: String

    public init(target: FocusIdentity<Element>, start: Int, typedText: String) {
        self.target = target
        self.start = start
        self.typedText = typedText
    }

    public var units: Int { typedText.utf16.count }
    public var cursorAtEnd: SelectionRange { SelectionRange(location: start + units, length: 0) }
    public var expectedSelection: SelectionRange { SelectionRange(location: start, length: units) }
    public var shiftLeftPresses: Int { typedText.count }
}

public enum ListToggleAbortReason: String, Equatable, Sendable {
    case secureInput
    case focusChanged
    case cursorMoved
    case cursorUnreadable
    case selectionMismatch
    case postFailed
    case typingAborted
}

public enum ListToggleResult: Equatable, Sendable {
    case replaced(units: Int)
    case aborted(ListToggleAbortReason, collapsedSelection: Bool, typedUnits: Int)
}

public struct ListToggleReplacer<Probe: SelectionProbing> {
    public static var keysPerBurst: Int { 16 }
    public static var burstDelayMs: Int { 12 }
    public static var selectionSettlePolls: Int { 10 }
    public static var selectionSettleDelayMs: Int { 50 }

    let keys: SelectionKeyPosting
    let probe: Probe
    let sleep: (Int) -> Void

    public init(keys: SelectionKeyPosting, probe: Probe,
                sleep: @escaping (Int) -> Void = { ms in usleep(useconds_t(max(0, ms)) * 1000) }) {
        self.keys = keys
        self.probe = probe
        self.sleep = sleep
    }

    public func stillAtEnd(_ spot: InsertionSpot<Probe.Element>) -> ListToggleAbortReason? {
        if probe.isSecureInputEnabled() { return .secureInput }
        guard let focus = probe.currentFocus(), focus == spot.target else { return .focusChanged }
        guard let range = probe.selectedRange() else { return .cursorUnreadable }
        guard range == spot.cursorAtEnd else { return .cursorMoved }
        return nil
    }

    public func replace(_ spot: InsertionSpot<Probe.Element>,
                        type: () -> InsertionResult) -> ListToggleResult {
        if let reason = stillAtEnd(spot) {
            return .aborted(reason, collapsedSelection: false, typedUnits: 0)
        }
        for k in 0..<spot.shiftLeftPresses {
            if k > 0, k % Self.keysPerBurst == 0 { sleep(Self.burstDelayMs) }
            guard keys.postShiftLeft() else {
                return .aborted(.postFailed, collapsedSelection: collapse(spot), typedUnits: 0)
            }
        }
        var polls = 0
        var range = probe.selectedRange()
        while range != spot.expectedSelection, polls < Self.selectionSettlePolls {
            sleep(Self.selectionSettleDelayMs)
            polls += 1
            range = probe.selectedRange()
        }
        if probe.isSecureInputEnabled() {
            return .aborted(.secureInput, collapsedSelection: collapse(spot), typedUnits: 0)
        }
        guard let focus = probe.currentFocus(), focus == spot.target else {
            return .aborted(.focusChanged, collapsedSelection: false, typedUnits: 0)
        }
        guard range == spot.expectedSelection else {
            return .aborted(range == nil ? .cursorUnreadable : .selectionMismatch,
                            collapsedSelection: collapse(spot), typedUnits: 0)
        }
        switch type() {
        case .sent(let units, _):
            return .replaced(units: units)
        case .aborted(let sent, _):
            return .aborted(.typingAborted, collapsedSelection: false, typedUnits: sent)
        }
    }

    private func collapse(_ spot: InsertionSpot<Probe.Element>) -> Bool {
        guard let focus = probe.currentFocus(), focus == spot.target,
              let range = probe.selectedRange(), range.length > 0 else { return false }
        return keys.postRightArrow()
    }
}

extension InsertionSpot: Sendable where Element: Sendable {}
