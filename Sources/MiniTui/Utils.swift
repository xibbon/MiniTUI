import Foundation

private let ansiEscape = "\u{001B}"

private let visibleWidthCache = VisibleWidthCache(maxSize: 512)

/// Expand visible tabs to 3 spaces (the fixed width used by layout) so terminal tab stops
/// cannot wrap a logical line. Tabs inside ANSI escape sequences are left untouched.
public func normalizeTerminalOutput(_ str: String) -> String {
    guard str.contains("\t") else { return str }

    var result = ""
    var index = 0
    let length = str.count
    while index < length {
        if let ansi = extractAnsiCode(str, at: index) {
            result += ansi.code
            index += ansi.length
            continue
        }

        let character = str[str.index(at: index)]
        result += character == "\t" ? "   " : String(character)
        index += 1
    }
    return result
}

/// SAFETY: cache dictionaries and eviction order are accessed only while
/// holding `lock`.
private final class VisibleWidthCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    private var order: [String] = []
    private let maxSize: Int

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    func get(_ key: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ key: String, value: Int) {
        lock.lock()
        if values[key] != nil {
            values[key] = value
            lock.unlock()
            return
        }
        values[key] = value
        order.append(key)
        if order.count > maxSize, let oldest = order.first {
            order.removeFirst()
            values.removeValue(forKey: oldest)
        }
        lock.unlock()
    }
}

/// Return the display width of a string, ignoring ANSI escape codes.
public func visibleWidth(_ str: String) -> Int {
    guard !str.isEmpty else { return 0 }

    var asciiCount = 0
    for scalar in str.unicodeScalars {
        let value = scalar.value
        if value < 0x20 || value > 0x7E {
            asciiCount = -1
            break
        }
        asciiCount += 1
    }
    if asciiCount >= 0 {
        return asciiCount
    }

    if let cached = visibleWidthCache.get(str) {
        return cached
    }

    var clean = str.replacingOccurrences(of: "\t", with: "   ")
    if clean.contains(ansiEscape) {
        clean = stripAnsiCodes(clean)
    }

    var width = 0
    for character in clean {
        width += graphemeWidth(character)
    }

    visibleWidthCache.set(str, value: width)
    return width
}

func stripAnsiCodes(_ text: String) -> String {
    stripTerminalSequences(text)
}

/// Remove CSI, OSC, and APC control sequences while preserving visible text.
public func stripTerminalSequences(_ str: String) -> String {
    guard str.contains(ansiEscape) else { return str }

    var result = ""
    var index = 0
    while index < str.count {
        if let ansi = extractAnsiCode(str, at: index) {
            index += ansi.length
            continue
        }
        result.append(str[str.index(at: index)])
        index += 1
    }
    return result
}

private func graphemeWidth(_ grapheme: Character) -> Int {
    let scalars = Array(grapheme.unicodeScalars)

    if grapheme == "\t" {
        return 3
    }

    if scalars.allSatisfy(isTerminalSpacingMark) {
        return scalars.count
    }

    if scalars.allSatisfy({ isZeroWidthScalar($0) }) {
        return 0
    }

    if isEmoji(grapheme) {
        return 2
    }

    guard let baseIndex = scalars.firstIndex(where: { !isZeroWidthScalar($0) }) else {
        return 0
    }

    let baseScalars = Array(scalars[baseIndex...])
    let baseScalar = baseScalars[0]
    if isRegionalIndicator(baseScalar) {
        return 2
    }

    var width = eastAsianWidth(baseScalar)
    var followsMark = false

    for scalar in baseScalars.dropFirst() {
        if isTerminalSpacingMark(scalar) {
            width += 1
            followsMark = false
        } else if isMark(scalar) {
            followsMark = true
        } else if !isNonPrintingScalar(scalar) {
            if followsMark || (0xFF00...0xFFEF).contains(scalar.value) {
                width += eastAsianWidth(scalar)
            } else if scalar.value == 0x0E33 || scalar.value == 0x0EB3 {
                width += 1
            }
            followsMark = false
        }
    }

    return width
}

