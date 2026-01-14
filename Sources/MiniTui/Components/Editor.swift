import Foundation

/// Theme configuration for the editor component.
public struct EditorTheme: Sendable {
    /// Formatter for the border characters.
    public let borderColor: @Sendable (String) -> String
    /// Theme for the autocomplete list.
    public let selectList: SelectListTheme

    /// Create an editor theme.
    public init(borderColor: @escaping @Sendable (String) -> String, selectList: SelectListTheme) {
        self.borderColor = borderColor
        self.selectList = selectList
    }
}

private struct TextChunk {
    let text: String
    let startIndex: Int
    let endIndex: Int
}

private func trimTrailingWhitespace(_ text: String) -> String {
    var trimmed = text
    while let last = trimmed.last, isWhitespaceChar(last) {
        trimmed.removeLast()
    }
    return trimmed
}

/// Split a line into word-wrapped chunks with original index information.
private func wordWrapLine(_ line: String, maxWidth: Int) -> [TextChunk] {
    if line.isEmpty || maxWidth <= 0 {
        return [TextChunk(text: "", startIndex: 0, endIndex: 0)]
    }

    if visibleWidth(line) <= maxWidth {
        return [TextChunk(text: line, startIndex: 0, endIndex: line.count)]
    }

    struct Token {
        let text: String
        let startIndex: Int
        let endIndex: Int
        let isWhitespace: Bool
    }

    var tokens: [Token] = []
    var currentToken = ""
    var tokenStart = 0
    var inWhitespace = false
    var charIndex = 0

    for grapheme in line {
        let graphemeIsWhitespace = isWhitespaceChar(grapheme)
        if currentToken.isEmpty {
            inWhitespace = graphemeIsWhitespace
            tokenStart = charIndex
        } else if graphemeIsWhitespace != inWhitespace {
            tokens.append(Token(text: currentToken, startIndex: tokenStart, endIndex: charIndex, isWhitespace: inWhitespace))
            currentToken = ""
            tokenStart = charIndex
            inWhitespace = graphemeIsWhitespace
        }

        currentToken.append(grapheme)
        charIndex += 1
    }

    if !currentToken.isEmpty {
        tokens.append(Token(text: currentToken, startIndex: tokenStart, endIndex: charIndex, isWhitespace: inWhitespace))
    }

    var chunks: [TextChunk] = []
    var currentChunk = ""
    var currentWidth = 0
    var chunkStartIndex = 0
    var atLineStart = true

    for token in tokens {
        let tokenWidth = visibleWidth(token.text)

        if atLineStart && token.isWhitespace {
            chunkStartIndex = token.endIndex
            continue
        }
        atLineStart = false

        if tokenWidth > maxWidth {
            if !currentChunk.isEmpty {
                chunks.append(TextChunk(text: currentChunk, startIndex: chunkStartIndex, endIndex: token.startIndex))
                currentChunk = ""
                currentWidth = 0
                chunkStartIndex = token.startIndex
            }

            var tokenChunk = ""
            var tokenChunkWidth = 0
            var tokenChunkStart = token.startIndex
            var tokenCharIndex = token.startIndex

            for grapheme in token.text {
                let graphemeWidth = visibleWidth(String(grapheme))
                if tokenChunkWidth + graphemeWidth > maxWidth && !tokenChunk.isEmpty {
                    chunks.append(TextChunk(text: tokenChunk, startIndex: tokenChunkStart, endIndex: tokenCharIndex))
                    tokenChunk = String(grapheme)
                    tokenChunkWidth = graphemeWidth
                    tokenChunkStart = tokenCharIndex
                } else {
                    tokenChunk.append(grapheme)
                    tokenChunkWidth += graphemeWidth
                }
                tokenCharIndex += 1
            }

            if !tokenChunk.isEmpty {
                currentChunk = tokenChunk
                currentWidth = tokenChunkWidth
                chunkStartIndex = tokenChunkStart
            }
            continue
        }

        if currentWidth + tokenWidth > maxWidth {
            let trimmedChunk = trimTrailingWhitespace(currentChunk)
            if !trimmedChunk.isEmpty || chunks.isEmpty {
                chunks.append(TextChunk(text: trimmedChunk, startIndex: chunkStartIndex, endIndex: chunkStartIndex + currentChunk.count))
            }

            atLineStart = true
            if token.isWhitespace {
                currentChunk = ""
                currentWidth = 0
                chunkStartIndex = token.endIndex
            } else {
                currentChunk = token.text
                currentWidth = tokenWidth
                chunkStartIndex = token.startIndex
                atLineStart = false
            }
        } else {
            currentChunk += token.text
            currentWidth += tokenWidth
        }
    }

    if !currentChunk.isEmpty {
        chunks.append(TextChunk(text: currentChunk, startIndex: chunkStartIndex, endIndex: line.count))
    }

    return chunks.isEmpty ? [TextChunk(text: "", startIndex: 0, endIndex: 0)] : chunks
}

