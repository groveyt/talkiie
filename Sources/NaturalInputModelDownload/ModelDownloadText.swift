import Foundation

public struct DownloadProgressEstimator: Sendable, Equatable {
    public static let windowSeconds: Double = 20
    public static let minimumSpanSeconds: Double = 3

    private var times: [Double] = []
    private var bytes: [Int64] = []
    public private(set) var receivedBytes: Int64 = 0
    public private(set) var totalBytes: Int64 = 0

    public init() {}

    public mutating func note(receivedBytes: Int64, totalBytes: Int64, at: Double) {
        if let last = bytes.last, receivedBytes < last { times.removeAll(); bytes.removeAll() }
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        times.append(at)
        bytes.append(receivedBytes)
        while let first = times.first, at - first > Self.windowSeconds {
            times.removeFirst(); bytes.removeFirst()
        }
    }

    public mutating func reset() {
        times.removeAll(); bytes.removeAll(); receivedBytes = 0; totalBytes = 0
    }

    public var remainingSeconds: Int? {
        guard totalBytes > 0, let t0 = times.first, let t1 = times.last,
              let b0 = bytes.first, let b1 = bytes.last else { return nil }
        let span = t1 - t0
        let moved = b1 - b0
        guard span >= Self.minimumSpanSeconds, moved > 0 else { return nil }
        let rate = Double(moved) / span
        let left = max(0, totalBytes - receivedBytes)
        return Int((Double(left) / rate).rounded(.up))
    }
}

public enum ModelDownloadText {

    public static func bytes(_ n: Int64) -> String {
        let n = max(0, n)
        if n < 1_000_000_000 { return "\(n / 1_000_000) MB" }
        return String(format: "%.2f GB", Double(n) / 1e9)
    }

    public static func gigabytesRoundedUp(_ n: Int64) -> String {
        oneDecimal((Double(max(0, n)) / 1e8).rounded(.up) / 10)
    }

    public static func gigabytesRoundedDown(_ n: Int64) -> String {
        oneDecimal((Double(max(0, n)) / 1e8).rounded(.down) / 10)
    }

    private static func oneDecimal(_ g: Double) -> String {
        var text = String(format: "%.1f", g)
        if text.hasSuffix(".0") { text.removeLast(2) }
        return text + " GB"
    }

    public static func remaining(seconds: Int) -> String {
        let s = max(0, seconds)
        if s < 60 { return "不到 1 分鐘" }
        let minutes = (s + 30) / 60
        if minutes < 60 { return "約 \(minutes) 分鐘" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "約 \(h) 小時" : "約 \(h) 小時 \(m) 分鐘"
    }

    public static func progressLine(receivedBytes: Int64, totalBytes: Int64, remainingSeconds: Int?) -> String {
        guard totalBytes > 0 else { return "已下載 \(bytes(receivedBytes))" }
        let pct = Int((Double(min(receivedBytes, totalBytes)) / Double(totalBytes) * 100).rounded(.down))
        var line = "已下載 \(bytes(receivedBytes))／\(bytes(totalBytes))（\(pct)%）"
        if let remainingSeconds {
            line += remainingSeconds < 60 ? "，剩不到 1 分鐘" : "，約剩" + String(remaining(seconds: remainingSeconds).dropFirst(1))
        }
        return line
    }

    public enum FailureKind: Equatable, Sendable {
        case network
        case server
        case disk
        case corrupt
        case install
        case local
        case busy
        case unavailable
    }

    public static func kind(of f: ModelInstallFailure) -> FailureKind {
        switch f {
        case .interrupted: return .network
        case .httpStatus, .redirectRefused: return .server
        case .insufficientDiskSpace: return .disk
        case .checksumMismatch, .sizeMismatch, .unexpectedRange: return .corrupt
        case .extractionFailed, .contentsInvalid: return .install
        case .logUnavailable, .fileSystem: return .local
        case .alreadyInProgressElsewhere: return .busy
        case .notInManifest, .hostingUndecided, .cancelled: return .unavailable
        }
    }

    public static func offersReport(for f: ModelInstallFailure) -> Bool {
        switch kind(of: f) {
        case .server, .corrupt, .install, .local: return true
        case .network, .disk, .busy, .unavailable: return false
        }
    }

    public static func failureReason(_ f: ModelInstallFailure) -> String {
        switch f {
        case .interrupted:
            return "網路連不上或中斷了。連線恢復後再按一次，會從斷掉的地方繼續"
        case .httpStatus(let code):
            return "伺服器出了問題（代碼 \(code)），不是你的網路。稍後再試；一直失敗的話請按「回報問題…」"
        case .redirectRefused:
            return "伺服器出了問題（回應的位置不對，已拒絕）。稍後再試；一直失敗的話請按「回報問題…」"
        case .insufficientDiskSpace(let need, let have):
            return "磁碟空間不夠：需要約 \(gigabytesRoundedUp(need)) 可用，目前只有 \(gigabytesRoundedDown(have))。"
                + "（模型本身約 2.4 GB；下載時壓縮檔與解開的檔案會同時存在，另外留 1 GB 給系統，所以要的比 2.4 GB 多。）"
                + "清出空間後再按一次"
        case .alreadyInProgressElsewhere: return "另一個 Talkiie 正在下載"
        case .checksumMismatch, .sizeMismatch, .unexpectedRange:
            return "下載的檔案不正確，已刪除，請重試；重試還是不行的話請按「回報問題…」"
        case .extractionFailed, .contentsInvalid: return "安裝失敗，請重試；重試還是不行的話請按「回報問題…」"
        case .logUnavailable, .fileSystem: return "無法寫入本機資料夾"
        case .notInManifest, .hostingUndecided: return "模型下載尚未開放"
        case .cancelled: return "已取消"
        }
    }
}