private func isZeroWidthScalar(_ scalar: Unicode.Scalar) -> Bool {
    isNonPrintingScalar(scalar)
}

private func isNonPrintingScalar(_ scalar: Unicode.Scalar) -> Bool {
    if scalar.properties.isDefaultIgnorableCodePoint { return true }

    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark, .format, .control, .surrogate:
        return true
    default:
        return false
    }
}

private func isMark(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .nonspacingMark, .spacingMark, .enclosingMark:
        return true
    default:
        return false
    }
}

private func isTerminalSpacingMark(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x1734, 0x302E, 0x302F:
        return false
    case 0x065F, 0x0F7F, 0x102B, 0x102C, 0x1031, 0x1033...0x1035, 0x1038, 0x103A...0x103E:
        return true
    default:
        return scalar.properties.generalCategory == .spacingMark
    }
}

private func isRegionalIndicator(_ scalar: Unicode.Scalar) -> Bool {
    return scalar.value >= 0x1F1E6 && scalar.value <= 0x1F1FF
}

private func isEmoji(_ grapheme: Character) -> Bool {
    let scalars = Array(grapheme.unicodeScalars)

    // Regional indicator pairs (flag emoji like 🇺🇸) are always width 2.
    if scalars.count == 2 && isRegionalIndicator(scalars[0]) && isRegionalIndicator(scalars[1]) {
        return true
    }
    // A lone regional indicator is treated as width 2 for consistency.
    if scalars.count == 1 && isRegionalIndicator(scalars[0]) {
        return true
    }

    if scalars.contains(where: { $0.value == 0xFE0F }) {
        return scalars.contains(where: { $0.properties.isEmoji })
    }

    return scalars.first(where: { !$0.properties.isDefaultIgnorableCodePoint })?.properties.isEmojiPresentation == true
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

    let normalizedLineEndings = text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
    let inputLines = normalizedLineEndings.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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

    let trimmed = wrapped.map { trimTrailingSpaces($0) }
    return trimmed.isEmpty ? [""] : trimmed
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
/// Optionally pad the result with spaces to reach exactly maxWidth.
public func truncateToWidth(_ text: String, maxWidth: Int, ellipsis: String = "...", pad: Bool = false) -> String {
    if maxWidth <= 0 {
        return ""
    }

    if text.isEmpty {
        return pad ? String(repeating: " ", count: maxWidth) : ""
    }

    let ellipsisWidth = visibleWidth(ellipsis)
    if ellipsisWidth >= maxWidth {
        let textWidth = visibleWidth(text)
        if textWidth <= maxWidth {
            return pad ? text + String(repeating: " ", count: maxWidth - textWidth) : text
        }

        let clippedEllipsis = truncateFragmentToWidth(ellipsis, maxWidth: maxWidth)
        if clippedEllipsis.width == 0 {
            return pad ? String(repeating: " ", count: maxWidth) : ""
        }
        return finalizeTruncatedResult(prefix: "", prefixWidth: 0, ellipsis: clippedEllipsis.text, ellipsisWidth: clippedEllipsis.width, maxWidth: maxWidth, pad: pad)
    }

    if isPrintableAscii(text) {
        if text.count <= maxWidth {
            return pad ? text + String(repeating: " ", count: maxWidth - text.count) : text
        }
        let targetWidth = maxWidth - ellipsisWidth
        return finalizeTruncatedResult(
            prefix: text.prefixCharacters(targetWidth),
            prefixWidth: targetWidth,
            ellipsis: ellipsis,
            ellipsisWidth: ellipsisWidth,
            maxWidth: maxWidth,
            pad: pad
        )
    }

    let targetWidth = maxWidth - ellipsisWidth
    var result = ""
    var pendingAnsi = ""
    var visibleSoFar = 0
    var keptWidth = 0
    var keepContiguousPrefix = true
    var overflowed = false
    var index = 0
    let length = text.count
    let hasAnsi = text.contains(ansiEscape)
    let hasTabs = text.contains("\t")

    if !hasAnsi && !hasTabs {
        for character in text {
            let width = graphemeWidth(character)
            if keepContiguousPrefix, keptWidth + width <= targetWidth {
                result.append(character)
                keptWidth += width
            } else {
                keepContiguousPrefix = false
            }
            visibleSoFar += width
            if visibleSoFar > maxWidth {
                overflowed = true
                break
            }
            index += 1
        }
    } else {
        while index < length {
            if let ansiResult = extractAnsiCode(text, at: index) {
                pendingAnsi += ansiResult.code
                index += ansiResult.length
                continue
            }

            let character = text[text.index(at: index)]
            let width = character == "\t" ? 3 : graphemeWidth(character)

            if keepContiguousPrefix, keptWidth + width <= targetWidth {
                if !pendingAnsi.isEmpty {
                    result += pendingAnsi
                    pendingAnsi = ""
                }
                result.append(character)
                keptWidth += width
            } else {
                keepContiguousPrefix = false
                pendingAnsi = ""
            }

            visibleSoFar += width
            if visibleSoFar > maxWidth {
                overflowed = true
                break
            }
            index += 1
        }
    }

    if !overflowed, index >= length {
        return pad ? text + String(repeating: " ", count: max(0, maxWidth - visibleSoFar)) : text
    }

    return finalizeTruncatedResult(
        prefix: result,
        prefixWidth: keptWidth,
        ellipsis: ellipsis,
        ellipsisWidth: ellipsisWidth,
        maxWidth: maxWidth,
        pad: pad
    )
}

private func isPrintableAscii(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        if scalar.value < 0x20 || scalar.value > 0x7E {
            return false
        }
    }
    return true
}