private struct EditorState {
    var lines: [String]
    var cursorLine: Int
    var cursorCol: Int
}

private struct LayoutLine {
    var text: String
    var hasCursor: Bool
    var cursorPos: Int?
}

/// Multi-line editor with history and autocomplete support.
public final class Editor: SystemCursorAware, KillBufferAware, EditorComponent {
    private var state = EditorState(lines: [""], cursorLine: 0, cursorCol: 0)
    private let theme: EditorTheme
    private var lastWidth: Int = 80

    /// Formatter used to color the editor border.
    public var borderColor: @Sendable (String) -> String
    /// When true, do not render a custom cursor and rely on the system cursor.
    public var usesSystemCursor = false

    private var autocompleteProvider: AutocompleteProvider?
    private var autocompleteList: SelectList?
    private var isAutocompleting = false
    private var autocompletePrefix = ""

    private var pastes: [Int: String] = [:]
    private var pasteCounter = 0

    private var pasteBuffer = ""
    private var isInPaste = false
    private var pendingShiftEnter = false

    private var history: [String] = []
    private var historyIndex = -1

    /// Called when the user submits with Enter.
    public var onSubmit: ((String) -> Void)?
    /// Called when the document text changes.
    public var onChange: ((String) -> Void)?
    /// When true, Enter does not submit.
    public var disableSubmit = false

    /// Create an editor with a theme.
    public init(theme: EditorTheme) {
        self.theme = theme
        self.borderColor = theme.borderColor
    }

    /// Provide an autocomplete provider for slash commands and file suggestions.
    public func setAutocompleteProvider(_ provider: AutocompleteProvider) {
        autocompleteProvider = provider
    }

    /// Add a string to the history, ignoring empty or duplicate entries.
    public func addToHistory(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if history.first == trimmed { return }
        history.insert(trimmed, at: 0)
        if history.count > 100 {
            history.removeLast()
        }
    }

    /// Render the editor content and optional autocomplete list.
    public func render(width: Int) -> [String] {
        lastWidth = width
        let horizontal = borderColor("─")
        let layoutLines = layoutText(contentWidth: width)
        var result: [String] = []

        result.append(String(repeating: horizontal, count: width))

        for layoutLine in layoutLines {
            var displayText = layoutLine.text
            var lineVisibleWidth = visibleWidth(displayText)

            if layoutLine.hasCursor, let cursorPos = layoutLine.cursorPos {
                let before = displayText.prefixCharacters(cursorPos)
                let after = displayText.substring(from: cursorPos, length: max(0, displayText.count - cursorPos))

                if usesSystemCursor {
                    displayText = before + systemCursorMarker + after
                } else if !after.isEmpty {
                    let first = after.prefixCharacters(1)
                    let rest = after.substring(from: 1, length: max(0, after.count - 1))
                    let cursor = "\u{001B}[7m\(first)\u{001B}[0m"
                    displayText = before + cursor + rest
                } else if lineVisibleWidth < width {
                    let cursor = "\u{001B}[7m \u{001B}[0m"
                    displayText = before + cursor
                    lineVisibleWidth += 1
                } else {
                    let beforeChars = Array(before)
                    if let last = beforeChars.last {
                        let cursor = "\u{001B}[7m\(String(last))\u{001B}[0m"
                        let prefix = beforeChars.dropLast().map(String.init).joined()
                        displayText = prefix + cursor
                    }
                }
            }

            let padding = String(repeating: " ", count: max(0, width - lineVisibleWidth))
            result.append(displayText + padding)
        }

        result.append(String(repeating: horizontal, count: width))

        if isAutocompleting, let autocompleteList {
            result.append(contentsOf: autocompleteList.render(width: width))
        }

        return result
    }

