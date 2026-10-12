import Foundation

public enum PanguSpacing {
    public static func apply(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.utf8.count + 8)
        var beforePrevious: Character?
        var previous: Character?
        for c in text {
            if let p = previous, needsSpace(beforePrevious, p, c) { out.append(" ") }
            out.append(c)
            beforePrevious = previous
            previous = c
        }
        return out
    }

    static func needsSpace(_ z: Character?, _ a: Character, _ b: Character) -> Bool {
        let aLatin = isAlnum(a) || (a == "%" && z.map(isDigit) == true)
        return (TranscriptFormatter.isHan(a) && isAlnum(b)) || (aLatin && TranscriptFormatter.isHan(b))
    }

    static func isAlnum(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber) }
    static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }
}
