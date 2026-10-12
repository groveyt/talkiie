#if os(macOS)
import AppKit
import ApplicationServices
import Carbon

public protocol FocusInspecting {
    func accessibilityTrusted() -> Bool
    func systemSecureInputEnabled() -> Bool
    func currentFocus() -> FocusSnapshot?
}

extension FocusInspecting {
    public func insertionState(frozenTarget: FrozenTarget?) -> InsertionPolicy.State {
        let trusted = accessibilityTrusted()
        return InsertionPolicy.State(accessibilityTrusted: trusted,
                                     systemSecureInputEnabled: systemSecureInputEnabled(),
                                     focus: trusted ? currentFocus() : nil,
                                     frozenTarget: frozenTarget)
    }
}

public struct LiveFocusInspector: FocusInspecting {

    enum ReadableAttribute: String, CaseIterable {
        case focusedUIElement = "AXFocusedUIElement"
        case focusedWindow = "AXFocusedWindow"
        case window = "AXWindow"
        case role = "AXRole"
        case subrole = "AXSubrole"
        case children = "AXChildren"
        case focused = "AXFocused"
        case editableAncestor = "AXEditableAncestor"
        case selectedTextRange = "AXSelectedTextRange"
        case markedRange = "AXTextInputMarkedRange"
        case parent = "AXParent"
        case position = "AXPosition"
        case size = "AXSize"
    }

    public func isElement(_ element: FocusedElementIdentity, within container: FocusedElementIdentity,
                          maxDepth: Int = 40) -> Bool {
        guard CFGetTypeID(element.ref as CFTypeRef) == AXUIElementGetTypeID(),
              CFGetTypeID(container.ref as CFTypeRef) == AXUIElementGetTypeID() else { return false }
        var current: AXUIElement? = unsafeDowncast(element.ref, to: AXUIElement.self)
        let target = unsafeDowncast(container.ref, to: AXUIElement.self)
        var depth = 0
        while let el = current, depth <= maxDepth {
            if CFEqual(el, target) { return true }
            current = self.element(el, .parent)
            depth += 1
        }
        return false
    }

    public func windowFrame(of element: FocusedElementIdentity) -> CGRect? {
        guard CFGetTypeID(element.ref as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
        let el = unsafeDowncast(element.ref, to: AXUIElement.self)
        guard let window = self.element(el, .window) ?? self.element(el, .focusedWindow) else { return nil }
        guard let posRef = copy(window, .position), CFGetTypeID(posRef) == AXValueGetTypeID(),
              let sizeRef = copy(window, .size), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(posRef, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox"]
    static let containerRoles: Set<String> = ["AXGroup", "AXWebArea"]
    static let secureSubrole = "AXSecureTextField"

    static let searchMaxDepth = 6
    static let searchMaxNodes = 200
    static let messagingTimeoutSeconds: Float = 0.25

    let timeouts = TimeoutCounter()

    public init() {}

    public func accessibilityTrusted() -> Bool { AXIsProcessTrusted() }

    public func systemSecureInputEnabled() -> Bool { IsSecureEventInputEnabled() }

    public func currentFocus() -> FocusSnapshot? { lookupFocus().snapshot }

    public func lookupFocus() -> FocusLookup {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let micros = { Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000) }
        guard accessibilityTrusted() else { return .missing(.notTrusted, micros: micros()) }
        timeouts.reset()
        var searched = -1
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, Self.messagingTimeoutSeconds)

        var focusError = AXError.success
        guard let focused = element(system, .focusedUIElement, error: &focusError) else {
            return .missing(.noFocusedElement(axError: focusError.rawValue), micros: micros())
        }
        var pid: pid_t = 0
        let pidError = AXUIElementGetPid(focused, &pid)
        guard pidError == .success, pid > 0 else {
            return .missing(.noProcess(axError: pidError == .success ? AXError.failure.rawValue : pidError.rawValue),
                            micros: micros())
        }

        var roleError = AXError.success
        let role = string(focused, .role, error: &roleError)
        if role == nil, roleError == .cannotComplete {
            return .missing(.roleUnreadable(axError: roleError.rawValue), micros: micros())
        }
        let subrole = string(focused, .subrole)

        var textNode: AXUIElement? = nil
        let editability: Editability
        if let role, Self.textRoles.contains(role) || element(focused, .editableAncestor) != nil {
            editability = .editable
            textNode = focused
        } else if let role, Self.containerRoles.contains(role),
                  isInFocusedWindow(focused, pid: pid),
                  let node = findTextDescendant(of: focused,
                                                requireFocused: role == "AXWebArea",
                                                searched: &searched) {
            editability = .containerWithTextDescendant
            textNode = node
        } else {
            editability = .notEditable
        }

        let nodeSubrole = textNode.flatMap { CFEqual($0, focused) ? subrole : string($0, .subrole) }
        let isSecure = subrole == Self.secureSubrole || nodeSubrole == Self.secureSubrole

        var marked = markedTextState(focused)
        var selected = range(focused, .selectedTextRange)
        if let textNode, !CFEqual(textNode, focused) {
            if marked == .unsupported { marked = markedTextState(textNode) }
            if selected == nil { selected = range(textNode, .selectedTextRange) }
        }
        let location = selected?.location

        let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
        let isDescendant = textNode.map { !CFEqual($0, focused) } ?? false
        let diagnostics = FocusDiagnostics(
            app: KnownApp(bundleID: bundleID),
            role: AXRoleKind(role), subrole: AXRoleKind(subrole),
            descendantRole: isDescendant ? AXRoleKind(textNode.flatMap { string($0, .role) }) : nil,
            descendantFocused: isDescendant ? textNode.flatMap { bool($0, .focused) } : nil,
            nodesSearched: searched,
            lookupMicros: micros(),
            rangeReadable: location != nil,
            axTimeouts: timeouts.count)

        return .found(FocusSnapshot(pid: pid,
                             bundleID: bundleID,
                             element: FocusedElementIdentity(focused),
                             role: role, subrole: subrole,
                             isSecureField: isSecure,
                             editability: editability,
                             markedText: marked,
                             selectionLocation: location,
                             diagnostics: diagnostics,
                             textElement: textNode.map { FocusedElementIdentity($0) },
                             selectionLength: selected?.length))
    }

    func isInFocusedWindow(_ el: AXUIElement, pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let focusedWindow = element(app, .focusedWindow),
              let window = element(el, .window) else { return false }
        return CFEqual(focusedWindow, window)
    }

    func findTextDescendant(of root: AXUIElement, requireFocused: Bool, searched: inout Int) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = children(root).map { ($0, 1) }
        var seen = 0
        defer { searched = seen }
        while !queue.isEmpty && seen < Self.searchMaxNodes {
            let (el, depth) = queue.removeFirst()
            seen += 1
            if let role = string(el, .role), Self.textRoles.contains(role),
               !requireFocused || bool(el, .focused) == true {
                return el
            }
            if depth < Self.searchMaxDepth {
                queue.append(contentsOf: children(el).map { ($0, depth + 1) })
            }
        }
        return nil
    }

