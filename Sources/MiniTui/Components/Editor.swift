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

/// Options for configuring the editor.
public struct EditorOptions: Sendable {
    public var autocompleteMaxVisible: Int?

    public init(autocompleteMaxVisible: Int? = nil) {
        self.autocompleteMaxVisible = autocompleteMaxVisible
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
    private var autocompleteMaxVisible: Int = 5
    private enum JumpMode {
        case forward
        case backward
    }
    private var jumpMode: JumpMode? = nil
    private var preferredVisualCol: Int? = nil

    private var pastes: [Int: String] = [:]
    private var pasteCounter = 0

    private var pasteBuffer = ""
    private var isInPaste = false

    private var history: [String] = []
    private var historyIndex = -1
    private var undoStack: [EditorState] = []
    private enum LastAction {
        case typingWord
        case kill
        case yank
    }
    private var lastAction: LastAction? = nil

    /// Called when the user submits with Enter.
    public var onSubmit: ((String) -> Void)?
    /// Called when the document text changes.
    public var onChange: ((String) -> Void)?
    /// When true, Enter does not submit.
    public var disableSubmit = false

    /// Create an editor with a theme.
    public init(theme: EditorTheme, options: EditorOptions = EditorOptions()) {
        self.theme = theme
        self.borderColor = theme.borderColor
        if let maxVisible = options.autocompleteMaxVisible {
            let clamped = max(3, min(20, maxVisible))
            self.autocompleteMaxVisible = clamped
        }
    }

    /// Return the max visible autocomplete items.
    public func getAutocompleteMaxVisible() -> Int {
        autocompleteMaxVisible
    }

    /// Set the max visible autocomplete items.
    public func setAutocompleteMaxVisible(_ maxVisible: Int) {
        let clamped = max(3, min(20, maxVisible))
        autocompleteMaxVisible = clamped
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

        if matchesKey(input, Key.ctrl("z")) {
            sendSuspendSignal()
            return
        }

        let kb = getKeybindings()

        if let activeJump = jumpMode {
            if kb.matches(input, TUIKeybinding.editorJumpForward) || kb.matches(input, TUIKeybinding.editorJumpBackward) {
                jumpMode = nil
                return
            }

            if let scalar = input.unicodeScalars.first, scalar.value >= 32 {
                jumpMode = nil
                jumpToChar(input, direction: activeJump)
                return
            }

            jumpMode = nil
        }

        if kb.matches(input, TUIKeybinding.inputCopy) {
            return
        }
        if kb.matches(input, TUIKeybinding.editorUndo) {
            undo()
            return
        }

        if isAutocompleting, let autocompleteList {
            if kb.matches(input, TUIKeybinding.selectCancel) {
                cancelAutocomplete()
                return
            }
            if kb.matches(input, TUIKeybinding.selectUp)
                || kb.matches(input, TUIKeybinding.selectDown)
                || kb.matches(input, TUIKeybinding.selectPageUp)
                || kb.matches(input, TUIKeybinding.selectPageDown) {
                autocompleteList.handleInput(input)
                return
            }

            if kb.matches(input, TUIKeybinding.inputTab) {
                if let selected = autocompleteList.getSelectedItem(), let provider = autocompleteProvider {
                    pushUndoSnapshot()
                    setLastAction(nil)
                    let result = provider.applyCompletion(
                        lines: state.lines,
                        cursorLine: state.cursorLine,
                        cursorCol: state.cursorCol,
                        item: selected,
                        prefix: autocompletePrefix
                    )
                    state.lines = result.lines
                    state.cursorLine = result.cursorLine
                    setCursorCol(result.cursorCol)
                    cancelAutocomplete()
                    onChange?(getText())
                }
                return
            }

            if kb.matches(input, TUIKeybinding.selectConfirm) {
                if let selected = autocompleteList.getSelectedItem(), let provider = autocompleteProvider {
                    pushUndoSnapshot()
                    setLastAction(nil)
                    let result = provider.applyCompletion(
                        lines: state.lines,
                        cursorLine: state.cursorLine,
                        cursorCol: state.cursorCol,
                        item: selected,
                        prefix: autocompletePrefix
                    )
                    state.lines = result.lines
                    state.cursorLine = result.cursorLine
                    setCursorCol(result.cursorCol)

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

        if kb.matches(input, TUIKeybinding.inputTab) && !isAutocompleting {
            handleTabCompletion()
            return
        }

        if kb.matches(input, TUIKeybinding.editorDeleteToLineEnd) {
            killToEndOfLine()
            return
        }
        if kb.matches(input, TUIKeybinding.editorDeleteToLineStart) {
            deleteToStartOfLine()
            return
        }
        if kb.matches(input, TUIKeybinding.editorDeleteWordBackward) {
            killWordBackwards()
            return
        }
        if kb.matches(input, TUIKeybinding.editorDeleteWordForward) {
            killWordForwards()
            return
        }
        if kb.matches(input, TUIKeybinding.editorDeleteCharBackward) || matchesKey(input, Key.shift("backspace")) {
            handleBackspace()
            return
        }
        if kb.matches(input, TUIKeybinding.editorDeleteCharForward) || matchesKey(input, Key.shift("delete")) {
            handleForwardDelete()
            return
        }

        if kb.matches(input, TUIKeybinding.editorYank) {
            yankKillBuffer()
            return
        }
        if kb.matches(input, TUIKeybinding.editorYankPop) {
            yankPop()
            return
        }

        if kb.matches(input, TUIKeybinding.editorCursorLineStart) {
            moveToLineStart()
            return
        }
        if kb.matches(input, TUIKeybinding.editorCursorLineEnd) {
            moveToLineEnd()
            return
        }
        if kb.matches(input, TUIKeybinding.editorCursorWordLeft) {
            setLastAction(nil)
            moveWordBackwards()
            return
        }
        if kb.matches(input, TUIKeybinding.editorCursorWordRight) {
            setLastAction(nil)
            moveWordForwards()
            return
        }

        if kb.matches(input, TUIKeybinding.inputNewLine)
            || (input.first?.unicodeScalars.first?.value == 10 && input.count > 1)
            || input == "\u{001B}\r"
            || input == "\u{001B}[13;2~"
            || (input.count > 1 && input.contains("\u{001B}") && input.contains("\r"))
            || (input == "\n" && input.count == 1)
        {
            if shouldSubmitOnBackslashEnter(input, kb: kb) {
                handleBackspace()
                submitValue()
                return
            }
            addNewLine()
            return
        }

        if kb.matches(input, TUIKeybinding.inputSubmit) {
            if disableSubmit {
                return
            }
            submitValue()
            return
        }

        if kb.matches(input, TUIKeybinding.editorCursorUp) {
            if isEditorEmpty() {
                navigateHistory(direction: -1)
            } else if historyIndex > -1 && isOnFirstVisualLine() {
                navigateHistory(direction: -1)
            } else if isOnFirstVisualLine() {
                moveToLineStart()
            } else {
                moveCursor(deltaLine: -1, deltaCol: 0)
            }
            return
        }
        if kb.matches(input, TUIKeybinding.editorCursorDown) {
            if historyIndex > -1 && isOnLastVisualLine() {
                navigateHistory(direction: 1)
            } else if isOnLastVisualLine() {
                moveToLineEnd()
            } else {
                moveCursor(deltaLine: 1, deltaCol: 0)
            }
            return
        }
        if kb.matches(input, TUIKeybinding.editorCursorRight) {
            moveCursor(deltaLine: 0, deltaCol: 1)
            return
        }
        if kb.matches(input, TUIKeybinding.editorCursorLeft) {
            moveCursor(deltaLine: 0, deltaCol: -1)
            return
        }

        if kb.matches(input, TUIKeybinding.editorPageUp) {
            pageScroll(direction: -1)
            return
        }
        if kb.matches(input, TUIKeybinding.editorPageDown) {
            pageScroll(direction: 1)
            return
        }

        if kb.matches(input, TUIKeybinding.editorJumpForward) {
            setLastAction(nil)
            jumpMode = .forward
            return
        }
        if kb.matches(input, TUIKeybinding.editorJumpBackward) {
            setLastAction(nil)
            jumpMode = .backward
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
        if getText() != text {
            pushUndoSnapshot()
        }
        setLastAction(nil)
        historyIndex = -1
        setTextInternal(text)
    }

    /// Insert text at the current cursor position.
    public func insertTextAtCursor(_ text: String) {
        guard !text.isEmpty else { return }
        pushUndoSnapshot()
        setLastAction(nil)
        historyIndex = -1
        insertTextAtCursorInternal(text)
    }

    private func insertTextAtCursorInternal(_ text: String) {
        guard !text.isEmpty else { return }
        historyIndex = -1
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let insertedLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        let beforeCursor = currentLine.prefixCharacters(state.cursorCol)
        let afterCursor = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))

        if insertedLines.count == 1 {
            state.lines[state.cursorLine] = beforeCursor + normalized + afterCursor
            setCursorCol(state.cursorCol + normalized.count)
        } else {
            var newLines: [String] = []
            if state.cursorLine > 0 {
                newLines.append(contentsOf: state.lines[0..<state.cursorLine])
            }
            newLines.append(beforeCursor + (insertedLines.first ?? ""))
            if insertedLines.count > 2 {
                newLines.append(contentsOf: insertedLines[1..<(insertedLines.count - 1)])
            }
            newLines.append((insertedLines.last ?? "") + afterCursor)
            if state.cursorLine + 1 < state.lines.count {
                newLines.append(contentsOf: state.lines[(state.cursorLine + 1)..<state.lines.count])
            }
            state.lines = newLines
            state.cursorLine += insertedLines.count - 1
            setCursorCol(insertedLines.last?.count ?? 0)
        }

        onChange?(getText())
    }

    /// Return true when the autocomplete list is visible.
    public func isShowingAutocomplete() -> Bool {
        return isAutocompleting
    }

    private func insertCharacter(_ text: String, skipUndoSnapshot: Bool = false) {
        historyIndex = -1
        if !skipUndoSnapshot {
            if let first = text.first, isWhitespaceChar(first) || lastAction != .typingWord {
                pushUndoSnapshot()
            }
            setLastAction(.typingWord)
        }
        let line = state.lines[safe: state.cursorLine] ?? ""
        let before = line.prefixCharacters(state.cursorCol)
        let after = line.substring(from: state.cursorCol, length: max(0, line.count - state.cursorCol))
        state.lines[state.cursorLine] = before + text + after
        setCursorCol(state.cursorCol + text.count)
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
        setLastAction(nil)
        pushUndoSnapshot()
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        let before = currentLine.prefixCharacters(state.cursorCol)
        let after = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
        state.lines[state.cursorLine] = before
        state.lines.insert(after, at: state.cursorLine + 1)
        state.cursorLine += 1
        setCursorCol(0)
        onChange?(getText())
    }

    private func shouldSubmitOnBackslashEnter(_ data: String, kb: TUIKeybindingsManager) -> Bool {
        if disableSubmit { return false }
        if !matchesKey(data, Key.enter) { return false }
        let submitKeys = kb.getKeys(TUIKeybinding.inputSubmit)
        let hasShiftEnter = submitKeys.contains(Key.shift("enter")) || submitKeys.contains(Key.shift("return"))
        if !hasShiftEnter { return false }

        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        return state.cursorCol > 0 && currentLine.character(at: state.cursorCol - 1) == "\\"
    }

    private func submitValue() {
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
        undoStack.removeAll()
        setLastAction(nil)
        preferredVisualCol = nil
        onChange?("")
        onSubmit?(result)
    }

    private func handleBackspace() {
        historyIndex = -1
        setLastAction(nil)

        if state.cursorCol > 0 {
            pushUndoSnapshot()
            let line = state.lines[safe: state.cursorLine] ?? ""
            let before = line.prefixCharacters(state.cursorCol - 1)
            let after = line.substring(from: state.cursorCol, length: max(0, line.count - state.cursorCol))
            state.lines[state.cursorLine] = before + after
            setCursorCol(state.cursorCol - 1)
        } else if state.cursorLine > 0 {
            pushUndoSnapshot()
            let currentLine = state.lines[state.cursorLine]
            let previousLine = state.lines[state.cursorLine - 1]
            state.lines[state.cursorLine - 1] = previousLine + currentLine
            state.lines.remove(at: state.cursorLine)
            state.cursorLine -= 1
            setCursorCol(previousLine.count)
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
        setLastAction(nil)
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol < currentLine.count {
            pushUndoSnapshot()
            let before = currentLine.prefixCharacters(state.cursorCol)
            let after = currentLine.substring(from: state.cursorCol + 1, length: max(0, currentLine.count - state.cursorCol - 1))
            state.lines[state.cursorLine] = before + after
        } else if state.cursorLine < state.lines.count - 1 {
            pushUndoSnapshot()
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

    private func setCursorCol(_ col: Int) {
        state.cursorCol = col
        preferredVisualCol = nil
    }

    private func moveToVisualLine(
        _ visualLines: [(logicalLine: Int, startCol: Int, length: Int)],
        currentVisualLine: Int,
        targetVisualLine: Int
    ) {
        let currentVL = visualLines[safe: currentVisualLine]
        let targetVL = visualLines[safe: targetVisualLine]

        guard let currentVL, let targetVL else { return }

        let currentVisualCol = state.cursorCol - currentVL.startCol
        let isLastSourceSegment = currentVisualLine == visualLines.count - 1
            || visualLines[safe: currentVisualLine + 1]?.logicalLine != currentVL.logicalLine
        let sourceMaxVisualCol = isLastSourceSegment ? currentVL.length : max(0, currentVL.length - 1)

        let isLastTargetSegment = targetVisualLine == visualLines.count - 1
            || visualLines[safe: targetVisualLine + 1]?.logicalLine != targetVL.logicalLine
        let targetMaxVisualCol = isLastTargetSegment ? targetVL.length : max(0, targetVL.length - 1)

        let moveToVisualCol = computeVerticalMoveColumn(
            currentVisualCol: currentVisualCol,
            sourceMaxVisualCol: sourceMaxVisualCol,
            targetMaxVisualCol: targetMaxVisualCol
        )

        state.cursorLine = targetVL.logicalLine
        let targetCol = targetVL.startCol + moveToVisualCol
        let logicalLine = state.lines[safe: targetVL.logicalLine] ?? ""
        state.cursorCol = min(targetCol, logicalLine.count)
    }

    private func computeVerticalMoveColumn(
        currentVisualCol: Int,
        sourceMaxVisualCol: Int,
        targetMaxVisualCol: Int
    ) -> Int {
        let hasPreferred = preferredVisualCol != nil
        let cursorInMiddle = currentVisualCol < sourceMaxVisualCol
        let targetTooShort = targetMaxVisualCol < currentVisualCol

        if !hasPreferred || cursorInMiddle {
            if targetTooShort {
                preferredVisualCol = currentVisualCol
                return targetMaxVisualCol
            }

            preferredVisualCol = nil
            return currentVisualCol
        }

        let preferred = preferredVisualCol ?? currentVisualCol
        let targetCantFitPreferred = targetMaxVisualCol < preferred
        if targetTooShort || targetCantFitPreferred {
            return targetMaxVisualCol
        }

        preferredVisualCol = nil
        return preferred
    }

    private func moveToLineStart() {
        setLastAction(nil)
        setCursorCol(0)
    }

    private func moveToLineEnd() {
        setLastAction(nil)
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        setCursorCol(currentLine.count)
    }

    private func deleteToStartOfLine() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol > 0 {
            pushUndoSnapshot()
            let deleted = currentLine.prefixCharacters(state.cursorCol)
            KillBuffer.shared.registerKill(deleted, append: true, prepend: true)
            state.lines[state.cursorLine] = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            setCursorCol(0)
            setLastAction(.kill)
        } else if state.cursorLine > 0 {
            pushUndoSnapshot()
            let previousLine = state.lines[state.cursorLine - 1]
            KillBuffer.shared.registerKill("\n", append: true, prepend: true)
            state.lines[state.cursorLine - 1] = previousLine + currentLine
            state.lines.remove(at: state.cursorLine)
            state.cursorLine -= 1
            setCursorCol(previousLine.count)
            setLastAction(.kill)
        }

        onChange?(getText())
    }

    private func deleteToEndOfLine() {
        historyIndex = -1
        setLastAction(nil)
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol < currentLine.count {
            pushUndoSnapshot()
            state.lines[state.cursorLine] = currentLine.prefixCharacters(state.cursorCol)
        } else if state.cursorLine < state.lines.count - 1 {
            pushUndoSnapshot()
            let nextLine = state.lines[state.cursorLine + 1]
            state.lines[state.cursorLine] = currentLine + nextLine
            state.lines.remove(at: state.cursorLine + 1)
        }

        onChange?(getText())
    }

    private func killToEndOfLine() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        var killText = ""

        if state.cursorCol < currentLine.count {
            pushUndoSnapshot()
            killText = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            state.lines[state.cursorLine] = currentLine.prefixCharacters(state.cursorCol)
        } else if state.cursorLine < state.lines.count - 1 {
            pushUndoSnapshot()
            killText = "\n"
            let nextLine = state.lines[state.cursorLine + 1]
            state.lines[state.cursorLine] = currentLine + nextLine
            state.lines.remove(at: state.cursorLine + 1)
        }

        guard !killText.isEmpty else { return }
        KillBuffer.shared.registerKill(killText, append: true)
        setLastAction(.kill)
        onChange?(getText())
    }

    private func yankKillBuffer() {
        let killBuffer = KillBuffer.shared.yank()
        guard !killBuffer.isEmpty else { return }
        pushUndoSnapshot()
        setLastAction(.yank)
        insertTextAtCursorInternal(killBuffer)
    }

    private func yankPop() {
        guard lastAction == .yank, KillBuffer.shared.hasMultipleEntries() else { return }
        pushUndoSnapshot()
        let previousText = KillBuffer.shared.yank()
        deleteYankedText(previousText)
        let nextText = KillBuffer.shared.rotate()
        insertTextAtCursorInternal(nextText)
        setLastAction(.yank)
    }

    private func deleteYankedText(_ text: String) {
        guard !text.isEmpty else { return }
        let yankLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if yankLines.count == 1 {
            let currentLine = state.lines[safe: state.cursorLine] ?? ""
            let deleteLen = min(text.count, state.cursorCol)
            let before = currentLine.prefixCharacters(max(0, state.cursorCol - deleteLen))
            let after = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            state.lines[state.cursorLine] = before + after
            setCursorCol(max(0, state.cursorCol - deleteLen))
        } else {
            let startLine = state.cursorLine - (yankLines.count - 1)
            guard startLine >= 0 else { return }
            let startLineText = state.lines[safe: startLine] ?? ""
            let firstLine = yankLines.first ?? ""
            let startCol = max(0, startLineText.count - firstLine.count)
            let currentLine = state.lines[safe: state.cursorLine] ?? ""
            let afterCursor = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            let beforeYank = startLineText.prefixCharacters(startCol)
            state.lines.replaceSubrange(startLine...state.cursorLine, with: [beforeYank + afterCursor])
            state.cursorLine = startLine
            setCursorCol(startCol)
        }

        onChange?(getText())
    }

    private func setLastAction(_ action: LastAction?) {
        lastAction = action
        if action != .kill {
            KillBuffer.shared.breakChain()
        }
    }

    private func pushUndoSnapshot() {
        undoStack.append(state)
    }

    private func undo() {
        historyIndex = -1
        guard let snapshot = undoStack.popLast() else { return }
        state = snapshot
        setLastAction(nil)
        preferredVisualCol = nil
        onChange?(getText())
    }

    private func deleteWordBackwards() {
        historyIndex = -1
        setLastAction(nil)
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol == 0 {
            if state.cursorLine > 0 {
                pushUndoSnapshot()
                let previousLine = state.lines[state.cursorLine - 1]
                state.lines[state.cursorLine - 1] = previousLine + currentLine
                state.lines.remove(at: state.cursorLine)
                state.cursorLine -= 1
                setCursorCol(previousLine.count)
            }
        } else {
            pushUndoSnapshot()
            let oldCursor = state.cursorCol
            moveWordBackwards()
            let deleteFrom = state.cursorCol
            setCursorCol(oldCursor)
            let before = currentLine.prefixCharacters(deleteFrom)
            let after = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            state.lines[state.cursorLine] = before + after
            setCursorCol(deleteFrom)
        }

        onChange?(getText())
    }

    private func killWordBackwards() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol == 0 {
            if state.cursorLine > 0 {
                pushUndoSnapshot()
                let previousLine = state.lines[state.cursorLine - 1]
                state.lines[state.cursorLine - 1] = previousLine + currentLine
                state.lines.remove(at: state.cursorLine)
                state.cursorLine -= 1
                setCursorCol(previousLine.count)
                KillBuffer.shared.registerKill("\n", append: true, prepend: true)
                setLastAction(.kill)
            }
        } else {
            pushUndoSnapshot()
            let oldCursor = state.cursorCol
            moveWordBackwards()
            let deleteFrom = state.cursorCol
            setCursorCol(oldCursor)
            let before = currentLine.prefixCharacters(deleteFrom)
            let after = currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol))
            let deleted = currentLine.substring(from: deleteFrom, length: max(0, state.cursorCol - deleteFrom))
            state.lines[state.cursorLine] = before + after
            setCursorCol(deleteFrom)
            KillBuffer.shared.registerKill(deleted, append: true, prepend: true)
            setLastAction(.kill)
        }

        onChange?(getText())
    }

    private func moveWordBackwards() {
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        if state.cursorCol == 0 {
            if state.cursorLine > 0 {
                state.cursorLine -= 1
                let prevLine = state.lines[state.cursorLine]
                setCursorCol(prevLine.count)
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

        setCursorCol(newCol)
    }

    private func moveWordForwards() {
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        if state.cursorCol >= currentLine.count {
            if state.cursorLine < state.lines.count - 1 {
                state.cursorLine += 1
                setCursorCol(0)
            }
            return
        }

        let textAfterCursor = Array(currentLine.substring(from: state.cursorCol, length: max(0, currentLine.count - state.cursorCol)))
        var index = 0
        var newCol = state.cursorCol

        while index < textAfterCursor.count, isWhitespaceChar(textAfterCursor[index]) {
            newCol += 1
            index += 1
        }

        if index < textAfterCursor.count {
            let first = textAfterCursor[index]
            if isPunctuationChar(first) {
                while index < textAfterCursor.count, isPunctuationChar(textAfterCursor[index]) {
                    newCol += 1
                    index += 1
                }
            } else {
                while index < textAfterCursor.count,
                      !isWhitespaceChar(textAfterCursor[index]),
                      !isPunctuationChar(textAfterCursor[index]) {
                    newCol += 1
                    index += 1
                }
            }
        }
        setCursorCol(newCol)
    }

    private func killWordForwards() {
        historyIndex = -1
        let currentLine = state.lines[safe: state.cursorLine] ?? ""

        if state.cursorCol >= currentLine.count {
            if state.cursorLine < state.lines.count - 1 {
                pushUndoSnapshot()
                let nextLine = state.lines[state.cursorLine + 1]
                state.lines[state.cursorLine] = currentLine + nextLine
                state.lines.remove(at: state.cursorLine + 1)
                KillBuffer.shared.registerKill("\n", append: true)
                setLastAction(.kill)
                onChange?(getText())
            }
            return
        }

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
        guard deleteTo > state.cursorCol else { return }
        pushUndoSnapshot()
        let before = currentLine.prefixCharacters(state.cursorCol)
        let after = currentLine.substring(from: deleteTo, length: max(0, currentLine.count - deleteTo))
        let deleted = currentLine.substring(from: state.cursorCol, length: max(0, deleteTo - state.cursorCol))
        state.lines[state.cursorLine] = before + after
        KillBuffer.shared.registerKill(deleted, append: true)
        setLastAction(.kill)
        onChange?(getText())
    }

    private func moveCursor(deltaLine: Int, deltaCol: Int) {
        setLastAction(nil)
        let visualLines = buildVisualLineMap(width: lastWidth)
        let currentVisualLine = findCurrentVisualLine(visualLines)

        if deltaLine != 0 {
            let targetVisualLine = currentVisualLine + deltaLine
            if targetVisualLine >= 0 && targetVisualLine < visualLines.count {
                moveToVisualLine(visualLines, currentVisualLine: currentVisualLine, targetVisualLine: targetVisualLine)
            }
        }

        if deltaCol != 0 {
            let currentLine = state.lines[safe: state.cursorLine] ?? ""
            if deltaCol > 0 {
                if state.cursorCol < currentLine.count {
                    setCursorCol(state.cursorCol + 1)
                } else if state.cursorLine < state.lines.count - 1 {
                    state.cursorLine += 1
                    setCursorCol(0)
                }
                else {
                    let currentVL = visualLines[safe: currentVisualLine]
                    if let currentVL {
                        preferredVisualCol = state.cursorCol - currentVL.startCol
                    }
                }
            } else {
                if state.cursorCol > 0 {
                    setCursorCol(state.cursorCol - 1)
                } else if state.cursorLine > 0 {
                    state.cursorLine -= 1
                    let prevLine = state.lines[state.cursorLine]
                    setCursorCol(prevLine.count)
                }
            }
        }
    }

    private func pageScroll(direction: Int) {
        setLastAction(nil)
        let visualLines = buildVisualLineMap(width: lastWidth)
        guard !visualLines.isEmpty else { return }
        let currentVisualLine = findCurrentVisualLine(visualLines)
        let pageSize = 5
        let targetVisualLine = max(0, min(visualLines.count - 1, currentVisualLine + direction * pageSize))
        moveToVisualLine(visualLines, currentVisualLine: currentVisualLine, targetVisualLine: targetVisualLine)
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
        historyIndex = -1
        setLastAction(nil)
        pushUndoSnapshot()
        let normalizedText = pastedText.replacingOccurrences(of: "\t", with: "    ")
        let pastedLines = normalizedText.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        if pastedLines.count > 10 {
            pasteCounter += 1
            let pasteId = pasteCounter
            pastes[pasteId] = normalizedText
            let marker = "[paste #\(pasteId) +\(pastedLines.count) lines]"
            for char in marker {
                insertCharacter(String(char), skipUndoSnapshot: true)
            }
            return
        }

        if pastedLines.count == 1 {
            for char in pastedLines[0] {
                insertCharacter(String(char), skipUndoSnapshot: true)
            }
            return
        }
        insertTextAtCursorInternal(normalizedText)
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
        setLastAction(nil)
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
        setCursorCol(state.lines[safe: state.cursorLine]?.count ?? 0)
        onChange?(getText())
    }

    private func isAtStartOfMessage() -> Bool {
        let currentLine = state.lines[safe: state.cursorLine] ?? ""
        let beforeCursor = currentLine.prefixCharacters(state.cursorCol)
        let trimmed = beforeCursor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "/"
    }

    private func jumpToChar(_ char: String, direction: JumpMode) {
        setLastAction(nil)
        guard let target = char.first else { return }
        let isForward = direction == .forward
        let end = isForward ? state.lines.count : -1
        let step = isForward ? 1 : -1

        var lineIndex = state.cursorLine
        while lineIndex != end {
            let line = state.lines[safe: lineIndex] ?? ""
            let isCurrentLine = lineIndex == state.cursorLine
            let startIndex: Int?
            if isCurrentLine {
                startIndex = isForward ? state.cursorCol + 1 : state.cursorCol - 1
            } else {
                startIndex = nil
            }

            let matchIndex: Int?
            if isForward {
                let start = max(0, startIndex ?? 0)
                matchIndex = indexOfChar(line, target, from: start)
            } else {
                let start = startIndex ?? (line.count - 1)
                matchIndex = lastIndexOfChar(line, target, from: start)
            }

            if let matchIndex {
                state.cursorLine = lineIndex
                setCursorCol(matchIndex)
                return
            }

            lineIndex += step
        }
    }

    private func indexOfChar(_ line: String, _ target: Character, from start: Int) -> Int? {
        guard start >= 0 else { return nil }
        var idx = start
        while idx < line.count {
            if line.character(at: idx) == target {
                return idx
            }
            idx += 1
        }
        return nil
    }

    private func lastIndexOfChar(_ line: String, _ target: Character, from start: Int) -> Int? {
        guard !line.isEmpty else { return nil }
        var idx = min(start, line.count - 1)
        while idx >= 0 {
            if line.character(at: idx) == target {
                return idx
            }
            idx -= 1
        }
        return nil
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
            autocompleteList = SelectList(items: suggestions.items, maxVisible: autocompleteMaxVisible, theme: theme.selectList)
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
                autocompleteList = SelectList(items: suggestions.items, maxVisible: autocompleteMaxVisible, theme: theme.selectList)
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
            autocompleteList = SelectList(items: suggestions.items, maxVisible: autocompleteMaxVisible, theme: theme.selectList)
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
