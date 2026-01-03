import Foundation

func stripAnsiCodes(_ text: String) -> String {
    let pattern = "\u{001B}\\[[0-9;]*[mGKHJ]"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return text
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
}

func stripVTControlCharacters(_ text: String) -> String {
    let stripped = stripAnsiCodes(text)
    let filtered = stripped.unicodeScalars.filter { scalar in
        scalar.value >= 32 || scalar == "\n"
    }
    return String(String.UnicodeScalarView(filtered))
}

enum Ansi {
    static func wrap(_ codes: [String], _ text: String) -> String {
        return "\u{001B}[" + codes.joined(separator: ";") + "m" + text + "\u{001B}[0m"
    }

    static func blue(_ text: String) -> String { wrap(["34"], text) }
    static func cyan(_ text: String) -> String { wrap(["36"], text) }
    static func yellow(_ text: String) -> String { wrap(["33"], text) }
    static func green(_ text: String) -> String { wrap(["32"], text) }
    static func red(_ text: String) -> String { wrap(["31"], text) }
    static func gray(_ text: String) -> String { wrap(["90"], text) }
    static func dim(_ text: String) -> String { wrap(["2"], text) }
    static func bold(_ text: String) -> String { wrap(["1"], text) }
    static func italic(_ text: String) -> String { wrap(["3"], text) }
    static func underline(_ text: String) -> String { wrap(["4"], text) }
    static func strikethrough(_ text: String) -> String { wrap(["9"], text) }
}

extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = self
        while let last = result.last, last.isWhitespace || last.isNewline {
            result.removeLast()
        }
        return result
    }
}
