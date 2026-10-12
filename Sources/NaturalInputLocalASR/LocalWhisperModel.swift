import Foundation

public struct LocalWhisperModel: Equatable, Sendable {
    public static let breezeFileName = "ggml-breeze-asr-25-q5_0.bin"

    public let directory: URL
    public let fileName: String

    public init(directory: URL, fileName: String = LocalWhisperModel.breezeFileName) {
        self.directory = directory
        self.fileName = fileName
    }

    public var modelURL: URL { directory.appendingPathComponent(fileName, isDirectory: false) }

    public var coreMLEncoderURL: URL { URL(fileURLWithPath: Self.coreMLEncoderPath(forModelPath: modelURL.path)) }

    static func coreMLEncoderPath(forModelPath path: String) -> String {
        var p = path
        if let dot = p.lastIndex(of: ".") { p = String(p[..<dot]) }
        if let dash = p.lastIndex(of: "-") {
            let sub = Array(p[dash...])
            if sub.count == 5, sub[1] == "q", sub[3] == "_" { p = String(p[..<dash]) }
        }
        return p + "-encoder.mlmodelc"
    }

    public func preflight(fileManager: FileManager = .default) throws(LocalWhisperError) {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            throw .modelDirectoryMissing
        }
        guard fileManager.fileExists(atPath: modelURL.path, isDirectory: &isDir), !isDir.boolValue else {
            throw .modelFileMissing(fileName)
        }
        let encoder = coreMLEncoderURL
        guard fileManager.fileExists(atPath: encoder.path, isDirectory: &isDir), isDir.boolValue,
              fileManager.fileExists(atPath: encoder.appendingPathComponent("coremldata.bin").path, isDirectory: &isDir),
              !isDir.boolValue else {
            throw .coreMLEncoderMissing(encoder.lastPathComponent)
        }
    }
}

public enum LocalWhisperError: Error, Equatable, Sendable, CustomStringConvertible {
    case modelDirectoryMissing
    case modelFileMissing(String)
    case coreMLEncoderMissing(String)
    case modelLoadFailed
    case coreMLLoadFailed
    case stateInitFailed

    public var userMessage: String {
        switch self {
        case .modelDirectoryMissing, .modelFileMissing, .coreMLEncoderMissing:
            return "找不到本機語音模型，這段口述沒有轉錄"
        case .modelLoadFailed, .coreMLLoadFailed, .stateInitFailed:
            return "本機語音模型載入失敗，這段口述沒有轉錄"
        }
    }

    public var description: String {
        switch self {
        case .modelDirectoryMissing: return "模型目錄不存在"
        case .modelFileMissing(let f): return "找不到模型檔 \(f)"
        case .coreMLEncoderMissing(let f): return "找不到 Core ML encoder \(f)（ALLOW_FALLBACK=OFF：沒有它就不能轉錄）"
        case .modelLoadFailed: return "whisper_init_from_file_with_params_no_state 失敗"
        case .coreMLLoadFailed: return "whisper_init_state 失敗：Core ML encoder 載不起來（ALLOW_FALLBACK=OFF，不退回 Metal）"
        case .stateInitFailed: return "whisper_init_state 失敗（非 Core ML）"
        }
    }
}

public struct LocalWhisperLoadReport: Equatable, Sendable {
    public let modelMillis: Int
    public let stateMillis: Int

    public var totalMillis: Int { modelMillis + stateMillis }
}
