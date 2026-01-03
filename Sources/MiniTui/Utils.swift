import Foundation

private let ansiEscape = "\u{001B}"

/// Return the display width of a string, ignoring ANSI escape codes.
public func visibleWidth(_ str: String) -> Int {
    guard !str.isEmpty else { return 0 }

    var isPureAscii = true
    for scalar in str.unicodeScalars {
        if scalar.value < 0x20 || scalar.value > 0x7E {
            isPureAscii = false
            break
        }
    }
    if isPureAscii {
        return str.count
    }

    var clean = str.replacingOccurrences(of: "\t", with: "   ")
    if clean.contains(ansiEscape) {
        clean = stripAnsiCodes(clean)
    }

    var width = 0
    for character in clean {
        width += graphemeWidth(character)
    }

    return width
}

func stripAnsiCodes(_ text: String) -> String {
    var result = text

    // Strip SGR + cursor codes.
    result = result.replacingMatches(of: "\u{001B}\\[[0-9;]*[mGKHJ]", with: "")

    // Strip OSC 8 hyperlinks.
    result = result.replacingMatches(of: "\u{001B}\\]8;;[^\u{0007}]*\u{0007}", with: "")

    return result
}

private func graphemeWidth(_ grapheme: Character) -> Int {
    let scalars = Array(grapheme.unicodeScalars)
    if scalars.allSatisfy({ isZeroWidthScalar($0) }) {
        return 0
    }

    if isEmoji(grapheme) {
        return 2
    }

    guard let baseIndex = scalars.firstIndex(where: { !isZeroWidthScalar($0) }) else {
        return 0
    }

    var width = eastAsianWidth(scalars[baseIndex])

    if scalars.count > baseIndex + 1 {
        for scalar in scalars[(baseIndex + 1)...] {
            if scalar.value >= 0xFF00 && scalar.value <= 0xFFEF {
                width += eastAsianWidth(scalar)
            }
        }
    }

    return width
}

private func isZeroWidthScalar(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.properties.isDefaultIgnorableCodePoint {
        return true
    }

    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark, .format, .control, .surrogate:
        return true
    default:
        return false
    }
}

private func isEmoji(_ grapheme: Character) -> Bool {
    let scalars = Array(grapheme.unicodeScalars)
    if scalars.count > 2 {
        return true
    }

    var hasEmojiCandidate = false
    for scalar in scalars {
        let value = scalar.value
        if value == 0xFE0F {
            return true
        }
        if (0x1F000...0x1FBFF).contains(value)
            || (0x2300...0x23FF).contains(value)
            || (0x2600...0x27BF).contains(value)
            || (0x2B50...0x2B55).contains(value) {
            hasEmojiCandidate = true
        }
    }

    return hasEmojiCandidate
}

private func eastAsianWidth(_ scalar: Unicode.Scalar) -> Int {
    return isWideScalar(scalar.value) ? 2 : 1
}

private func isWideScalar(_ value: UInt32) -> Bool {
    switch value {
    case 0x1100...0x115F,
         0x2329, 0x232A,
         0x2E80...0xA4CF,
         0xAC00...0xD7A3,
         0xF900...0xFAFF,
         0xFE10...0xFE19,
         0xFE30...0xFE6F,
         0xFF00...0xFF60,
         0xFFE0...0xFFE6:
        return true
    default:
        return false
    }
}

/// Wrap text to a target width while preserving ANSI escape sequences.
public func wrapTextWithAnsi(_ text: String, width: Int) -> [String] {
    guard !text.isEmpty else { return [""] }

    let inputLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var result: [String] = []
    let tracker = AnsiCodeTracker()

    for inputLine in inputLines {
        let prefix = result.isEmpty ? "" : tracker.getActiveCodes()
        result.append(contentsOf: wrapSingleLine(prefix + inputLine, width: width, tracker: tracker))
        updateTrackerFromText(inputLine, tracker: tracker)
    }

    return result.isEmpty ? [""] : result
}

