import Foundation

public enum InsertionText {
    public static func paragraphs(_ paragraphs: [String]) -> [String] {
        var out: [String] = []
        for p in paragraphs.map(sanitized) {
            if p.isEmpty, out.last?.isEmpty ?? true { continue }
            out.append(p)
        }
        if out.last?.isEmpty == true { out.removeLast() }
        return out
    }

    public static func sanitized(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        var lastWasSpace = true
        for scalar in text.unicodeScalars {
            let isBreak = scalar.properties.generalCategory == .control
                || scalar.value == 0x2028 || scalar.value == 0x2029
            let s: Unicode.Scalar = isBreak ? " " : scalar
            if s == " " {
                if lastWasSpace { continue }
                lastWasSpace = true
            } else {
                lastWasSpace = false
            }
            out.append(s)
        }
        if lastWasSpace, out.last == " " { out.removeLast() }
        return String(out)
    }
}
