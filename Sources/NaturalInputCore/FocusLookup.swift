import Foundation

public enum FocusLookup: Equatable, Sendable {
    case found(FocusSnapshot)
    case missing(FocusMiss, micros: Int)

    public var snapshot: FocusSnapshot? {
        if case .found(let s) = self { return s }
        return nil
    }

    public var miss: FocusMiss? {
        if case .missing(let m, _) = self { return m }
        return nil
    }

    public var micros: Int {
        switch self {
        case .found(let s): return s.diagnostics?.lookupMicros ?? -1
        case .missing(_, let m): return m
        }
    }
}

public enum FocusMiss: Equatable, Sendable {
    case notTrusted
    case noFocusedElement(axError: Int32)
    case noProcess(axError: Int32)
    case roleUnreadable(axError: Int32)

    public var axError: Int32? {
        switch self {
        case .notTrusted: return nil
        case .noFocusedElement(let e), .noProcess(let e), .roleUnreadable(let e): return e
        }
    }

    public var isTimeout: Bool { axError == AXErrorCode.cannotComplete }
}

public enum AXErrorCode {
    public static let success: Int32 = 0
    public static let failure: Int32 = -25200
    public static let illegalArgument: Int32 = -25201
    public static let invalidUIElement: Int32 = -25202
    public static let cannotComplete: Int32 = -25204
    public static let attributeUnsupported: Int32 = -25205
    public static let notImplemented: Int32 = -25208
    public static let apiDisabled: Int32 = -25211
    public static let noValue: Int32 = -25212

    public static func name(_ code: Int32) -> String {
        switch code {
        case success: return "success"
        case failure: return "failure"
        case illegalArgument: return "illegalArgument"
        case invalidUIElement: return "invalidUIElement"
        case cannotComplete: return "cannotComplete"
        case attributeUnsupported: return "attributeUnsupported"
        case notImplemented: return "notImplemented"
        case apiDisabled: return "apiDisabled"
        case noValue: return "noValue"
        default: return "other"
        }
    }
}

public enum FocusSource: String, Equatable, Sendable {
    case systemWide
    case afterEnable
}

public enum FocusLogText {
    public static func miss(_ miss: FocusMiss) -> String {
        switch miss {
        case .notTrusted: return "reason=untrusted"
        case .noFocusedElement(let e): return "lookup failed: AXFocusedUIElement err=\(e) (\(AXErrorCode.name(e)))"
        case .noProcess(let e): return "lookup failed: AXUIElementGetPid err=\(e) (\(AXErrorCode.name(e)))"
        case .roleUnreadable(let e): return "lookup failed: AXRole err=\(e) (\(AXErrorCode.name(e)))"
        }
    }
}
