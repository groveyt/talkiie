import Foundation

public enum LearnedTermGate {
    public enum Rejection: String, Sendable, Equatable {
        case singleLetter
        case functionWord
        case number
        case cjkFunctionWord
        case doubledCharacterTypo
    }

    public static func rejection(_ replacement: String) -> Rejection? {
        let term = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return nil }
        if term.allSatisfy(PersonalDictionary.isHan) {
            return cjkFunctionWords.contains(TraditionalChinese.convert(term)) ? .cjkFunctionWord : nil
        }
        guard term.allSatisfy(\.isASCII) else { return nil }
        let words = term.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        for w in words {
            if w.count == 1, w.first!.isLetter { return .singleLetter }
            if englishFunctionWords.contains(w.lowercased()) { return .functionWord }
        }
        if words.count > 1, words.contains(where: { $0.allSatisfy(\.isNumber) }) { return .number }
        return nil
    }

    public static func rejection(_ replacement: String, knownTerms: some Sequence<String>) -> Rejection? {
        if let r = rejection(replacement) { return r }
        let own = foldedKey(replacement)
        let known = Set(knownTerms.map(foldedKey)).subtracting([own])
        return isDoubledCharacterVariant(replacement, ofAnyIn: known) ? .doubledCharacterTypo : nil
    }

    static func isDoubledCharacterVariant(_ term: String, ofAnyIn known: Set<String>) -> Bool {
        let folded = foldedKey(term)
        guard !known.contains(folded) else { return false }
        let chars = Array(folded)
        guard chars.count >= 2 else { return false }
        for i in 1..<chars.count where chars[i] == chars[i - 1] && chars[i].isLetter {
            var collapsed = chars
            collapsed.remove(at: i)
            if known.contains(String(collapsed)) { return true }
        }
        return false
    }

    public static func foldedKey(_ s: String) -> String { PersonalDictionary.normalizedKey(s).lowercased() }

    static let englishFunctionWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "nor", "so", "yet", "if", "then", "than", "that", "this", "these", "those",
        "there", "here", "where", "when", "what", "which", "who", "whom", "whose", "why", "how",
        "i", "me", "my", "mine", "myself", "we", "us", "our", "ours", "you", "your", "yours", "he", "him", "his",
        "she", "her", "hers", "it", "its", "they", "them", "their", "theirs",
        "is", "am", "are", "was", "were", "be", "been", "being", "do", "does", "did", "done",
        "have", "has", "had", "will", "would", "shall", "should", "can", "could", "may", "might", "must",
        "to", "of", "in", "on", "at", "by", "for", "from", "with", "without", "about", "into", "onto", "over", "under",
        "up", "down", "out", "off", "as", "also", "just", "very", "really", "too", "not", "no", "yes", "yeah",
        "okay", "ok", "oh", "um", "uh", "like", "well", "think", "know", "mean", "guess", "say", "said", "see",
        "go", "going", "get", "got", "want", "let", "lets", "all", "any", "some", "each", "every", "both",
        "more", "most", "much", "many", "such", "only", "even", "still", "again", "already", "almost", "maybe",
        "because", "while", "though", "although", "until", "since", "via", "per",
    ]

    static let cjkFunctionWords: Set<String> = [
        "時候", "什麼", "這個", "那個", "這樣", "那樣", "就是", "然後", "因為", "所以", "可以", "沒有",
        "我們", "你們", "他們", "她們", "自己", "一個", "一下", "一些", "一點", "不是", "已經", "還是", "但是",
        "如果", "應該", "現在", "知道", "覺得", "其實", "這邊", "那邊", "的話", "以後", "之後", "以前", "之前",
        "怎麼", "為什麼", "有點", "比較", "可能", "需要", "還有", "或是", "或者", "而且", "只是", "只有",
        "這些", "那些", "那麼", "這麼", "大家", "一起", "東西", "事情", "時間", "地方",
    ]
}