private func truncateFragmentToWidth(_ text: String, maxWidth: Int) -> (text: String, width: Int) {
    if maxWidth <= 0 || text.isEmpty {
        return ("", 0)
    }

    if isPrintableAscii(text) {
        let clipped = text.prefixCharacters(maxWidth)
        return (clipped, clipped.count)
    }

    var result = ""
    var width = 0
    var pendingAnsi = ""
    var index = 0
    let length = text.count

    while index < length {
        if let ansiResult = extractAnsiCode(text, at: index) {
            pendingAnsi += ansiResult.code
            index += ansiResult.length
            continue
        }

        let character = text[text.index(at: index)]
        let characterWidth = character == "\t" ? 3 : graphemeWidth(character)
        if width + characterWidth > maxWidth {
            break
        }
        if !pendingAnsi.isEmpty {
            result += pendingAnsi
            pendingAnsi = ""
        }
        result.append(character)
        width += characterWidth
        index += 1
    }

    return (result, width)
}

private func finalizeTruncatedResult(prefix: String, prefixWidth: Int, ellipsis: String, ellipsisWidth: Int, maxWidth: Int, pad: Bool) -> String {
    let reset = "\u{001B}[0m"
    let hyperlinkClose = getActiveOsc8Close(prefix)
    let visibleWidth = prefixWidth + ellipsisWidth
    let result: String
    if ellipsis.isEmpty {
        result = prefix + hyperlinkClose + reset
    } else {
        result = prefix + hyperlinkClose + reset + ellipsis + reset
    }

    if pad {
        return result + String(repeating: " ", count: max(0, maxWidth - visibleWidth))
    }
    return result
}

private enum Osc8Terminator {
    case bell
    case stringTerminator
}

private func getActiveOsc8Close(_ prefix: String) -> String {
    guard prefix.contains("\u{001B}]8;") else { return "" }

    var activeTerminator: Osc8Terminator?
    var index = 0
    while index < prefix.count {
        guard let ansi = extractAnsiCode(prefix, at: index) else {
            index += 1
            continue
        }

        if ansi.code.hasPrefix("\u{001B}]8;") {
            let terminatorLength = ansi.code.hasSuffix("\u{0007}") ? 1 : 2
            let bodyLength = ansi.code.count - 4 - terminatorLength
            let body = ansi.code.substring(from: 4, length: max(0, bodyLength))
            if let separator = body.firstIndex(of: ";") {
                let url = body[body.index(after: separator)...]
                activeTerminator = url.isEmpty ? nil : (terminatorLength == 1 ? .bell : .stringTerminator)
            }
        }
        index += ansi.length
    }

    switch activeTerminator {
    case .bell: return osc8HyperlinkCloseBell
    case .stringTerminator: return osc8HyperlinkCloseStringTerminator
    default: return ""
    }
}