    /// Handle raw terminal input when focused.
    public func handleInput(_ data: String) {
        var input = data

        if input.contains("\u{001B}[200~") {
            isInPaste = true
            pasteBuffer = ""
            input = input.replacingOccurrences(of: "\u{001B}[200~", with: "")
        }

        if isInPaste {
            pasteBuffer += input
            if let endRange = pasteBuffer.range(of: "\u{001B}[201~") {
                let pasteContent = String(pasteBuffer[..<endRange.lowerBound])
                if !pasteContent.isEmpty {
                    handlePaste(pasteContent)
                }
                isInPaste = false
                let remaining = String(pasteBuffer[endRange.upperBound...])
                pasteBuffer = ""
                if !remaining.isEmpty {
                    handleInput(remaining)
                }
            }
            return
        }

        if pendingShiftEnter {
            if input == "\r" {
                pendingShiftEnter = false
                addNewLine()
                return
            }
            pendingShiftEnter = false
            insertCharacter("\\")
        }

        if input == "\\" {
            pendingShiftEnter = true
            return
        }

        if matchesKey(input, Key.ctrl("z")) {
            sendSuspendSignal()
            return
        }

        let kb = getEditorKeybindings()

        if kb.matches(input, .copy) {
            return
        }

        if isAutocompleting, let autocompleteList {
            if kb.matches(input, .selectCancel) {
                cancelAutocomplete()
                return
            }
            if kb.matches(input, .selectUp) || kb.matches(input, .selectDown) {
                autocompleteList.handleInput(input)
                return
            }

            if kb.matches(input, .tab) {
                if let selected = autocompleteList.getSelectedItem(), let provider = autocompleteProvider {
                    let result = provider.applyCompletion(
                        lines: state.lines,
                        cursorLine: state.cursorLine,
                        cursorCol: state.cursorCol,
                        item: selected,
                        prefix: autocompletePrefix
                    )
                    state.lines = result.lines
                    state.cursorLine = result.cursorLine
                    state.cursorCol = result.cursorCol
                    cancelAutocomplete()
                    onChange?(getText())
                }
                return
            }

            if kb.matches(input, .selectConfirm) {
                if let selected = autocompleteList.getSelectedItem(), let provider = autocompleteProvider {
                    let result = provider.applyCompletion(
                        lines: state.lines,
                        cursorLine: state.cursorLine,
                        cursorCol: state.cursorCol,
                        item: selected,
                        prefix: autocompletePrefix
                    )
                    state.lines = result.lines
                    state.cursorLine = result.cursorLine
                    state.cursorCol = result.cursorCol

                    if autocompletePrefix.hasPrefix("/") {
                        cancelAutocomplete()
                    } else {
                        cancelAutocomplete()
                        onChange?(getText())
                        return
                    }
                }
            }
        }

        if kb.matches(input, .tab) && !isAutocompleting {
            handleTabCompletion()
            return
        }

        if kb.matches(input, .deleteToLineEnd) {
            killToEndOfLine()
            return
        }
        if kb.matches(input, .deleteToLineStart) {
            deleteToStartOfLine()
            return
        }
        if kb.matches(input, .deleteWordBackward) {
            killWordBackwards()
            return
        }
        if kb.matches(input, .deleteCharBackward) || matchesKey(input, Key.shift("backspace")) {
            handleBackspace()
            return
        }
        if kb.matches(input, .deleteCharForward) || matchesKey(input, Key.shift("delete")) {
            handleForwardDelete()
            return
        }

        if matchesKey(input, Key.alt("d")) {
            killWordForwards()
            return
        }
        if matchesKey(input, Key.ctrl("y")) {
            yankKillBuffer()
            return
        }

        if kb.matches(input, .cursorLineStart) {
            moveToLineStart()
            return
        }
        if kb.matches(input, .cursorLineEnd) {
            moveToLineEnd()
            return
        }
        if kb.matches(input, .cursorWordLeft) {
            moveWordBackwards()
            return
        }
        if kb.matches(input, .cursorWordRight) {
            moveWordForwards()
            return
        }

        if kb.matches(input, .newLine)
            || (input.first?.unicodeScalars.first?.value == 10 && input.count > 1)
            || input == "\u{001B}\r"
            || input == "\u{001B}[13;2~"
            || (input.count > 1 && input.contains("\u{001B}") && input.contains("\r"))
            || (input == "\n" && input.count == 1)
            || input == "\\\r" {
            addNewLine()
            return
        }

        if kb.matches(input, .submit) {
            if disableSubmit {
                return
            }

            var result = state.lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            for (pasteId, pasteContent) in pastes {
                let pattern = "\\[paste #\(pasteId)( (\\+\\d+ lines|\\d+ chars))?\\]"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: pasteContent)
                }
            }

