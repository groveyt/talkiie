public enum ConsentGate {
    public static let currentVersion = 8
    public static let defaultsKey = "consentAcceptedVersion"

    public static func hasEverAccepted(acceptedVersion: Int?) -> Bool { acceptedVersion != nil }

    public static func allowsCapture(acceptedVersion: Int?, current: Int = currentVersion) -> Bool {
        guard let accepted = acceptedVersion else { return false }
        return accepted == current
    }
}
