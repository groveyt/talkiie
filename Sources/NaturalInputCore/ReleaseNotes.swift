import Foundation

public struct ReleaseNotes: Decodable, Equatable, Sendable {
    public struct Release: Decodable, Equatable, Sendable, Identifiable {
        public let version: String
        public let date: String
        public let items: [Item]
        public let summary: String?
        public var id: String { version }

        public init(version: String, date: String, items: [Item], summary: String? = nil) {
            self.version = version
            self.date = date
            self.items = items
            self.summary = summary
        }
    }

    public struct Item: Decodable, Equatable, Sendable {
        public enum Kind: String, Decodable, Sendable {
            case new, improved, fixed
        }
        public let kind: Kind
        public let title: String
        public let body: String
        public let how: [String]?

        public init(kind: Kind, title: String, body: String, how: [String]? = nil) {
            self.kind = kind
            self.title = title
            self.body = body
            self.how = how
        }
    }

    public let releases: [Release]

    public init(releases: [Release]) { self.releases = releases }

    public static func decode(_ data: Data) -> ReleaseNotes? {
        try? JSONDecoder().decode(ReleaseNotes.self, from: data)
    }

    public func between(_ from: String?, _ to: String) -> [Release] {
        releases
            .filter { r in
                !AppVersion.less(to, r.version) && (from.map { AppVersion.less($0, r.version) } ?? true)
            }
            .sorted { AppVersion.less($1.version, $0.version) }
    }

    public func previous(before version: String) -> String? {
        releases.map(\.version).filter { AppVersion.less($0, version) }.max(by: AppVersion.less)
    }
}

public enum AppVersion {
    public static func less(_ a: String, _ b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
}

public enum WhatsNewPlan {
    public enum Keys {
        public static let lastVersion = "whatsNew.lastVersion"
        public static let unseen = "whatsNew.unseen"
        public static let since = "whatsNew.since"
        public static let relaunchedByUpdate = "whatsNew.relaunchedByUpdate"
    }

    public struct State: Equatable, Sendable {
        public var lastVersion: String?
        public var unseen: String?
        public var since: String?

        public init(lastVersion: String? = nil, unseen: String? = nil, since: String? = nil) {
            self.lastVersion = lastVersion
            self.unseen = unseen
            self.since = since
        }
    }

    public enum Presentation: Equatable, Sendable {
        case none
        case window
        case menuOnly
    }

    public struct Launch: Equatable, Sendable {
        public let state: State
        public let presentation: Presentation
        public let releases: [String]
    }

    public static func onLaunch(current: String, state: State, relaunchedByUpdate: Bool,
                                consented: Bool, notes: ReleaseNotes?) -> Launch {
        var next = state
        next.lastVersion = current
        let none = Launch(state: next, presentation: .none, releases: [])
        guard state.lastVersion.map({ AppVersion.less($0, current) }) ?? consented else { return none }
        guard let notes else { return none }
        let from = state.since ?? state.lastVersion ?? notes.previous(before: current)
        let shown = notes.between(from, current)
        guard !shown.isEmpty else { return none }
        if next.since == nil { next.since = from }
        next.unseen = current
        return Launch(state: next, presentation: relaunchedByUpdate ? .window : .menuOnly,
                      releases: shown.map(\.version))
    }

    public static func content(current: String, state: State, notes: ReleaseNotes) -> (from: String?, to: String, releases: [ReleaseNotes.Release]) {
        let to = state.unseen ?? current
        let from = state.unseen != nil ? state.since : notes.previous(before: to)
        return (from, to, notes.between(from, to))
    }

    public static func afterShown(_ state: State) -> State {
        State(lastVersion: state.lastVersion, unseen: nil, since: nil)
    }
}
