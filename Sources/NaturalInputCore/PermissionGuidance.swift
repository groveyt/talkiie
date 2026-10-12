import Foundation

public enum PermissionGuidance {

    public enum Microphone: Equatable, Sendable, CaseIterable {
        case notDetermined, granted, denied, restricted
    }

    public struct State: Equatable, Sendable {
        public let microphone: Microphone
        public let accessibilityTrusted: Bool
        public let accessibilityPrompted: Bool

        public init(microphone: Microphone, accessibilityTrusted: Bool, accessibilityPrompted: Bool) {
            self.microphone = microphone
            self.accessibilityTrusted = accessibilityTrusted
            self.accessibilityPrompted = accessibilityPrompted
        }
    }

    public enum Action: Equatable, Sendable {
        case requestMicrophone
        case openMicrophoneSettings
        case promptAccessibility
        case openAccessibilitySettings
    }

    public struct Item: Equatable, Sendable {
        public let status: String
        public let buttonTitle: String?
        public let action: Action?

        public init(status: String, buttonTitle: String? = nil, action: Action? = nil) {
            self.status = status
            self.buttonTitle = buttonTitle
            self.action = action
        }
    }

    public static func microphoneItem(_ mic: Microphone) -> Item {
        switch mic {
        case .granted:
            return Item(status: "麥克風：已允許")
        case .notDetermined:
            return Item(status: "麥克風：尚未允許",
                        buttonTitle: "允許麥克風…",
                        action: .requestMicrophone)
        case .denied:
            return Item(status: "麥克風：已拒絕 —— 需到系統設定重新開啟",
                        buttonTitle: "打開麥克風設定…",
                        action: .openMicrophoneSettings)
        case .restricted:
            return Item(status: "麥克風：受系統管理限制，無法在此開啟")
        }
    }

    public static func accessibilityItem(trusted: Bool, prompted: Bool) -> Item {
        if trusted { return Item(status: "輔助使用：已允許") }
        if prompted {
            return Item(status: "輔助使用：未允許 —— 請在系統設定勾選 Talkiie",
                        buttonTitle: "打開輔助使用設定…",
                        action: .openAccessibilitySettings)
        }
        return Item(status: "輔助使用：未允許（插字需要）",
                    buttonTitle: "允許輔助使用…",
                    action: .promptAccessibility)
    }

    public static func summary(_ s: State) -> String {
        let micOK = s.microphone == .granted
        switch (micOK, s.accessibilityTrusted) {
        case (true, true):   return "權限就緒"
        case (false, true):  return "缺麥克風權限：無法錄音"
        case (true, false):  return "缺輔助使用權限：無法插字"
        case (false, false): return "缺麥克風與輔助使用權限：無法口述"
        }
    }

    public static func isReady(_ s: State) -> Bool {
        s.microphone == .granted && s.accessibilityTrusted
    }
}
