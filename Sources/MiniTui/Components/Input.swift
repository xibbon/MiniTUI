import Foundation

/// Single-line text input with cursor and editing shortcuts.
public final class Input: SystemCursorAware, KillBufferAware {
    private var value: String = ""
    private var cursor: Int = 0
    /// Called when the user submits with Enter.
    public var onSubmit: ((String) -> Void)?
    /// Called when the user cancels with Escape or Ctrl+C.
    public var onEscape: (() -> Void)?
    /// Called when the user presses Ctrl-D on an empty input.
    public var onEnd: (() -> Void)?
    /// When true, do not render a custom cursor and rely on the system cursor.
    public var usesSystemCursor = false

    private var pasteBuffer: String = ""
    private var isInPaste = false

    /// Create an empty input.
    public init() {}

    /// Return the current input value.
    public func getValue() -> String {
        return value
    }

    /// Set the current input value.
    public func setValue(_ value: String) {
        self.value = value
        cursor = min(cursor, value.count)
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
                handlePaste(pasteContent)
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

        if matchesKey(input, Key.ctrl("d")) {
            if value.isEmpty {
                onEnd?()
                return
            }
        }

        let kb = getEditorKeybindings()

        if kb.matches(input, .selectCancel) {
            onEscape?()
            return
        }

        if kb.matches(input, .submit) || input == "\n" {
            onSubmit?(value)
            return
        }

        if kb.matches(input, .deleteCharBackward) || matchesKey(input, Key.shift("backspace")) {
            if cursor > 0 {
                let before = value.prefixCharacters(cursor - 1)
                let after = value.substring(from: cursor, length: value.count - cursor)
                value = before + after
                cursor -= 1
            }
            return
        }

        if kb.matches(input, .deleteCharForward) || matchesKey(input, Key.shift("delete")) {
            if cursor < value.count {
                let before = value.prefixCharacters(cursor)
                let after = value.substring(from: cursor + 1, length: value.count - cursor - 1)
                value = before + after
            }
            return
        }

        if kb.matches(input, .deleteWordBackward) {
            killWordBackwards()
            return
        }

        if kb.matches(input, .deleteToLineStart) {
            value = value.substring(from: cursor, length: value.count - cursor)
            cursor = 0
            return
        }

        if kb.matches(input, .deleteToLineEnd) {
            killToEndOfLine()
            return
        }

        if kb.matches(input, .yank) {
            yankKillBuffer()
            return
        }

        if kb.matches(input, .deleteWordForward) {
            killWordForwards()
            return
        }

        if kb.matches(input, .cursorLeft) {
            if cursor > 0 {
                cursor -= 1
            }
            return
        }

        if kb.matches(input, .cursorRight) {
            if cursor < value.count {
                cursor += 1
            }
            return
        }

        if kb.matches(input, .cursorLineStart) {
            cursor = 0
            return
        }

        if kb.matches(input, .cursorLineEnd) {
            cursor = value.count
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

        let hasControlChars = input.unicodeScalars.contains { scalar in
            let value = scalar.value
            return value < 32 || value == 0x7F || (0x80...0x9F).contains(value)
        }
        if !hasControlChars {
            let before = value.prefixCharacters(cursor)
            let after = value.substring(from: cursor, length: value.count - cursor)
            value = before + input + after
            cursor += input.count
        }
    }

    /// Render the input line with a prompt and cursor.
    public func render(width: Int) -> [String] {
        let prompt = "> "
        let availableWidth = width - prompt.count
        if availableWidth <= 0 {
            return [prompt]
        }

        var visibleText = ""
        var cursorDisplay = cursor

        if value.count < availableWidth {
            visibleText = value
        } else {
            let scrollWidth = cursor == value.count ? max(0, availableWidth - 1) : availableWidth
            let halfWidth = scrollWidth / 2

            if cursor < halfWidth {
                visibleText = value.prefixCharacters(scrollWidth)
                cursorDisplay = cursor
            } else if cursor > value.count - halfWidth {
                visibleText = value.suffixCharacters(scrollWidth)
                cursorDisplay = scrollWidth - (value.count - cursor)
            } else {
                let start = cursor - halfWidth
                visibleText = value.substring(from: start, length: scrollWidth)
                cursorDisplay = halfWidth
            }
        }

        let beforeCursor = visibleText.prefixCharacters(cursorDisplay)
        let afterCursor = visibleText.substring(from: cursorDisplay, length: max(0, visibleText.count - cursorDisplay))
        let textWithCursor: String

        if usesSystemCursor {
            textWithCursor = beforeCursor + systemCursorMarker + afterCursor
        } else {
            let atCursor = afterCursor.isEmpty ? " " : afterCursor.prefixCharacters(1)
            let remaining = afterCursor.isEmpty ? "" : afterCursor.substring(from: 1, length: max(0, afterCursor.count - 1))
            let cursorChar = "\u{001B}[7m\(atCursor)\u{001B}[27m"
            textWithCursor = beforeCursor + cursorChar + remaining
        }

        let visualLength = visibleWidth(textWithCursor)
        let padding = String(repeating: " ", count: max(0, availableWidth - visualLength))
        let line = prompt + textWithCursor + padding

        return [line]
    }

    private func deleteWordBackwards() {
        guard cursor > 0 else { return }

        let oldCursor = cursor
        moveWordBackwards()
        let deleteFrom = cursor
        cursor = oldCursor

        let before = value.prefixCharacters(deleteFrom)
        let after = value.substring(from: cursor, length: value.count - cursor)
        value = before + after
        cursor = deleteFrom
    }

    private func moveWordBackwards() {
        guard cursor > 0 else { return }

        var textBeforeCursor = Array(value.prefixCharacters(cursor))

        while let last = textBeforeCursor.last, isWhitespaceChar(last) {
            textBeforeCursor.removeLast()
            cursor -= 1
        }

        if let last = textBeforeCursor.last {
            if isPunctuationChar(last) {
                while let tail = textBeforeCursor.last, isPunctuationChar(tail) {
                    textBeforeCursor.removeLast()
                    cursor -= 1
                }
            } else {
                while let tail = textBeforeCursor.last,
                      !isWhitespaceChar(tail),
                      !isPunctuationChar(tail) {
                    textBeforeCursor.removeLast()
                    cursor -= 1
                }
            }
        }
    }

    private func moveWordForwards() {
        guard cursor < value.count else { return }

        let textAfterCursor = Array(value.substring(from: cursor, length: value.count - cursor))
        var index = 0

        while index < textAfterCursor.count, isWhitespaceChar(textAfterCursor[index]) {
            cursor += 1
            index += 1
        }

        if index < textAfterCursor.count {
            let first = textAfterCursor[index]
            if isPunctuationChar(first) {
                while index < textAfterCursor.count, isPunctuationChar(textAfterCursor[index]) {
                    cursor += 1
                    index += 1
                }
            } else {
                while index < textAfterCursor.count,
                      !isWhitespaceChar(textAfterCursor[index]),
                      !isPunctuationChar(textAfterCursor[index]) {
                    cursor += 1
                    index += 1
                }
            }
        }
    }

    private func handlePaste(_ pastedText: String) {
        let cleanText = pastedText
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")

        let before = value.prefixCharacters(cursor)
        let after = value.substring(from: cursor, length: value.count - cursor)
        value = before + cleanText + after
        cursor += cleanText.count
    }

    private func killToEndOfLine() {
        let before = value.prefixCharacters(cursor)
        let after = value.substring(from: cursor, length: value.count - cursor)
        KillBuffer.shared.registerKill(after, append: true)
        value = before
    }

    private func yankKillBuffer() {
        let killBuffer = KillBuffer.shared.yank()
        guard !killBuffer.isEmpty else { return }
        let before = value.prefixCharacters(cursor)
        let after = value.substring(from: cursor, length: value.count - cursor)
        value = before + killBuffer + after
        cursor += killBuffer.count
    }

    private func killWordBackwards() {
        guard cursor > 0 else { return }

        let oldCursor = cursor
        moveWordBackwards()
        let deleteFrom = cursor
        cursor = oldCursor

        let before = value.prefixCharacters(deleteFrom)
        let after = value.substring(from: cursor, length: value.count - cursor)
        let deleted = value.substring(from: deleteFrom, length: max(0, cursor - deleteFrom))
        value = before + after
        cursor = deleteFrom

        KillBuffer.shared.registerKill(deleted, append: true, prepend: true)
    }

    private func killWordForwards() {
        guard cursor < value.count else { return }

        let textAfterCursor = Array(value.substring(from: cursor, length: value.count - cursor))
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

        let deleteTo = cursor + index
        let before = value.prefixCharacters(cursor)
        let after = value.substring(from: deleteTo, length: value.count - deleteTo)
        let deleted = value.substring(from: cursor, length: max(0, deleteTo - cursor))
        value = before + after

        KillBuffer.shared.registerKill(deleted, append: true)
    }
}
