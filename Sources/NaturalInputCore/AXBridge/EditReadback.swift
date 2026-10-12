#if os(macOS)
import ApplicationServices
import Foundation

public enum EditReadback {

    public static var liveReadCount: Int {
        counterLock.lock(); defer { counterLock.unlock() }
        return counter
    }
    private nonisolated(unsafe) static var counter = 0
    private static let counterLock = NSLock()
    static func countLiveRead() {
        counterLock.lock(); counter += 1; counterLock.unlock()
    }

    public static func capture(permit: ReadbackPermit, record: InsertionRecord?,
                               inspector: FocusInspecting, reader: FieldTextReading,
                               now: Date = Date()) -> EditCaptureOutcome {
        guard permit.consume() else { return .refused(.permitUsed) }
        guard let record else { return .refused(.noInsertion) }
        guard record.insertedText.count <= EditAligner.maximumInsertedCharacters else { return .refused(.tooLong) }
        guard inspector.accessibilityTrusted() else { return .refused(.accessibilityNotTrusted) }
        guard !inspector.systemSecureInputEnabled() else { return .refused(.secureInput) }
        guard let focus = inspector.currentFocus() else { return .refused(.focusChanged) }
        guard !focus.isSecureField else { return .refused(.secureField) }
        guard focus.pid == record.pid, focus.element == record.element, focus.role == record.role,
              (focus.textElement ?? focus.element) == record.textElement else { return .refused(.focusChanged) }

        let fieldLength = reader.characterCount(of: record.textElement)
        guard let window = ReadWindow.around(startUTF16: record.startUTF16, insertedUTF16: record.insertedUTF16,
                                             fieldLength: fieldLength) else { return .refused(.notFound) }
        let text: String
        switch reader.string(of: record.textElement, location: window.location, length: window.length) {
        case .text(let t):
            text = t
        case .failed:
            return .refused(.readFailed)
        case .unsupported:
            guard let fieldLength, fieldLength <= LiveFieldTextReader.maximumValueUTF16 else { return .refused(.fieldTooLong) }
            guard let t = reader.valueWindow(of: record.textElement, location: window.location, length: window.length)
            else { return .refused(.unreadable) }
            text = t
        }
        guard let aligned = EditAligner.align(inserted: record.insertedText, window: text,
                                              insertionOffsetUTF16: window.insertionOffset)
        else { return .refused(.notFound) }
        return .captured(EditCorrection(capturedAt: now, app: record.app, inserted: record.insertedText,
                                        edited: aligned.edited),
                         alignedPercent: aligned.alignedPercent)
    }
}

public protocol FieldTextReading {
    func characterCount(of element: FocusedElementIdentity) -> Int?
    func string(of element: FocusedElementIdentity, location: Int, length: Int) -> RangeRead
    func valueWindow(of element: FocusedElementIdentity, location: Int, length: Int) -> String?
}

public enum RangeRead: Equatable {
    case text(String)
    case unsupported
    case failed
}

public struct LiveFieldTextReader: FieldTextReading {
    static let messagingTimeoutSeconds: Float = 0.25

    public init() {}

    public func characterCount(of element: FocusedElementIdentity) -> Int? {
        guard let el = Self.axElement(element) else { return nil }
        EditReadback.countLiveRead()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXNumberOfCharacters" as CFString, &ref) == .success else { return nil }
        return (ref as? NSNumber)?.intValue
    }

    public func string(of element: FocusedElementIdentity, location: Int, length: Int) -> RangeRead {
        guard location >= 0, length > 0, let el = Self.axElement(element) else { return .failed }
        var range = CFRange(location: location, length: length)
        guard let param = AXValueCreate(.cfRange, &range) else { return .failed }
        EditReadback.countLiveRead()
        var ref: CFTypeRef?
        let err = AXUIElementCopyParameterizedAttributeValue(el, kAXStringForRangeParameterizedAttribute as CFString,
                                                             param, &ref)
        return Self.rangeRead(err, ref as? String)
    }

    static func rangeRead(_ err: AXError, _ value: String?) -> RangeRead {
        switch err {
        case .success: return value.map(RangeRead.text) ?? .failed
        case .attributeUnsupported, .parameterizedAttributeUnsupported: return .unsupported
        default: return .failed
        }
    }

    public static let maximumValueUTF16 = 100_000

    public func valueWindow(of element: FocusedElementIdentity, location: Int, length: Int) -> String? {
        guard location >= 0, length > 0, let el = Self.axElement(element) else { return nil }
        EditReadback.countLiveRead()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &ref) == .success,
              let whole = ref as? String else { return nil }
        return Self.slice(whole, location: location, length: length)
    }

    static func slice(_ whole: String, location: Int, length: Int) -> String? {
        let utf16 = whole.utf16
        guard utf16.count <= maximumValueUTF16, location < utf16.count else { return nil }
        let lower = utf16.index(utf16.startIndex, offsetBy: location)
        let upper = utf16.index(lower, offsetBy: min(length, utf16.count - location))
        guard let a = lower.samePosition(in: whole), let b = upper.samePosition(in: whole) else { return nil }
        return String(whole[a..<b])
    }

    private static func axElement(_ identity: FocusedElementIdentity) -> AXUIElement? {
        guard CFGetTypeID(identity.ref as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        let el = unsafeDowncast(identity.ref, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(el, messagingTimeoutSeconds)
        return el
    }
}
#endif