/// The half-open terminal-cell range occupied by a grapheme.
public struct GraphemeCellRange: Equatable, Sendable {
    public let start: Int
    public let end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// Return the terminal-cell range occupied by the grapheme at a visible column.
public func getGraphemeCellRange(line: String, column: Int) -> GraphemeCellRange? {
    guard column >= 0 else { return nil }

    var currentColumn = 0
    var index = 0
    while index < line.count {
        if let ansi = extractAnsiCode(line, at: index) {
            index += ansi.length
            continue
        }

        var textEnd = index
        while textEnd < line.count, extractAnsiCode(line, at: textEnd) == nil {
            textEnd += 1
        }

        let text = line.substring(from: index, length: textEnd - index)
        for character in text {
            let width = graphemeWidth(character)
            if width > 0, column >= currentColumn, column < currentColumn + width {
                return GraphemeCellRange(start: currentColumn, end: currentColumn + width)
            }
            currentColumn += width
        }
        index = textEnd
    }
    return nil
}

/// Extract a range of visible columns from a line. Handles ANSI codes and wide chars.
public func sliceByColumn(_ line: String, startCol: Int, length: Int, strict: Bool = false) -> String {
    return sliceWithWidth(line, startCol: startCol, length: length, strict: strict).text
}

/// Like sliceByColumn but also returns the actual visible width of the result.
public func sliceWithWidth(
    _ line: String,
    startCol: Int,
    length: Int,
    strict: Bool = false
) -> (text: String, width: Int) {
    if length <= 0 {
        return ("", 0)
    }

    let endCol = startCol + length
    var result = ""
    var resultWidth = 0
    var currentCol = 0
    var i = 0
    var pendingAnsi = ""
    let lineLength = line.count

    while i < lineLength {
        if let ansi = extractAnsiCode(line, at: i) {
            if currentCol >= startCol && currentCol < endCol {
                result += ansi.code
            } else if currentCol < startCol {
                pendingAnsi += ansi.code
            }
            i += ansi.length
            continue
        }

        var textEnd = i
        while textEnd < lineLength && extractAnsiCode(line, at: textEnd) == nil {
            textEnd += 1
        }

        let textPortion = line.substring(from: i, length: textEnd - i)
        for grapheme in textPortion {
            let w = visibleWidth(String(grapheme))
            let inRange = currentCol >= startCol && currentCol < endCol
            let fits = !strict || currentCol + w <= endCol
            if inRange && fits {
                if !pendingAnsi.isEmpty {
                    result += pendingAnsi
                    pendingAnsi = ""
                }
                result.append(grapheme)
                resultWidth += w
            }
            currentCol += w
            if currentCol >= endCol {
                break
            }
        }
        i = textEnd
        if currentCol >= endCol {
            break
        }
    }

    return (result, resultWidth)
}

/// Extract "before" and "after" segments from a line in a single pass.
@MainActor
public func extractSegments(
    _ line: String,
    beforeEnd: Int,
    afterStart: Int,
    afterLen: Int,
    strictAfter: Bool = false
) -> (before: String, beforeWidth: Int, after: String, afterWidth: Int) {
    var before = ""
    var beforeWidth = 0
    var after = ""
    var afterWidth = 0
    var currentCol = 0
    var i = 0
    var pendingAnsiBefore = ""
    var afterStarted = false
    let afterEnd = afterStart + afterLen
    let lineLength = line.count

    let pooledStyleTracker = AnsiCodeTracker()
    pooledStyleTracker.clear()

    while i < lineLength {
        if let ansi = extractAnsiCode(line, at: i) {
            pooledStyleTracker.process(ansi.code)
            if currentCol < beforeEnd {
                pendingAnsiBefore += ansi.code
            } else if currentCol >= afterStart && currentCol < afterEnd && afterStarted {
                after += ansi.code
            }
            i += ansi.length
            continue
        }

        var textEnd = i
        while textEnd < lineLength && extractAnsiCode(line, at: textEnd) == nil {
            textEnd += 1
        }

        let textPortion = line.substring(from: i, length: textEnd - i)
        for grapheme in textPortion {
            let w = visibleWidth(String(grapheme))

            if currentCol < beforeEnd {
                if !pendingAnsiBefore.isEmpty {
                    before += pendingAnsiBefore
                    pendingAnsiBefore = ""
                }
                before.append(grapheme)
                beforeWidth += w
            } else if currentCol >= afterStart && currentCol < afterEnd {
                let fits = !strictAfter || currentCol + w <= afterEnd
                if fits {
                    if !afterStarted {
                        after += pooledStyleTracker.getActiveCodes()
                        afterStarted = true
                    }
                    after.append(grapheme)
                    afterWidth += w
                }
            }

            currentCol += w
            let done = afterLen <= 0 ? currentCol >= beforeEnd : currentCol >= afterEnd
            if done { break }
        }

        i = textEnd
        let done = afterLen <= 0 ? currentCol >= beforeEnd : currentCol >= afterEnd
        if done { break }
    }

    return (before, beforeWidth, after, afterWidth)
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

/// Extract one ANSI, OSC, or APC escape sequence at a character offset.
public func extractAnsiCode(_ text: String, at index: Int) -> (code: String, length: Int)? {
    guard index >= 0, index < text.count else {
        return nil
    }

    let startIndex = text.index(at: index)
    guard startIndex < text.endIndex, text[startIndex] == "\u{001B}" else {
        return nil
    }

    let nextOffset = index + 1
    guard nextOffset < text.count else {
        return nil
    }

    let nextIndex = text.index(at: nextOffset)
    let next = text[nextIndex]

    if next == "[" {
        var j = nextOffset + 1
        while j < text.count {
            let ch = text[text.index(at: j)]
            if ch == "m" || ch == "G" || ch == "K" || ch == "H" || ch == "J" {
                let endOffset = j + 1
                let endIndex = text.index(at: endOffset)
                return (String(text[startIndex..<endIndex]), endOffset - index)
            }
            j += 1
        }
        return nil
    }

    if next == "]" || next == "_" {
        var j = nextOffset + 1
        while j < text.count {
            let ch = text[text.index(at: j)]
            if ch == "\u{0007}" {
                let endOffset = j + 1
                let endIndex = text.index(at: endOffset)
                return (String(text[startIndex..<endIndex]), endOffset - index)
            }
            if ch == "\u{001B}" {
                let escNext = j + 1
                if escNext < text.count, text[text.index(at: escNext)] == "\\" {
                    let endOffset = escNext + 1
                    let endIndex = text.index(at: endOffset)
                    return (String(text[startIndex..<endIndex]), endOffset - index)
                }
            }
            j += 1
        }
        return nil
    }

    return nil
}

private func updateTrackerFromText(_ text: String, tracker: AnsiCodeTracker) {
    var index = 0
    let length = text.count
    while index < length {
        if let ansiResult = extractAnsiCode(text, at: index) {
            tracker.process(ansiResult.code)
            index += ansiResult.length
        } else {
            index += 1
        }
    }
}

private func splitIntoTokensWithAnsi(_ text: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    var pendingAnsi = ""
    var inWhitespace = false

    var index = 0
    let length = text.count
    while index < length {
        if let ansiResult = extractAnsiCode(text, at: index) {
            pendingAnsi += ansiResult.code
            index += ansiResult.length
            continue
        }

        let char = text[text.index(at: index)]
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
        index += 1
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

    func clear() {
        reset()
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