private func wrapSingleLine(_ line: String, width: Int, tracker: AnsiCodeTracker) -> [String] {
    guard !line.isEmpty else { return [""] }

    if visibleWidth(line) <= width {
        return [line]
    }

    var wrapped: [String] = []
    let tokens = splitIntoTokensWithAnsi(line)
    var currentLine = ""
    var currentVisibleLength = 0

    for token in tokens {
        let tokenVisibleLength = visibleWidth(token)
        let isWhitespace = token.trimmingCharacters(in: .whitespaces).isEmpty

        if tokenVisibleLength > width && !isWhitespace {
            if !currentLine.isEmpty {
                let lineEndReset = tracker.getLineEndReset()
                if !lineEndReset.isEmpty {
                    currentLine += lineEndReset
                }
                wrapped.append(currentLine)
                currentLine = ""
                currentVisibleLength = 0
            }

            let broken = breakLongWord(token, width: width, tracker: tracker)
            wrapped.append(contentsOf: broken.dropLast())
            if let last = broken.last {
                currentLine = last
                currentVisibleLength = visibleWidth(currentLine)
            }
            continue
        }

        let totalNeeded = currentVisibleLength + tokenVisibleLength
        if totalNeeded > width && currentVisibleLength > 0 {
            var lineToWrap = trimTrailingSpaces(currentLine)
            let lineEndReset = tracker.getLineEndReset()
            if !lineEndReset.isEmpty {
                lineToWrap += lineEndReset
            }
            wrapped.append(lineToWrap)

            if isWhitespace {
                currentLine = tracker.getActiveCodes()
                currentVisibleLength = 0
            } else {
                currentLine = tracker.getActiveCodes() + token
                currentVisibleLength = tokenVisibleLength
            }
        } else {
            currentLine += token
            currentVisibleLength += tokenVisibleLength
        }

        updateTrackerFromText(token, tracker: tracker)
    }

    if !currentLine.isEmpty {
        wrapped.append(currentLine)
    }

    return wrapped.isEmpty ? [""] : wrapped
}

/// Return true when a character is whitespace or a newline.
public func isWhitespaceChar(_ char: Character) -> Bool {
    return char.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
}

private let punctuationSet = CharacterSet(charactersIn: "(){}[]<>.,;:'\"!?+-=*/\\|&%^$#@~`")

/// Return true when a character is treated as punctuation.
public func isPunctuationChar(_ char: Character) -> Bool {
    return char.unicodeScalars.allSatisfy { punctuationSet.contains($0) }
}

private func breakLongWord(_ word: String, width: Int, tracker: AnsiCodeTracker) -> [String] {
    var lines: [String] = []
    var currentLine = tracker.getActiveCodes()
    var currentWidth = 0

    var segments: [(type: SegmentType, value: String)] = []
    var i = 0
    let length = word.count

    while i < length {
        if let ansiResult = extractAnsiCode(word, at: i) {
            segments.append((.ansi, ansiResult.code))
            i += ansiResult.length
            continue
        }

        var end = i
        while end < length {
            if extractAnsiCode(word, at: end) != nil {
                break
            }
            end += 1
        }

        let textPortion = word.substring(from: i, length: end - i)
        for character in textPortion {
            segments.append((.grapheme, String(character)))
        }
        i = end
    }

    for segment in segments {
        switch segment.type {
        case .ansi:
            currentLine += segment.value
            tracker.process(segment.value)
        case .grapheme:
            let grapheme = segment.value
            if grapheme.isEmpty {
                continue
            }
            let graphemeWidth = visibleWidth(grapheme)
            if currentWidth + graphemeWidth > width {
                let lineEndReset = tracker.getLineEndReset()
                if !lineEndReset.isEmpty {
                    currentLine += lineEndReset
                }
                lines.append(currentLine)
                currentLine = tracker.getActiveCodes()
                currentWidth = 0
            }

            currentLine += grapheme
            currentWidth += graphemeWidth
        }
    }

    if !currentLine.isEmpty {
        lines.append(currentLine)
    }

    return lines.isEmpty ? [""] : lines
}