            state = EditorState(lines: [""], cursorLine: 0, cursorCol: 0)
            pastes.removeAll()
            pasteCounter = 0
            historyIndex = -1
            onChange?("")
            onSubmit?(result)
            return
        }

        if kb.matches(input, .cursorUp) {
            if isEditorEmpty() {
                navigateHistory(direction: -1)
            } else if historyIndex > -1 && isOnFirstVisualLine() {
                navigateHistory(direction: -1)
            } else {
                moveCursor(deltaLine: -1, deltaCol: 0)
            }
            return
        }
        if kb.matches(input, .cursorDown) {
            if historyIndex > -1 && isOnLastVisualLine() {
                navigateHistory(direction: 1)
            } else {
                moveCursor(deltaLine: 1, deltaCol: 0)
            }
            return
        }
        if kb.matches(input, .cursorRight) {
            moveCursor(deltaLine: 0, deltaCol: 1)
            return
        }
        if kb.matches(input, .cursorLeft) {
            moveCursor(deltaLine: 0, deltaCol: -1)
            return
        }

        if matchesKey(input, Key.shift("space")) {
            insertCharacter(" ")
            return
        }
        if input.first?.unicodeScalars.first?.value ?? 0 >= 32 {
            insertCharacter(input)
        }
    }

    /// Return the full document text.
    public func getText() -> String {
        return state.lines.joined(separator: "\n")
    }

    /// Return the text with paste markers expanded to their actual content.
    public func getExpandedText() -> String {
        var result = state.lines.joined(separator: "\n")
        for (pasteId, pasteContent) in pastes {
            let pattern = "\\[paste #\(pasteId)( (\\+\\d+ lines|\\d+ chars))?\\]"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(result.startIndex..<result.endIndex, in: result)
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: pasteContent)
            }
        }
        return result
    }

    /// Return a copy of the document lines.
    public func getLines() -> [String] {
        return Array(state.lines)
    }

    /// Return the current cursor position.
    public func getCursor() -> (line: Int, col: Int) {
        return (line: state.cursorLine, col: state.cursorCol)
    }

    /// Replace the document text and reset history navigation.
    public func setText(_ text: String) {
        historyIndex = -1
        setTextInternal(text)
    }

    /// Insert text at the current cursor position.
    public func insertTextAtCursor(_ text: String) {
        for char in text {
            insertCharacter(String(char))
        }
    }

    /// Return true when the autocomplete list is visible.
    public func isShowingAutocomplete() -> Bool {
        return isAutocompleting
    }

    private func insertCharacter(_ text: String) {
        historyIndex = -1
        let line = state.lines[safe: state.cursorLine] ?? ""
        let before = line.prefixCharacters(state.cursorCol)
        let after = line.substring(from: state.cursorCol, length: max(0, line.count - state.cursorCol))
        state.lines[state.cursorLine] = before + text + after
        state.cursorCol += text.count
        onChange?(getText())

        if !isAutocompleting {
            if text == "/" && isAtStartOfMessage() {
                tryTriggerAutocomplete(explicitTab: false)
            } else if text == "@" {
                let currentLine = state.lines[safe: state.cursorLine] ?? ""
                let textBeforeCursor = currentLine.prefixCharacters(max(0, state.cursorCol))
                if textBeforeCursor.count == 1 || textBeforeCursor.suffixCharacters(2).first == " " {
                    tryTriggerAutocomplete(explicitTab: false)
                }
            } else if text.range(of: "^[a-zA-Z0-9._-]$", options: .regularExpression) != nil {
                let currentLine = state.lines[safe: state.cursorLine] ?? ""
                let textBeforeCursor = currentLine.prefixCharacters(max(0, state.cursorCol))
                if textBeforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
                    tryTriggerAutocomplete(explicitTab: false)
                }
            }
        } else {
            updateAutocomplete()
        }
    }

    private func addNewLine() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        let before = currentLine.prefixCharacters(state.cursorCol)
        let after = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
        state.lines[state.cursorLine] = before
        state.lines.insert(after, at: state.cursorLine + 1)
        state.cursorLine += 1
        state.cursorCol = 0
        onChange?(getText())
    }

    private func handleBackspace() {
        historyIndex = -1

        if state.cursorCol > 0 {
            let line = state.lines[safe: state.cursorLine] ?? ""
            let before = line.prefixCharacters(state.cursorCol - 1)
            let after = line.substring(from: state.cursorCol, length: max(0, line.count - state.cursorCol))
            state.lines[state.cursorLine] = before + after
            state.cursorCol -= 1
        } else if state.cursorLine > 0 {
            let currentLine = state.lines[state.cursorLine]
            let previousLine = state.lines[state.cursorLine - 1]
            state.lines[state.cursorLine - 1] = previousLine + currentLine
            state.lines.remove(at: state.cursorLine)
            state.cursorLine -= 1
            state.cursorCol = previousLine.count
        }

        onChange?(getText())

        if isAutocompleting {
            updateAutocomplete()
        } else {
            let currentLine = state.lines[safe: state.cursorLine] ?? ""
            let textBeforeCursor = currentLine.prefixCharacters(state.cursorCol)
            if textBeforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
                tryTriggerAutocomplete(explicitTab: false)
            } else if textBeforeCursor.range(of: "(?:^|\\s)@[\\S]*$", options: .regularExpression) != nil {
                tryTriggerAutocomplete(explicitTab: false)
            }
        }
    }

    private func handleForwardDelete() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol < currentLine.count {
            let before = currentLine.prefixCharacters(state.cursorCol)
            let after = currentLine.substring(from: state.cursorCol + 1, length: max(0, currentLine.count - state.cursorCol - 1))
            state.lines[state.cursorLine] = before + after
        } else if state.cursorLine < state.lines.count - 1 {
            let nextLine = state.lines[state.cursorLine + 1]
            state.lines[state.cursorLine] = currentLine + nextLine
            state.lines.remove(at: state.cursorLine + 1)
        }

        onChange?(getText())

        if isAutocompleting {
            updateAutocomplete()
        } else {
            let textBeforeCursor = currentLine.prefixCharacters(state.cursorCol)
            if textBeforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") {
                tryTriggerAutocomplete(explicitTab: false)
            } else if textBeforeCursor.range(of: "(?:^|\\s)@[\\S]*$", options: .regularExpression) != nil {
                tryTriggerAutocomplete(explicitTab: false)
            }
        }
    }

    private func moveToLineStart() {
        state.cursorCol = 0
    }

    private func moveToLineEnd() {
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        state.cursorCol = currentLine.count
    }

    private func deleteToStartOfLine() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol > 0 {
            state.lines[state.cursorLine] = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            state.cursorCol = 0
        } else if state.cursorLine > 0 {
            let previousLine = state.lines[state.cursorLine - 1]
            state.lines[state.cursorLine - 1] = previousLine + currentLine
            state.lines.remove(at: state.cursorLine)
            state.cursorLine -= 1
            state.cursorCol = previousLine.count
        }

        onChange?(getText())
    }

    private func deleteToEndOfLine() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol < currentLine.count {
            state.lines[state.cursorLine] = currentLine.prefixCharacters(state.cursorCol)
        } else if state.cursorLine < state.lines.count - 1 {
            let nextLine = state.lines[state.cursorLine + 1]
            state.lines[state.cursorLine] = currentLine + nextLine
            state.lines.remove(at: state.cursorLine + 1)
        }

        onChange?(getText())
    }

    private func killToEndOfLine() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        let killText: String

        if state.cursorCol < currentLine.count {
            killText = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            state.lines[state.cursorLine] = currentLine.prefixCharacters(state.cursorCol)
        } else if state.cursorLine < state.lines.count - 1 {
            killText = "\n"
            let nextLine = state.lines[state.cursorLine + 1]
            state.lines[state.cursorLine] = currentLine + nextLine
            state.lines.remove(at: state.cursorLine + 1)
        } else {
            killText = ""
        }

        KillBuffer.shared.registerKill(killText, append: true)
        onChange?(getText())
    }

    private func yankKillBuffer() {
        let killBuffer = KillBuffer.shared.yank()
        guard !killBuffer.isEmpty else { return }

        if killBuffer.contains("\n") {
            handlePaste(killBuffer)
            return
        }

        for char in killBuffer {
            insertCharacter(String(char))
        }
    }

    private func deleteWordBackwards() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol == 0 {
            if state.cursorLine > 0 {
                let previousLine = state.lines[state.cursorLine - 1]
                state.lines[state.cursorLine - 1] = previousLine + currentLine
                state.lines.remove(at: state.cursorLine)
                state.cursorLine -= 1
                state.cursorCol = previousLine.count
            }
        } else {
            let oldCursor = state.cursorCol
            moveWordBackwards()
            let deleteFrom = state.cursorCol
            state.cursorCol = oldCursor
            let before = currentLine.prefixCharacters(deleteFrom)
            let after = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            state.lines[state.cursorLine] = before + after
            state.cursorCol = deleteFrom
        }

        onChange?(getText())
    }

    private func killWordBackwards() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol == 0 {
            if state.cursorLine > 0 {
                let previousLine = state.lines[state.cursorLine - 1]
                state.lines[state.cursorLine - 1] = previousLine + currentLine
                state.lines.remove(at: state.cursorLine)
                state.cursorLine -= 1
                state.cursorCol = previousLine.count
                KillBuffer.shared.registerKill("\n", append: true, prepend: true)
            }
        } else {
            let oldCursor = state.cursorCol
            moveWordBackwards()
            let deleteFrom = state.cursorCol
            state.cursorCol = oldCursor
            let before = currentLine.prefixCharacters(deleteFrom)
            let after = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            let deleted = currentLine.substring(from: deleteFrom, length: max(0, state.cursorCol - deleteFrom))
            state.lines[state.cursorLine] = before + after
            state.cursorCol = deleteFrom
            KillBuffer.shared.registerKill(deleted, append: true, prepend: true)
        }

        onChange?(getText())
    }

    private func moveWordBackwards() {
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        if state.cursorCol == 0 {
            if state.cursorLine > 0 {
                state.cursorLine -= 1
                let prevLine = state.lines[state.cursorLine]
                state.cursorCol = prevLine.count
            }
            return
        }

        var textBeforeCursor = Array(currentLine.prefixCharacters(state.cursorCol))
        var newCol = state.cursorCol

        while let last = textBeforeCursor.last, isWhitespaceChar(last) {
            textBeforeCursor.removeLast()
            newCol -= 1
        }

        if let last = textBeforeCursor.last {
            if isPunctuationChar(last) {
                while let tail = textBeforeCursor.last, isPunctuationChar(tail) {
                    textBeforeCursor.removeLast()
                    newCol -= 1
                }
            } else {
                while let tail = textBeforeCursor.last, !isWhitespaceChar(tail), !isPunctuationChar(tail) {
                    textBeforeCursor.removeLast()
                    newCol -= 1
                }
            }
        }

        state.cursorCol = newCol
    }

    private func moveWordForwards() {
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        if state.cursorCol >= currentLine.count {
            if state.cursorLine < state.lines.count - 1 {
                state.cursorLine += 1
                state.cursorCol = 0
            }
            return
        }

        let textAfterCursor = Array(currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol)))
        var index = 0

        while index < textAfterCursor.count, isWhitespaceChar(textAfterCursor[index]) {
            state.cursorCol += 1
            index += 1
        }

        if index < textAfterCursor.count {
            let first = textAfterCursor[index]
            if isPunctuationChar(first) {
                while index < textAfterCursor.count, isPunctuationChar(textAfterCursor[index]) {
                    state.cursorCol += 1
                    index += 1
                }
            } else {
                while index < textAfterCursor.count,
                      !isWhitespaceChar(textAfterCursor[index]),
                      !isPunctuationChar(textAfterCursor[index]) {
                    state.cursorCol += 1
                    index += 1
                }
            }
        }
    }

    private func killWordForwards() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        guard state.cursorCol < currentLine.count else { return }

        let textAfterCursor = Array(currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol)))
        var index = 0

        while index < textAfterCursor.count, isWhitespaceChar(textAfterCursor[index]) {
            index += 1
        }

        if index < textAfterCursor.count {
            let first = textAfterCursor[index]
            if isPunctuationChar(first) {
                while index < textAfterCursor.count, isPunctuationChar(textAfterCursor[index]) {
                    index += 1
                }
            } else {
                while index < textAfterCursor.count,
                      !isWhitespaceChar(textAfterCursor[index]),
                      !isPunctuationChar(textAfterCursor[index]) {
                    index += 1
                }
            }
        }

        let deleteTo = state.cursorCol + index
        let before = currentLine.prefixCharacters(state.cursorCol)
        let after = currentLine.substring(from: deleteTo, length: max(0, currentLine.count - deleteTo))
        let deleted = currentLine.substring(from: state.cursorCol, length: max(0, deleteTo - state.cursorCol))
        state.lines[state.cursorLine] = before + after
        KillBuffer.shared.registerKill(deleted, append: true)
        onChange?(getText())
    }

    private func moveCursor(deltaLine: Int, deltaCol: Int) {
        let width = lastWidth

        if deltaLine != 0 {
            let visualLines = buildVisualLineMap(width: width)
            let currentVisualLine = findCurrentVisualLine(visualLines)
            let currentVL = visualLines[safe: currentVisualLine]
            let visualCol = currentVL.map { state.cursorCol - $0.startCol } ?? 0
            let targetVisualLine = currentVisualLine + deltaLine
            if targetVisualLine >= 0 && targetVisualLine < visualLines.count {
                let targetVL = visualLines[targetVisualLine]
                state.cursorLine = targetVL.logicalLine
                let targetCol = targetVL.startCol + min(visualCol, targetVL.length)
                let logicalLine = state.lines[safe: targetVL.logicalLine] ?? ""
                state.cursorCol = min(targetCol, logicalLine.count)
            }
        }

        if deltaCol != 0 {
            let currentLine = state.lines[safe: state.cursorLine] ?? ""
            if deltaCol > 0 {
                if state.cursorCol < currentLine.count {
                    state.cursorCol += 1
                } else if state.cursorLine < state.lines.count - 1 {
                    state.cursorLine += 1
                    state.cursorCol = 0
                }
            } else {
                if state.cursorCol > 0 {
                    state.cursorCol -= 1
                } else if state.cursorLine > 0 {
                    state.cursorLine -= 1
                    let prevLine = state.lines[state.cursorLine]
                    state.cursorCol = prevLine.count
                }
            }
        }
    }

    private func buildVisualLineMap(width: Int) -> [(logicalLine: Int, startCol: Int, length: Int)] {
        var visualLines: [(logicalLine: Int, startCol: Int, length: Int)] = []

        for (index, line) in state.lines.enumerated() {
            if line.isEmpty {
                visualLines.append((logicalLine: index, startCol: 0, length: 0))
                continue
            }

            if visibleWidth(line) <= width {
                visualLines.append((logicalLine: index, startCol: 0, length: line.count))
                continue
            }

            let chunks = wordWrapLine(line, maxWidth: width)
            for chunk in chunks {
                visualLines.append((logicalLine: index, startCol: chunk.startIndex, length: chunk.endIndex - chunk.startIndex))
            }
        }

        return visualLines
    }

    private func findCurrentVisualLine(_ visualLines: [(logicalLine: Int, startCol: Int, length: Int)]) -> Int {
        for (index, visual) in visualLines.enumerated() {
            if visual.logicalLine == state.cursorLine {
                let colInSegment = state.cursorCol - visual.startCol
                let isLastSegmentOfLine = index == visualLines.count - 1 || visualLines[index + 1].logicalLine != visual.logicalLine
                if colInSegment >= 0 && (colInSegment < visual.length || (isLastSegmentOfLine && colInSegment <= visual.length)) {
                    return index
                }
            }
        }
        return max(visualLines.count - 1, 0)
    }

    private func layoutText(contentWidth: Int) -> [LayoutLine] {
        var layoutLines: [LayoutLine] = []

        if state.lines.isEmpty || (state.lines.count == 1 && state.lines[0].isEmpty) {
            layoutLines.append(LayoutLine(text: "", hasCursor: true, cursorPos: 0))
            return layoutLines
        }

        for i in 0..<state.lines.count {
            let line = state.lines[i]
            let isCurrentLine = i == state.cursorLine
            let lineVisibleWidth = visibleWidth(line)

            if lineVisibleWidth <= contentWidth {
                if isCurrentLine {
                    layoutLines.append(LayoutLine(text: line, hasCursor: true, cursorPos: state.cursorCol))
                } else {
                    layoutLines.append(LayoutLine(text: line, hasCursor: false, cursorPos: nil))
                }
            } else {
                let chunks = wordWrapLine(line, maxWidth: contentWidth)
                for (chunkIndex, chunk) in chunks.enumerated() {
                    let cursorPos = state.cursorCol
                    let isLastChunk = chunkIndex == chunks.count - 1
                    var hasCursorInChunk = false
                    var adjustedCursorPos = 0

                    if isCurrentLine {
                        if isLastChunk {
                            hasCursorInChunk = cursorPos >= chunk.startIndex
                            adjustedCursorPos = cursorPos - chunk.startIndex
                        } else {
                            hasCursorInChunk = cursorPos >= chunk.startIndex && cursorPos < chunk.endIndex
                            if hasCursorInChunk {
                                adjustedCursorPos = cursorPos - chunk.startIndex
                                if adjustedCursorPos > chunk.text.count {
                                    adjustedCursorPos = chunk.text.count
                                }
                            }
                        }
                    }

                    if hasCursorInChunk {
                        layoutLines.append(LayoutLine(text: chunk.text, hasCursor: true, cursorPos: adjustedCursorPos))
                    } else {
                        layoutLines.append(LayoutLine(text: chunk.text, hasCursor: false, cursorPos: nil))
                    }
                }
            }
        }

        return layoutLines
    }

    private func handlePaste(_ pastedText: String) {
        let pastedLines = pastedText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if pastedLines.count > 10 {
            pasteCounter += 1
            let pasteId = pasteCounter
            pastes[pasteId] = pastedText
            let marker = "[paste #\(pasteId) +\(pastedLines.count) lines]"
            for char in marker {
                insertCharacter(String(char))
            }
            return
        }

        if pastedLines.count == 1 {
            for char in pastedLines[0] {
                insertCharacter(String(char))
            }
            return
        }

        let currentLine = state.lines[state.cursorLine]
        let beforeCursor = currentLine.prefixCharacters(state.cursorCol)
        let afterCursor = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))

        var newLines: [String] = []
        for i in 0..<state.cursorLine {
            newLines.append(state.lines[i])
        }
        newLines.append(beforeCursor + (pastedLines.first ?? ""))
        if pastedLines.count > 2 {
            newLines.append(contentsOf: pastedLines[1..<pastedLines.count - 1])
        }
        newLines.append((pastedLines.last ?? "") + afterCursor)
        for i in (state.cursorLine + 1)..<state.lines.count {
            newLines.append(state.lines[i])
        }

        state.lines = newLines
        state.cursorLine += pastedLines.count - 1
        state.cursorCol = pastedLines.last?.count ?? 0
        onChange?(getText())
    }

    private func isEditorEmpty() -> Bool {
        return state.lines.count == 1 && state.lines.first == ""
    }

    private func isOnFirstVisualLine() -> Bool {
        let visualLines = buildVisualLineMap(width: lastWidth)
        let currentVisualLine = findCurrentVisualLine(visualLines)
        return currentVisualLine == 0
    }

    private func isOnLastVisualLine() -> Bool {
        let visualLines = buildVisualLineMap(width: lastWidth)
        let currentVisualLine = findCurrentVisualLine(visualLines)
        return currentVisualLine == visualLines.count - 1
    }

    private func navigateHistory(direction: Int) {
        guard !history.isEmpty else { return }
        let newIndex = historyIndex - direction
        if newIndex < -1 || newIndex >= history.count {
            return
        }
        historyIndex = newIndex
        if historyIndex == -1 {
            setTextInternal("")
        } else {
            setTextInternal(history[historyIndex])
        }
    }

    private func setTextInternal(_ text: String) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        state.lines = lines.isEmpty ? [""] : lines
        state.cursorLine = max(state.lines.count - 1, 0)
        state.cursorCol = state.lines[safe: state.cursorLine]?.count ?? 0
        onChange?(getText())
    }

    private func isAtStartOfMessage() -> Bool {
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        let beforeCursor = currentLine.prefixCharacters(state.cursorCol)
        let trimmed = beforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "/"
    }

    private func tryTriggerAutocomplete(explicitTab: Bool) {
        guard let provider = autocompleteProvider else { return }

        if explicitTab, let combined = provider as? CombinedAutocompleteProvider {
            if !combined.shouldTriggerFileCompletion(lines: state.lines, cursorLine: state.cursorLine, cursorCol: state.cursorCol) {
                return
            }
        }

        if let suggestions = provider.getSuggestions(lines: state.lines, cursorLine: state.cursorLine, cursorCol: state.cursorCol), !suggestions.items.isEmpty {
            autocompletePrefix = suggestions.prefix
            autocompleteList = SelectList(items: suggestions.items, maxVisible: 5, theme: theme.selectList)
            isAutocompleting = true
        } else {
            cancelAutocomplete()
        }
    }

    private func handleTabCompletion() {
        guard autocompleteProvider != nil else { return }

        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        let beforeCursor = currentLine.prefixCharacters(state.cursorCol)

        if beforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") && !beforeCursor.trimmingCharacters(in: .whitespaces).contains(" ") {
            handleSlashCommandCompletion()
        } else {
            forceFileAutocomplete()
        }
    }

    private func handleSlashCommandCompletion() {
        tryTriggerAutocomplete(explicitTab: true)
    }

    private func forceFileAutocomplete() {
        guard let provider = autocompleteProvider else { return }

        if let combined = provider as? CombinedAutocompleteProvider {
            if let suggestions = combined.getForceFileSuggestions(lines: state.lines, cursorLine: state.cursorLine, cursorCol: state.cursorCol), !suggestions.items.isEmpty {
                autocompletePrefix = suggestions.prefix
                autocompleteList = SelectList(items: suggestions.items, maxVisible: 5, theme: theme.selectList)
                isAutocompleting = true
                return
            }
        }

        tryTriggerAutocomplete(explicitTab: true)
    }

    private func cancelAutocomplete() {
        isAutocompleting = false
        autocompleteList = nil
        autocompletePrefix = ""
    }

    private func updateAutocomplete() {
        guard isAutocompleting, let provider = autocompleteProvider else { return }
        if let suggestions = provider.getSuggestions(lines: state.lines, cursorLine: state.cursorLine, cursorCol: state.cursorCol), !suggestions.items.isEmpty {
            autocompletePrefix = suggestions.prefix
            autocompleteList = SelectList(items: suggestions.items, maxVisible: 5, theme: theme.selectList)
        } else {
            cancelAutocomplete()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
