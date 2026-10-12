import Foundation

public enum PublicIdentity {
    public static let bundleIdentifier = "app.yyt.talkiie"
    public static let logSubsystem = "app.yyt.talkiie"
    public static let consentVersion = 3
    public static let dataDirectoryName = "app.yyt.talkiie"

    public static var dataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(dataDirectoryName, isDirectory: true)
    }

    public static var modelsDirectory: URL {
        dataDirectory.appendingPathComponent("models", isDirectory: true)
    }

    public static var licenseDirectory: URL {
        dataDirectory.appendingPathComponent("license", isDirectory: true)
    }
}
