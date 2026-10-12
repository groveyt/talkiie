import Foundation

/// 資料：OpenCC（Apache-2.0，見 THIRD_PARTY_NOTICES.md）`data/dictionary/`，原樣入庫在 `OpenCC/`。
public enum TaiwanPhrases {
    public static func apply(_ text: String) -> String {
        guard let table, !text.isEmpty else { return text }
        return table.convert(text)
    }

    public static var isAvailable: Bool { table != nil }

    public static var vocabulary: [String: String] { table?.vocabulary ?? [:] }

    static let excluded: Set<String> = [
        "打開", "支持", "對象", "文件", "項目", "程序", "進程", "窗口", "消息", "社區",
        "高級", "低級", "菜單", "數據", "代碼", "溢出", "呼出", "導入", "保存", "聲明",
        "設置", "循環", "分區", "局部", "註銷", "連接", "運行", "設備", "查看", "映射",
        "發送", "添加", "優化", "刷新", "奔馳", "觸摸", "指針", "屏蔽", "圖庫", "壁紙",
        "性能", "調度", "掛斷", "布爾", "審覈",
        "擴展", "權限", "全局", "實例", "參數", "類型", "發佈", "萬象", "死機", "控件",
        "標識符", "網卡", "重載", "回調", "鏡像",
    ]

    static let table: Table? = Table.loadBundled()

    struct Table {
        let keep: Set<String>
        let keepMaxLength: [Character: Int]
        let variants: [Character: Character]
        let vocabulary: [String: String]

        static func loadBundled() -> Table? {
            guard let phrases = read("TWPhrases"), let variantPhrases = read("TWVariantsPhrases"),
                  let variants = read("TWVariants") else { return nil }
            return Table(phrases: phrases, variantPhrases: variantPhrases, variants: variants)
        }

        private static func read(_ name: String) -> String? {
            guard let path = Bundle.module.path(forResource: name, ofType: "txt", inDirectory: "OpenCC"),
                  let data = FileManager.default.contents(atPath: path) else { return nil }
            return String(data: data, encoding: .utf8)
        }

        static func parse(_ text: String) -> [(String, String)] {
            text.split(whereSeparator: \.isNewline).compactMap { line in
                guard !line.hasPrefix("#") else { return nil }
                let cols = line.split(separator: "\t", maxSplits: 1)
                guard cols.count == 2, let first = cols[1].split(separator: " ").first else { return nil }
                return (String(cols[0]), String(first))
            }
        }

        init(phrases phraseText: String, variantPhrases: String, variants variantText: String) {
            var variants: [Character: Character] = [:]
            for (k, v) in Self.parse(variantText) where k.count == 1 && v.count == 1 && k != v {
                variants[Character(k)] = Character(v)
            }
            let keep = Set(Self.parse(variantPhrases).map(\.0))
            var m: [Character: Int] = [:]
            for k in keep { if let f = k.first { m[f] = max(m[f] ?? 0, k.count) } }
            func norm(_ s: String) -> String { String(s.map { variants[$0] ?? $0 }) }
            func icu(_ s: String) -> String { s.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? s }
            var vocab: [String: String] = [:]
            for (k, v) in Self.parse(phraseText) where !TaiwanPhrases.excluded.contains(k) {
                vocab[norm(icu(k))] = norm(icu(v))
            }
            self.keep = keep
            self.keepMaxLength = m
            self.variants = variants
            self.vocabulary = vocab
        }

        func convert(_ text: String) -> String {
            let chars = Array(text)
            var out = String()
            out.reserveCapacity(text.utf8.count)
            var i = 0
            while i < chars.count {
                if let longest = keepMaxLength[chars[i]] {
                    var len = min(longest, chars.count - i)
                    var kept = false
                    while len >= 2 {
                        let key = String(chars[i..<(i + len)])
                        if keep.contains(key) { out += key; i += len; kept = true; break }
                        len -= 1
                    }
                    if kept { continue }
                }
                out.append(variants[chars[i]] ?? chars[i])
                i += 1
            }
            return out
        }
    }
}