/// Apply a background formatter to a padded line.
public func applyBackgroundToLine(_ line: String, width: Int, bgFn: (String) -> String) -> String {
    let visibleLen = visibleWidth(line)
    let paddingNeeded = max(0, width - visibleLen)
    let padding = String(repeating: " ", count: paddingNeeded)
    let withPadding = line + padding
    return bgFn(withPadding)
}

/// Truncate text to a visible width, preserving ANSI codes and adding an ellipsis.
public func truncateToWidth(_ text: String, maxWidth: Int, ellipsis: String = "...") -> String {
    let textVisibleWidth = visibleWidth(text)
    if textVisibleWidth <= maxWidth {
        return text
    }

    let ellipsisWidth = visibleWidth(ellipsis)
    let targetWidth = maxWidth - ellipsisWidth
    if targetWidth <= 0 {
        return String(ellipsis.prefix(maxWidth))
    }

    var segments: [(type: SegmentType, value: String)] = []
    var i = 0
    let length = text.count

    while i < length {
        if let ansiResult = extractAnsiCode(text, at: i) {
            segments.append((.ansi, ansiResult.code))
            i += ansiResult.length
            continue
        }

        var end = i
        while end < length {
            if extractAnsiCode(text, at: end) != nil {
                break
            }
            end += 1
        }

        let textPortion = text.substring(from: i, length: end - i)
        for character in textPortion {
            segments.append((.grapheme, String(character)))
        }
        i = end
    }

    var result = ""
    var currentWidth = 0

    for segment in segments {
        switch segment.type {
        case .ansi:
            result += segment.value
        case .grapheme:
            let grapheme = segment.value
            if grapheme.isEmpty {
                continue
            }
            let graphemeWidth = visibleWidth(grapheme)
            if currentWidth + graphemeWidth > targetWidth {
                break
            }
            result += grapheme
            currentWidth += graphemeWidth
        }
    }

    return "\(result)\u{001B}[0m\(ellipsis)"
}

private enum SegmentType {
    case ansi
    case grapheme
}

private func trimTrailingSpaces(_ text: String) -> String {
    guard !text.isEmpty else { return text }
    var result = text
    while result.last == " " {
        result.removeLast()
    }
    return result
}

private func extractAnsiCode(_ text: String, at pos: Int) -> (code: String, length: Int)? {
    guard text.character(at: pos) == "\u{001B}", text.character(at: pos + 1) == "[" else {
        return nil
    }

    var j = pos + 2
    let length = text.count

    while j < length {
        guard let ch = text.character(at: j) else {
            break
        }
        if ch == "m" || ch == "G" || ch == "K" || ch == "H" || ch == "J" {
            let startIndex = text.index(at: pos)
            let endIndex = text.index(at: j + 1)
            return (String(text[startIndex..<endIndex]), j + 1 - pos)
        }
        j += 1
    }

    return nil
}

private func updateTrackerFromText(_ text: String, tracker: AnsiCodeTracker) {
    var i = 0
    let length = text.count
    while i < length {
        if let ansiResult = extractAnsiCode(text, at: i) {
            tracker.process(ansiResult.code)
            i += ansiResult.length
        } else {
            i += 1
        }
    }
}

private func splitIntoTokensWithAnsi(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var pendingAnsi = ""
    var inWhitespace = false

    var i = 0
    let length = text.count

    while i < length {
        if let ansiResult = extractAnsiCode(text, at: i) {
            pendingAnsi += ansiResult.code
            i += ansiResult.length
            continue
        }

        let char = text.character(at: i) ?? " "
        let charIsSpace = char == " "

        if charIsSpace != inWhitespace, !current.isEmpty {
            tokens.append(current)
            current = ""
        }

        if !pendingAnsi.isEmpty {
            current += pendingAnsi
            pendingAnsi = ""
        }

        inWhitespace = charIsSpace
        current.append(char)
        i += 1
    }

    if !pendingAnsi.isEmpty {
        current += pendingAnsi
    }

    if !current.isEmpty {
        tokens.append(current)
    }

    return tokens
}

