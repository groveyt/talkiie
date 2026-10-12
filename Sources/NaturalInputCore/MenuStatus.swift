#if os(macOS)
import Foundation

public enum MenuStatus {

    public static func idleLine(hotkey: String, tap: TapHotkey) -> String {
        "待命中 · \(hotkey)\(orTap(tap)) 開始口述"
    }

    public static func recordingLine(elapsed: String, hotkey: String, tap: TapHotkey,
                                     stop: StopTrigger = .anyKey) -> String {
        "錄音中 \(elapsed) · 再按 \(hotkey)\(orTap(tap)) 或\(stop.menuPhrase)結束"
    }

    private static func orTap(_ tap: TapHotkey) -> String {
        tap.menuPhrase.map { " 或\($0)" } ?? ""
    }

    public enum Warning: Equatable, Sendable {
        case permissions(String)
        case hotkeyUnavailable(hotkey: String)
        case remoteUnreachable(at: Date)

        public enum Destination: Equatable, Sendable { case permissions, general }

        public var opens: Destination? {
            switch self {
            case .permissions: return .permissions
            case .hotkeyUnavailable: return .general
            case .remoteUnreachable: return nil
            }
        }

        public func text(time: (Date) -> String, remoteUnreachable: (String) -> String) -> String {
            switch self {
            case .permissions(let summary):
                return "⚠️ \(summary)…"
            case .hotkeyUnavailable(let hotkey):
                return "⚠️ 熱鍵 \(hotkey) 無法使用（可能被其他 app 佔用），換一個…"
            case .remoteUnreachable(let at):
                return remoteUnreachable(time(at))
            }
        }
    }

    public static func warnings(permissions: PermissionGuidance.State, inputMonitoringMissing: Bool,
                                hotkeyRegistered: Bool, hotkey: String, lastRemoteFailure: Date?) -> [Warning] {
        var out: [Warning] = []
        if !hotkeyRegistered { out.append(.hotkeyUnavailable(hotkey: hotkey)) }
        if !PermissionGuidance.isReady(permissions) {
            let summary = PermissionGuidance.summary(permissions)
            out.append(.permissions(inputMonitoringMissing ? summary + "；fn 還需要輸入監控" : summary))
        } else if inputMonitoringMissing {
            out.append(.permissions("缺輸入監控權限：fn 鍵無法開始口述"))
        }
        if let lastRemoteFailure { out.append(.remoteUnreachable(at: lastRemoteFailure)) }
        return out
    }
}

public enum LaunchAtLoginPolicy {
    public enum Status: Equatable, Sendable, CaseIterable {
        case notRegistered, enabled, requiresApproval, notFound
    }

    public static let userChoiceKey = "launchAtLoginUserChoice"
    public static let autoRegisteredKey = "launchAtLoginAutoRegistered"

    public static func shouldAutoRegister(consented: Bool, defaultOn: Bool, alreadyAutoRegistered: Bool,
                                          userChoice: Bool?) -> Bool {
        consented && defaultOn && !alreadyAutoRegistered && userChoice == nil
    }

    public static func toggleIsOn(_ s: Status) -> Bool {
        s == .enabled || s == .requiresApproval
    }

    public static func hint(_ s: Status, registerFailed: Bool = false) -> (text: String, needsSettingsButton: Bool)? {
        switch s {
        case .requiresApproval:
            return ("macOS 還要你在「系統設定 › 一般 › 登入項目」允許 Talkiie，才會在登入時打開。", true)
        case .enabled:
            return nil
        case .notRegistered, .notFound:
            return registerFailed
                ? ("macOS 沒有接受這個設定。可以到「系統設定 › 一般 › 登入項目」手動把 Talkiie 加進去。", true)
                : nil
        }
    }
}
#endif
