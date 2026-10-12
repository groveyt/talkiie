import Foundation

public enum EgressBoundary {
    public static let rationale = "全 app 唯一網路出口（PLAN.md §1、§3.3）"
}

public enum EgressKind: String, Sendable, CaseIterable {
    case modelDownload
    case ownDevice
    case userContent
    case appUpdate
    case feedbackReport
}
