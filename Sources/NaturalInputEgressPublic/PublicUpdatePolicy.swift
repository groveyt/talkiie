import Foundation
import NaturalInputEgress

public enum PublicUpdatePolicy {
    public static let feedURL = URL(string: "https://talkiie.yyt.app/appcast.xml")!
    public static let downloadPrefix = "https://talkiie.yyt.app/download/"
    public static let feedbackPage = "https://talkiie.yyt.app/feedback"

    public static let placeholderPublicKey = "PLACEHOLDER-TALKIIE-PUBLIC-EDDSA-KEY-NOT-GENERATED"

    public static let feedParameters: [[String: String]] = []
    public static let allowedSystemProfileKeys: [String] = []

    public static func isUsablePublicKey(_ key: String?) -> Bool {
        guard let key, key != placeholderPublicKey, let raw = Data(base64Encoded: key) else { return false }
        return raw.count == 32
    }

    public static func requestedFeedURL(base: URL?, extraParameters: [[String: String]]) -> URL? {
        guard let base else { return nil }
        guard !extraParameters.isEmpty else { return base }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "=&+")
        func esc(_ s: String?) -> String { (s ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        let query = extraParameters.map { "\(esc($0["key"]))=\(esc($0["value"]))" }.joined(separator: "&")
        return URL(string: base.absoluteString + (base.query == nil ? "?" : "&") + query)
    }

    public static func isAllowedFeed(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.absoluteString == feedURL.absoluteString
    }

    public static func isAllowedDownload(_ url: URL?) -> Bool {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let prefix = URLComponents(string: downloadPrefix) else { return false }
        guard c.scheme == "https", c.host == prefix.host, c.port == nil,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil else { return false }
        let path = c.path
        guard path.hasPrefix(prefix.path), path.hasSuffix(".zip") || path.hasSuffix(".dmg"),
              path.count > prefix.path.count + 4 else { return false }
        let rest = path.dropFirst(prefix.path.count)
        return !rest.contains("/") && !rest.contains("..") && !url.absoluteString.lowercased().contains("%2f")
    }

    public static let releaseNotesFormat = "plain-text"

    public static func isAllowedReleaseNotes(descriptionFormat: String?, hasDescription: Bool,
                                             releaseNotesURL: URL?, fullReleaseNotesURL: URL?) -> Bool {
        guard releaseNotesURL == nil, fullReleaseNotesURL == nil else { return false }
        guard hasDescription else { return true }
        return descriptionFormat == releaseNotesFormat
    }

    public static func feedbackURL(build: String, os: String) -> URL {
        var c = URLComponents(string: feedbackPage)!
        var items: [URLQueryItem] = []
        if let b = sanitize(build) { items.append(URLQueryItem(name: "build", value: b)) }
        if let o = sanitize(os) { items.append(URLQueryItem(name: "os", value: o)) }
        c.queryItems = items.isEmpty ? nil : items
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    static func sanitize(_ s: String) -> String? {
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._+() -")
        let kept = String(String.UnicodeScalarView(s.unicodeScalars.filter { allowed.contains($0) }).prefix(32))
            .trimmingCharacters(in: .whitespaces)
        return kept.isEmpty ? nil : kept
    }
}

public struct PublicUpdateGate: Sendable {
    public enum Rejection: Error, Equatable, Sendable {
        case feedNotAllowed
        case systemProfileEnabled
        case downloadNotAllowed
        case logUnavailable
    }

    private let log: EgressLog

    public init(log: EgressLog) { self.log = log }

    public func approveFeedCheck(_ url: URL?, feedParameters: [[String: String]], sendsSystemProfile: Bool) throws {
        guard !sendsSystemProfile else { throw Rejection.systemProfileEnabled }
        let requested = PublicUpdatePolicy.requestedFeedURL(base: url, extraParameters: feedParameters)
        guard PublicUpdatePolicy.isAllowedFeed(requested), let url = requested else { throw Rejection.feedNotAllowed }
        do { try log.record(kind: .appUpdate, endpoint: url, payload: Data()) } catch { throw Rejection.logUnavailable }
    }

    public func approveDownload(_ url: URL?) throws {
        guard PublicUpdatePolicy.isAllowedDownload(url), let url else { throw Rejection.downloadNotAllowed }
        do { try log.record(kind: .appUpdate, endpoint: url, payload: Data()) } catch { throw Rejection.logUnavailable }
    }
}
