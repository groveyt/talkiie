import Foundation

public enum UnicodeChunker {

    public static let defaultMaxUnits = 16

    public static func chunks(_ text: String, maxUnits: Int = defaultMaxUnits) -> [[UInt16]] {
        precondition(maxUnits >= 2, "maxUnits 至少要 2，否則裝不下一個 surrogate pair")
        var out: [[UInt16]] = []
        var current: [UInt16] = []

        func flush() {
            if !current.isEmpty { out.append(current); current = [] }
        }

        for cluster in text {
            let units = Array(String(cluster).utf16)
            if units.count > maxUnits {
                flush()
                for scalar in cluster.unicodeScalars {
                    let su = Array(String(scalar).utf16)
                    if current.count + su.count > maxUnits { flush() }
                    current.append(contentsOf: su)
                }
                flush()
                continue
            }
            if current.count + units.count > maxUnits { flush() }
            current.append(contentsOf: units)
        }
        flush()
        return out
    }
}
