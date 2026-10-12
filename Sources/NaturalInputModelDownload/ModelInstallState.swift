import Foundation

public enum ModelInstallState: Sendable, Equatable {
    case notDownloaded
    case downloading(receivedBytes: Int64, totalBytes: Int64)
    case verifying
    case installing
    case available(URL)
    case failed(ModelInstallFailure)

    public var fractionCompleted: Double? {
        guard case let .downloading(received, total) = self, total > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(total)))
    }
}

public enum ModelInstallFailure: Error, Sendable, Equatable {
    case notInManifest
    case hostingUndecided
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case alreadyInProgressElsewhere
    case logUnavailable
    case interrupted
    case httpStatus(Int)
    case redirectRefused
    case unexpectedRange
    case sizeMismatch
    case checksumMismatch
    case extractionFailed
    case contentsInvalid
    case fileSystem
    case cancelled

    public var keepsPartialDownload: Bool {
        switch self {
        case .interrupted, .cancelled, .extractionFailed, .contentsInvalid, .httpStatus, .redirectRefused,
             .logUnavailable, .insufficientDiskSpace, .alreadyInProgressElsewhere:
            return true
        case .notInManifest, .hostingUndecided, .unexpectedRange, .sizeMismatch, .checksumMismatch, .fileSystem:
            return false
        }
    }
}
