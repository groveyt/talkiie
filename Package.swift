// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NaturalInput",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NaturalInputCore", targets: ["NaturalInputCore"]),
        .library(name: "NaturalInputEgress", targets: ["NaturalInputEgress"]),
        .library(name: "NaturalInputEgressPublic", targets: ["NaturalInputEgressPublic"]),
        .library(name: "NaturalInputModelDownload", targets: ["NaturalInputModelDownload"]),
        .library(name: "NaturalInputLocalASR", targets: ["NaturalInputLocalASR"]),
        .library(name: "TalkiieOrb", targets: ["TalkiieOrb"]),
        .library(name: "TalkiieLicensing", targets: ["TalkiieLicensing"]),
    ],
    targets: [
        // OpenCC/: Taiwan phrase dictionary (Apache-2.0). Bopomofo/: zhuyin tables (McBopomofo MIT + libtabe BSD,
        // licence texts in Bopomofo/LICENSE). WhisperTokenizer/: Whisper's multilingual vocabulary (OpenAI, MIT).
        .target(name: "NaturalInputCore", dependencies: ["TalkiieOrb"],
                resources: [.copy("OpenCC"), .copy("Bopomofo"), .copy("WhisperTokenizer")]),
        // The dotted orb's geometry (port of Thinking Orbs, MIT) and the voice-level envelope. Foundation only.
        .target(name: "TalkiieOrb"),
        .target(name: "NaturalInputEgress", dependencies: ["NaturalInputCore"]),
        .target(name: "NaturalInputEgressPublic", dependencies: ["NaturalInputEgress"]),
        .target(name: "NaturalInputModelDownload", dependencies: ["NaturalInputEgress"]),
        .binaryTarget(name: "whisper", path: "Vendor/whisper/whisper-coreml.xcframework.zip"),
        .target(name: "NaturalInputLocalASR", dependencies: ["NaturalInputCore", "whisper"], exclude: ["README.md"]),
        .target(name: "TalkiieLicensing"),
    ]
)
