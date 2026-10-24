import Foundation

public enum RoundNotices {
    public static func emptyTranscript(level: AudioLevelSummary?) -> String {
        if let level, level.isSilent {
            return "沒聽到內容：沒收到聲音，請檢查麥克風後再說一次"
        }
        return "沒聽到內容：麥克風有收到聲音，但沒辨識出字；再說一次試試"
    }

    public static let slowRoundSeconds: Double = 5
    public static let slowRoundMillis: Int = Int(slowRoundSeconds * 1000)
    public static let stillWorkingCaption = "還在處理，請稍等…"
}