    func copy(_ el: AXUIElement, _ attr: ReadableAttribute) -> CFTypeRef? {
        var error = AXError.success
        return copy(el, attr, error: &error)
    }

    func copy(_ el: AXUIElement, _ attr: ReadableAttribute, error: inout AXError) -> CFTypeRef? {
        var ref: CFTypeRef?
        error = AXUIElementCopyAttributeValue(el, attr.rawValue as CFString, &ref)
        if error == .cannotComplete { timeouts.add() }
        guard error == .success else { return nil }
        return ref
    }

    func string(_ el: AXUIElement, _ attr: ReadableAttribute, error: inout AXError) -> String? {
        copy(el, attr, error: &error) as? String
    }

    func element(_ el: AXUIElement, _ attr: ReadableAttribute) -> AXUIElement? {
        var error = AXError.success
        return element(el, attr, error: &error)
    }

    func element(_ el: AXUIElement, _ attr: ReadableAttribute, error: inout AXError) -> AXUIElement? {
        guard let ref = copy(el, attr, error: &error) else { return nil }
        guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { error = .failure; return nil }
        return unsafeDowncast(ref, to: AXUIElement.self)
    }

    func string(_ el: AXUIElement, _ attr: ReadableAttribute) -> String? {
        copy(el, attr) as? String
    }

    func bool(_ el: AXUIElement, _ attr: ReadableAttribute) -> Bool? {
        (copy(el, attr) as? NSNumber)?.boolValue
    }

    func children(_ el: AXUIElement) -> [AXUIElement] {
        guard let arr = copy(el, .children) as? [AnyObject] else { return [] }
        return arr.compactMap { obj in
            CFGetTypeID(obj) == AXUIElementGetTypeID() ? unsafeDowncast(obj, to: AXUIElement.self) : nil
        }
    }

    func range(_ el: AXUIElement, _ attr: ReadableAttribute) -> CFRange? {
        guard let ref = copy(el, attr), CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var r = CFRange()
        guard AXValueGetValue(unsafeDowncast(ref, to: AXValue.self), .cfRange, &r) else { return nil }
        return r
    }

    func markedTextState(_ el: AXUIElement) -> MarkedTextState {
        guard let r = range(el, .markedRange) else { return .unsupported }
        return r.length > 0 ? .composing : .idle
    }
}
final class TimeoutCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func add() { lock.lock(); value += 1; lock.unlock() }
    func reset() { lock.lock(); value = 0; lock.unlock() }
}
#endif
