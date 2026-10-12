import Foundation

public enum SecureInputPolicy {

    public struct State: Equatable, Sendable {
        public let systemSecureInputEnabled: Bool
        public let focusIsSecureTextField: Bool
        public let isRecording: Bool

        public init(systemSecureInputEnabled: Bool,
                    focusIsSecureTextField: Bool,
                    isRecording: Bool) {
            self.systemSecureInputEnabled = systemSecureInputEnabled
            self.focusIsSecureTextField = focusIsSecureTextField
            self.isRecording = isRecording
        }
    }

    public enum Message: Equatable, Sendable {
        case passwordField
        case systemSecureInput

        public var text: String {
            switch self {
            case .passwordField:    return "密碼欄位不支援語音輸入"
            case .systemSecureInput: return "Secure Input 啟用中，語音輸入暫停"
            }
        }
    }

    public enum Decision: Equatable, Sendable {
        case allow
        case refuseBeforeRecording(Message)
        case stopRecordingAndWipe(Message)
        case refuseInsertion(Message)

        public var isAllow: Bool { self == .allow }
        public var message: Message? {
            switch self {
            case .allow: return nil
            case .refuseBeforeRecording(let m), .stopRecordingAndWipe(let m), .refuseInsertion(let m):
                return m
            }
        }
    }

    static func isBlocked(_ s: State) -> Bool {
        s.systemSecureInputEnabled || s.focusIsSecureTextField
    }

    static func message(for s: State) -> Message {
        s.focusIsSecureTextField ? .passwordField : .systemSecureInput
    }

    public static func decideBeforeRecording(_ s: State) -> Decision {
        isBlocked(s) ? .refuseBeforeRecording(message(for: s)) : .allow
    }

    public static func decideDuringRecording(_ s: State) -> Decision {
        isBlocked(s) ? .stopRecordingAndWipe(message(for: s)) : .allow
    }

    public static func decideBeforeInsertion(_ s: State) -> Decision {
        isBlocked(s) ? .refuseInsertion(message(for: s)) : .allow
    }
}
