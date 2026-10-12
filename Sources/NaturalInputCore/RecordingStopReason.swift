public enum RecordingStopReason: String, CaseIterable, Sendable {
    case secondPress
    case secureInput
    case sleepOrLock
    case maxDuration
    case cancelled

    public var sendsAudio: Bool {
        switch self {
        case .secondPress, .maxDuration: return true
        case .secureInput, .sleepOrLock, .cancelled: return false
        }
    }

    public var hudMessage: String? {
        switch self {
        case .secondPress: return nil
        case .secureInput: return SecureInputPolicy.Message.systemSecureInput.text + "，錄音已停止並清除"
        case .sleepOrLock: return "Mac 進入睡眠或鎖定，錄音已停止並清除"
        case .maxDuration: return "已達錄音時間上限，錄音已停止"
        case .cancelled: return "已取消"
        }
    }
}
