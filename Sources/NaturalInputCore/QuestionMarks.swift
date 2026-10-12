import Foundation

enum QuestionMarks {
    static func apply(_ paragraph: String) -> String {
        var chars = Array(paragraph)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            let next = i + 1
            let atEnd = next == chars.count
            if maParticles.contains(c) {
                if atEnd {
                    chars.append("？")
                    break
                }
                if replaceable.contains(chars[next]) { chars[next] = "？" }
            } else if particles.contains(c), atEnd || strictReplaceable.contains(chars[next]) {
                let clause = clauseBefore(chars, i)
                let question = c == "吧" || c == "罢" ? isConfirmationBa(clause) : isQuestionClause(clause)
                if question {
                    if atEnd {
                        chars.append("？")
                        break
                    }
                    chars[next] = "？"
                }
            }
            i += 1
        }
        return String(chars)
    }

    static func clauseBefore(_ chars: [Character], _ i: Int) -> String {
        var start = i
        while start > 0, !clauseBoundaries.contains(chars[start - 1]) { start -= 1 }
        return String(chars[start..<i])
    }

    static func isQuestionClause(_ clause: String) -> Bool {
        if notQuestion.contains(where: { clause.contains($0) }) { return false }
        if clause.contains("都") || clause.contains("也") { return false }
        if embeddingVerbs.contains(where: { clause.contains($0) }) { return false }
        if questionWords.contains(where: { clause.contains($0) }) { return true }
        let c = Array(clause)
        guard c.count >= 3 else { return false }
        for k in 0..<(c.count - 2) where c[k] == c[k + 2] && negations.contains(c[k + 1]) && !negations.contains(c[k]) && isHan(c[k]) {
            return true
        }
        return false
    }

    static func isConfirmationBa(_ clause: String) -> Bool {
        if ["對", "对", "沒錯", "没错"].contains(where: { clause.hasSuffix($0) }) { return true }
        if clause.contains("該不會") || clause.contains("该不会") { return true }
        let addressee = ["你", "妳", "您"].contains(where: { clause.contains($0) })
        let guess = guessCues.contains(where: { clause.contains($0) })
        return addressee && guess
    }

    private static func isHan(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) }
    }

    private static let maParticles: Set<Character> = ["嗎", "吗"]
    private static let particles: Set<Character> = ["呢", "啊", "呀", "哇", "哪", "吧", "罢"]
    private static let replaceable: Set<Character> = ["。", "，", "；", ".", ","]
    private static let strictReplaceable: Set<Character> = ["。", "；", "."]
    private static let clauseBoundaries: Set<Character> = ["，", "。", "？", "！", "；", "：", "、", ",", ".", "?", "!", ";", ":", "\n"]
    private static let negations: Set<Character> = ["不", "沒", "没"]
    private static let questionWords = [
        "什麼", "什么", "甚麼", "誰", "谁", "哪", "怎麼", "怎么", "怎樣", "怎样",
        "為什麼", "为什么", "為何", "为何", "如何", "幹嘛", "干嘛", "啥", "是否",
    ]
    private static let guessCues = [
        "應該可以", "应该可以", "應該會", "应该会", "應該是", "应该是", "應該有", "应该有",
        "應該已經", "应该已经", "大概",
    ]
    private static let embeddingVerbs = [
        "想", "看看", "看要", "決定", "决定", "考慮", "考虑", "研究", "討論", "讨论", "知道", "記得", "记得",
        "說說", "说说", "猜",
    ]
    private static let notQuestion = [
        "什麼都", "什么都", "什麼也", "什么也", "什麼的", "什么的", "沒什麼", "没什么", "沒有什麼", "没有什么", "不是什麼", "不是什么", "有什麼就", "有什么就", "不怎麼", "不怎么",
        "誰都", "谁都", "誰也", "谁也", "哪裡都", "哪里都", "哪兒都", "哪儿都", "哪都", "哪怕",
        "怎麼都", "怎么都", "怎樣都", "怎样都", "沒啥", "没啥", "啥都",
        "不管", "無論", "无论", "不論", "不论", "隨便", "随便",
        "不知道", "不確定", "不确定", "不曉得", "不晓得", "不清楚",
    ]
}
