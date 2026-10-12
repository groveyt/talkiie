import Foundation

public enum PublicConsentCopy {
    public static let title = "開始使用 Talkiie 之前"
    public static let acceptButton = "同意並開始"
    public static let quitButton = "結束"
    public static let destinationLine = "聲音不離開這台 Mac（本機轉錄）"

    public static func points(hotkey: String) -> [String] { [
        "按一下 \(hotkey) 開始說話，再按一次結束，文字會打在游標所在的地方。",
        "轉錄在這台 Mac 上進行（本機語音模型 Breeze-ASR-25）：錄到的聲音與轉出的文字都不會離開這台 Mac，聲音也不會存檔。",
        "「個人詞庫」裡「改成」那一欄的詞只在這台 Mac 上幫語音模型認字，不會送出。",
        "第一次使用要先下載語音模型（約 2 GB）：在選單列按「下載語音模型…」時，Talkiie 才會向 models.talkiie.yyt.app 下載，"
            + "只下載模型檔、不帶你的任何資料；下載好之後第一次準備約需一分鐘。",
        "需要兩個權限：「麥克風」（錄音）與「輔助使用」（把文字打進其他 app）。",
        "同意之後，Talkiie 會把自己加進「登入項目」，開機後自動在選單列待命；不想要可以到 設定 › 一般 關掉。",
        "設定裡的「也用這個鍵開始／結束」：新安裝預設是按兩下 ⌃（已經在用的人維持原本的設定，預設不使用）。選了 fn 或「按兩下 ⌃／⌥／⌘」之後，Talkiie 會看那個鍵有沒有按下，"
            + "以及按著的時候有沒有按到別的鍵或點滑鼠（只知道「有」，不記錄你打的字）；改回不使用就不再看。"
            + "只有選 fn 時會再要求「輸入監控」：macOS 只把 fn 鍵交給有這個權限的 app。",
        "Talkiie 每天會向 talkiie.yyt.app 檢查一次有沒有新版本（不帶你的任何資料）；有新版時會問你要不要重新啟動以套用。",
        "Talkiie 會在這台 Mac 記下使用統計（只有次數、字數與時間，不記你說了什麼），不會送出；可以在 設定 › 統計 關掉或全部刪除。",
        "設定裡的「收集我的修改」預設關閉。打開之後，只有在你按「收下修改」的快捷鍵（預設 ⌥K，可以改成 ⌃K）時，Talkiie 才會讀一次剛插入那段文字"
            + "前後各 200 字，用來對照你改了什麼（有些 app 不支援只讀一段，這時會讀一次整個輸入欄位，只留那一段、其餘立刻丟掉）；"
            + "只存「插入的字 → 改後的字」在這台 Mac，不送出，隨時可以全部刪除。"
            + "如果改的是聽錯的字（注音相近），Talkiie 會把正確的詞自動加進個人詞庫（標「自動加入」，可以刪除）。",
    ] }

    public static func fixtureJSON(hotkey: String) -> String {
        let payload: [String: Any] = [
            "consentVersion": PublicIdentity.consentVersion,
            "title": title,
            "points": points(hotkey: hotkey),
            "acceptButton": acceptButton,
            "quitButton": quitButton,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }
}