private final class AnsiCodeTracker {
    private var bold = false
    private var dim = false
    private var italic = false
    private var underline = false
    private var blink = false
    private var inverse = false
    private var hidden = false
    private var strikethrough = false
    private var fgColor: String?
    private var bgColor: String?

    func process(_ ansiCode: String) {
        guard ansiCode.hasSuffix("m"), ansiCode.hasPrefix("\u{001B}[") else {
            return
        }

        let paramsStart = ansiCode.index(ansiCode.startIndex, offsetBy: 2)
        let paramsEnd = ansiCode.index(before: ansiCode.endIndex)
        let params = String(ansiCode[paramsStart..<paramsEnd])

        if params.isEmpty || params == "0" {
            reset()
            return
        }

        let parts = params.split(separator: ";")
        var i = 0
        while i < parts.count {
            let part = parts[i]
            let code = Int(part) ?? 0

            if code == 38 || code == 48 {
                if i + 2 < parts.count, parts[i + 1] == "5" {
                    let colorCode = "\(code);\(parts[i + 1]);\(parts[i + 2])"
                    if code == 38 {
                        fgColor = colorCode
                    } else {
                        bgColor = colorCode
                    }
                    i += 3
                    continue
                } else if i + 4 < parts.count, parts[i + 1] == "2" {
                    let colorCode = "\(code);\(parts[i + 1]);\(parts[i + 2]);\(parts[i + 3]);\(parts[i + 4])"
                    if code == 38 {
                        fgColor = colorCode
                    } else {
                        bgColor = colorCode
                    }
                    i += 5
                    continue
                }
            }

            switch code {
            case 0:
                reset()
            case 1:
                bold = true
            case 2:
                dim = true
            case 3:
                italic = true
            case 4:
                underline = true
            case 5:
                blink = true
            case 7:
                inverse = true
            case 8:
                hidden = true
            case 9:
                strikethrough = true
            case 21:
                bold = false
            case 22:
                bold = false
                dim = false
            case 23:
                italic = false
            case 24:
                underline = false
            case 25:
                blink = false
            case 27:
                inverse = false
            case 28:
                hidden = false
            case 29:
                strikethrough = false
            case 39:
                fgColor = nil
            case 49:
                bgColor = nil
            default:
                if (30...37).contains(code) || (90...97).contains(code) {
                    fgColor = String(code)
                } else if (40...47).contains(code) || (100...107).contains(code) {
                    bgColor = String(code)
                }
            }
            i += 1
        }
    }

    func getActiveCodes() -> String {
        var codes: [String] = []
        if bold { codes.append("1") }
        if dim { codes.append("2") }
        if italic { codes.append("3") }
        if underline { codes.append("4") }
        if blink { codes.append("5") }
        if inverse { codes.append("7") }
        if hidden { codes.append("8") }
        if strikethrough { codes.append("9") }
        if let fgColor { codes.append(fgColor) }
        if let bgColor { codes.append(bgColor) }

        guard !codes.isEmpty else { return "" }
        return "\u{001B}[" + codes.joined(separator: ";") + "m"
    }

    func getLineEndReset() -> String {
        if underline {
            return "\u{001B}[24m"
        }
        return ""
    }

    private func reset() {
        bold = false
        dim = false
        italic = false
        underline = false
        blink = false
        inverse = false
        hidden = false
        strikethrough = false
        fgColor = nil
        bgColor = nil
    }
}

private extension String {
    func replacingMatches(of pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return self
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: replacement)
    }
}
