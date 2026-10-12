import Foundation

public enum SpeculativeTailSetting {
    public static let defaultsKey = "talkiie.speculativeTail"
    public static let defaultEnabled = false

    public static func policy(fromDefaults value: Any?, researchCapture: Bool = false) -> StreamingTranscription.Speculation? {
        guard !researchCapture, (value as? Bool) ?? defaultEnabled else { return nil }
        return StreamingTranscription.Speculation.mac
    }
}
