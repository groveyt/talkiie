import Foundation

public struct FocusDiagnostics: Equatable, Sendable {
    public let app: KnownApp
    public let role: AXRoleKind
    public let subrole: AXRoleKind
    public let descendantRole: AXRoleKind?
    public let descendantFocused: Bool?
    public let nodesSearched: Int
    public let lookupMicros: Int
    public let rangeReadable: Bool
    public let axTimeouts: Int

    public init(app: KnownApp, role: AXRoleKind, subrole: AXRoleKind,
                descendantRole: AXRoleKind?, descendantFocused: Bool?,
                nodesSearched: Int, lookupMicros: Int, rangeReadable: Bool, axTimeouts: Int = 0) {
        self.app = app; self.role = role; self.subrole = subrole
        self.descendantRole = descendantRole; self.descendantFocused = descendantFocused
        self.nodesSearched = nodesSearched; self.lookupMicros = lookupMicros
        self.rangeReadable = rangeReadable; self.axTimeouts = axTimeouts
    }
}

public enum AXRoleKind: String, Equatable, Sendable, CaseIterable {
    case none, textField, textArea, comboBox, searchField, secureTextField
    case group, webArea, scrollArea, window, application, button, staticText, other

    public init(_ raw: String?) {
        switch raw {
        case nil: self = .none
        case "AXTextField": self = .textField
        case "AXTextArea": self = .textArea
        case "AXComboBox": self = .comboBox
        case "AXSearchField": self = .searchField
        case "AXSecureTextField": self = .secureTextField
        case "AXGroup": self = .group
        case "AXWebArea": self = .webArea
        case "AXScrollArea": self = .scrollArea
        case "AXWindow": self = .window
        case "AXApplication": self = .application
        case "AXButton": self = .button
        case "AXStaticText": self = .staticText
        default: self = .other
        }
    }
}

public enum KnownApp: String, Equatable, Sendable, CaseIterable {
    case none, textEdit, notes, chrome, safari, arc, slack, claudeDesktop, chatGPT, terminal, iTerm, vsCode, messages, other

    public init(bundleID: String?) {
        switch bundleID {
        case nil: self = .none
        case "com.apple.TextEdit": self = .textEdit
        case "com.apple.Notes": self = .notes
        case "com.google.Chrome": self = .chrome
        case "com.apple.Safari": self = .safari
        case "company.thebrowser.Browser": self = .arc
        case "com.tinyspeck.slackmacgap": self = .slack
        case "com.anthropic.claudefordesktop": self = .claudeDesktop
        case "com.openai.chat", "com.openai.codex": self = .chatGPT
        case "com.apple.Terminal": self = .terminal
        case "com.googlecode.iterm2": self = .iTerm
        case "com.microsoft.VSCode": self = .vsCode
        case "com.apple.MobileSMS": self = .messages
        default: self = .other
        }
    }
}
