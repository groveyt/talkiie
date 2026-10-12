import Foundation

public struct ModelFile: Sendable, Equatable {
    public enum Format: String, Sendable {
        case raw
        case zip
    }

    public let name: String
    public let url: URL
    public let sha256: String
    public let bytes: Int64
    public let installedBytes: Int64
    public let format: Format

    init(name: String, url: URL, sha256: String, bytes: Int64, installedBytes: Int64, format: Format) {
        self.name = name
        self.url = url
        self.sha256 = sha256
        self.bytes = bytes
        self.installedBytes = installedBytes
        self.format = format
    }
}

public struct ModelArtifact: Sendable, Equatable {
    public let id: String
    public let version: String
    public let files: [ModelFile]
    public let isPlaceholder: Bool

    init(id: String, version: String, files: [ModelFile], isPlaceholder: Bool) {
        self.id = id
        self.version = version
        self.files = files
        self.isPlaceholder = isPlaceholder
    }

    public var downloadBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    public var installedBytes: Int64 { files.reduce(0) { $0 + $1.installedBytes } }
    public var contents: [String] { files.map(\.name) }
}

public enum ModelManifest {
    public static let placeholderHost = "talkiie-models.invalid"

    public static let hostingHost = "models.talkiie.yyt.app"

    public static let breezeASR25 = ModelArtifact(
        id: "breeze-asr-25-q5_0",
        version: "1",
        files: [
            ModelFile(name: "ggml-breeze-asr-25-q5_0.bin",
                      url: URL(string: "https://models.talkiie.yyt.app/breeze-asr-25-q5_0/1/9be65cda66ee424a-ggml-breeze-asr-25-q5_0.bin")!,
                      sha256: "9be65cda66ee424a261cae9e9864e5aceb2f1be63cc01e5b670e57d022fdf335",
                      bytes: 1_080_732_108, installedBytes: 1_080_732_108, format: .raw),
            ModelFile(name: "ggml-breeze-asr-25-encoder.mlmodelc",
                      url: URL(string: "https://models.talkiie.yyt.app/breeze-asr-25-q5_0/1/09d274fa084bbe3b-ggml-breeze-asr-25-encoder.mlmodelc.zip")!,
                      sha256: "09d274fa084bbe3b60c804431decb867876c55bb9d9a18186a497a849eff2e0e",
                      bytes: 981_942_719, installedBytes: 1_273_963_992, format: .zip),
        ],
        isPlaceholder: false)

    public static let artifacts: [ModelArtifact] = [breezeASR25]

    public static func isWellFormed(_ a: ModelArtifact) -> Bool {
        guard isSafeName(a.id), isSafeName(a.version), !a.files.isEmpty,
              Set(a.contents).count == a.files.count else { return false }
        return a.files.allSatisfy(isWellFormed)
    }

    static func isWellFormed(_ f: ModelFile) -> Bool {
        guard let c = URLComponents(url: f.url, resolvingAgainstBaseURL: false),
              c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil,
              !c.path.isEmpty, !c.path.contains(".."),
              !f.url.absoluteString.lowercased().contains("%2f")
        else { return false }
        let hex = Set("0123456789abcdef")
        guard f.sha256.count == 64, f.sha256.allSatisfy({ hex.contains($0) }) else { return false }
        guard f.bytes > 0, f.installedBytes > 0 else { return false }
        if f.format == .raw && f.installedBytes != f.bytes { return false }
        return isSafeName(f.name)
    }

    static func isSafeName(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix(".") && !s.contains("/") && !s.contains("..") && !s.contains("\0")
    }
}
