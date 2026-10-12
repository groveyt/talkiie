import Foundation

public enum TraditionalChinese {
    public static func convert(_ text: String) -> String {
        TaiwanPhrases.apply(text.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? text)
    }
}
