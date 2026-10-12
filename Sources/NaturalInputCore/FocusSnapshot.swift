import Foundation

public struct FocusedElementIdentity: Equatable, @unchecked Sendable {
    public let ref: AnyObject

    public init(_ ref: AnyObject) { self.ref = ref }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        CFEqual(lhs.ref as CFTypeRef, rhs.ref as CFTypeRef)
    }
}

public enum MarkedTextState: Equatable, Sendable {
    case idle
    case composing
    case unsupported
}

public enum Editability: Equatable, Sendable {
    case editable
    case containerWithTextDescendant
    case notEditable
}

public struct FocusSnapshot: Equatable, Sendable {
    public let pid: Int32
    public let bundleID: String?
    public let element: FocusedElementIdentity
    public let role: String?
    public let subrole: String?
    public let isSecureField: Bool
    public let editability: Editability
    public let markedText: MarkedTextState
    public let selectionLocation: Int?
    public let selectionLength: Int?
    public let diagnostics: FocusDiagnostics?
    public let textElement: FocusedElementIdentity?

    public init(pid: Int32, bundleID: String?, element: FocusedElementIdentity,
                role: String?, subrole: String?, isSecureField: Bool,
                editability: Editability, markedText: MarkedTextState,
                selectionLocation: Int?, diagnostics: FocusDiagnostics? = nil,
                textElement: FocusedElementIdentity? = nil, selectionLength: Int? = nil) {
        self.selectionLength = selectionLength
        self.diagnostics = diagnostics
        self.textElement = textElement
        self.pid = pid
        self.bundleID = bundleID
        self.element = element
        self.role = role
        self.subrole = subrole
        self.isSecureField = isSecureField
        self.editability = editability
        self.markedText = markedText
        self.selectionLocation = selectionLocation
    }
}

public struct FrozenTarget: Equatable, Sendable {
    public let pid: Int32
    public let bundleID: String?
    public let element: FocusedElementIdentity

    public init(pid: Int32, bundleID: String?, element: FocusedElementIdentity) {
        self.pid = pid
        self.bundleID = bundleID
        self.element = element
    }

    public init(_ s: FocusSnapshot) {
        self.init(pid: s.pid, bundleID: s.bundleID, element: s.element)
    }
}
