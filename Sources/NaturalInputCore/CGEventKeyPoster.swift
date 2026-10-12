#if os(macOS)
import CoreGraphics
import Foundation

public struct CGEventKeyPoster: KeyEventPosting {
    public init() {}

    public func post(utf16 units: [UInt16]) -> Bool {
        guard !units.isEmpty else { return true }
        guard let src = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) else {
            return false
        }
        down.flags = []
        up.flags = []
        units.withUnsafeBufferPointer { buf in
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buf.baseAddress)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: buf.baseAddress)
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    static let returnVirtualKey: CGKeyCode = 0x24

    public func postShiftReturn() -> Bool {
        guard let src = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: Self.returnVirtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: Self.returnVirtualKey, keyDown: false) else {
            return false
        }
        down.flags = .maskShift
        up.flags = .maskShift
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    static let vVirtualKey: CGKeyCode = 0x09

    public func postPasteShortcut(toPID pid: Int32) -> Bool {
        guard let src = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: Self.vVirtualKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: Self.vVirtualKey, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(pid)
        up.postToPid(pid)
        return true
    }
}

extension CGEventKeyPoster: SelectionKeyPosting {
    static let leftArrowVirtualKey: CGKeyCode = 0x7B
    static let rightArrowVirtualKey: CGKeyCode = 0x7C
    static let arrowFlags: CGEventFlags = [.maskNumericPad, .maskSecondaryFn]

    public func postShiftLeft() -> Bool {
        postArrow(Self.leftArrowVirtualKey, flags: Self.arrowFlags.union(.maskShift))
    }

    public func postRightArrow() -> Bool {
        postArrow(Self.rightArrowVirtualKey, flags: Self.arrowFlags)
    }

    private func postArrow(_ key: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let src = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else {
            return false
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
#endif
