import Testing
import MiniTui

@MainActor
@Test("does nothing on Up arrow when history is empty")
func historyUpWhenEmpty() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "")
}

@MainActor
@Test("shows most recent history entry on Up arrow when editor is empty")
func historyUpShowsMostRecent() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("first prompt")
    editor.addToHistory("second prompt")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "second prompt")
}

@MainActor
@Test("cycles through history entries on repeated Up arrow")
func historyCyclesUp() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("first")
    editor.addToHistory("second")
    editor.addToHistory("third")

    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "third")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "second")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "first")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "first")
}

@MainActor
@Test("returns to empty editor on Down arrow after browsing history")
func historyDownClears() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("prompt")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "prompt")
    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "")
}

@MainActor
@Test("navigates forward through history with Down arrow")
func historyDownNavigates() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("first")
    editor.addToHistory("second")
    editor.addToHistory("third")

    editor.handleInput("\u{001B}[A")
    editor.handleInput("\u{001B}[A")
    editor.handleInput("\u{001B}[A")

    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "second")
    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "third")
    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "")
}

@MainActor
@Test("exits history mode when typing a character")
func historyExitsOnTyping() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("old prompt")
    editor.handleInput("\u{001B}[A")
    editor.handleInput("x")
    #expect(editor.getText() == "old promptx")
}

@MainActor
@Test("exits history mode on setText")
func historyExitsOnSetText() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("first")
    editor.addToHistory("second")
    editor.handleInput("\u{001B}[A")
    editor.setText("")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "second")
}

@MainActor
@Test("does not add empty strings to history")
func historyIgnoresEmpty() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("")
    editor.addToHistory("   ")
    editor.addToHistory("valid")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "valid")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "valid")
}

@MainActor
@Test("does not add consecutive duplicates to history")
func historyNoConsecutiveDuplicates() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("same")
    editor.addToHistory("same")
    editor.addToHistory("same")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "same")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "same")
}

@MainActor
@Test("allows non-consecutive duplicates in history")
func historyAllowsNonConsecutiveDuplicates() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("first")
    editor.addToHistory("second")
    editor.addToHistory("first")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "first")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "second")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "first")
}

@MainActor
@Test("uses cursor movement instead of history when editor has content")
func historyNotWhenContentExists() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("history item")
    editor.setText("line1\nline2")
    editor.handleInput("\u{001B}[A")
    editor.handleInput("X")
    #expect(editor.getText() == "line1X\nline2")
}

@MainActor
@Test("limits history to 100 entries")
func historyLimit() {
    let editor = Editor(theme: defaultEditorTheme)
    for i in 0..<105 {
        editor.addToHistory("prompt \(i)")
    }
    for _ in 0..<100 {
        editor.handleInput("\u{001B}[A")
    }
    #expect(editor.getText() == "prompt 5")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "prompt 5")
}

@MainActor
@Test("allows cursor movement within multi-line history entry with Down")
func historyMultiLineDown() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("line1\nline2\nline3")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "line1\nline2\nline3")
    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "")
}

@MainActor
@Test("allows cursor movement within multi-line history entry with Up")
func historyMultiLineUp() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("older entry")
    editor.addToHistory("line1\nline2\nline3")
    editor.handleInput("\u{001B}[A")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "line1\nline2\nline3")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "line1\nline2\nline3")
    editor.handleInput("\u{001B}[A")
    #expect(editor.getText() == "older entry")
}

@MainActor
@Test("navigates from multi-line entry back to newer via Down after cursor movement")
func historyMultiLineDownAfterMove() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.addToHistory("line1\nline2\nline3")
    editor.handleInput("\u{001B}[A")
    editor.handleInput("\u{001B}[A")
    editor.handleInput("\u{001B}[A")
    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "line1\nline2\nline3")
    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "line1\nline2\nline3")
    editor.handleInput("\u{001B}[B")
    #expect(editor.getText() == "")
}

@MainActor
@Test("returns cursor position")
func returnsCursorPosition() {
    let editor = Editor(theme: defaultEditorTheme)
    #expect(editor.getCursor().line == 0)
    #expect(editor.getCursor().col == 0)
    editor.handleInput("a")
    editor.handleInput("b")
    editor.handleInput("c")
    #expect(editor.getCursor().line == 0)
    #expect(editor.getCursor().col == 3)
    editor.handleInput("\u{001B}[D")
    #expect(editor.getCursor().col == 2)
}

@MainActor
@Test("returns lines as a defensive copy")
func returnsLinesCopy() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.setText("a\nb")
    var lines = editor.getLines()
    #expect(lines == ["a", "b"])
    lines[0] = "mutated"
    #expect(editor.getLines() == ["a", "b"])
}

@MainActor
@Test("inserts mixed ASCII, umlauts, and emojis as literal text")
func insertsUnicode() {
    let editor = Editor(theme: defaultEditorTheme)
    for char in ["H", "e", "l", "l", "o", " ", "ä", "ö", "ü", " ", "😀"] {
        editor.handleInput(char)
    }
    #expect(editor.getText() == "Hello äöü 😀")
}

@MainActor
@Test("treats split Shift+Enter as a newline")
func shiftEnterSplitNewline() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("\\")
    editor.handleInput("\r")
    #expect(editor.getText() == "\n")
}

@MainActor
@Test("inserts a literal backslash when not followed by Enter")
func shiftEnterBackslashLiteral() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("\\")
    editor.handleInput("x")
    #expect(editor.getText() == "\\x")
}

@MainActor
@Test("deletes single-code-unit unicode characters with Backspace")
func deletesUmlauts() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("ä")
    editor.handleInput("ö")
    editor.handleInput("ü")
    editor.handleInput("\u{007F}")
    #expect(editor.getText() == "äö")
}

@MainActor
@Test("deletes multi-code-unit emojis with single Backspace")
func deletesEmoji() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("😀")
    editor.handleInput("👍")
    editor.handleInput("\u{007F}")
    #expect(editor.getText() == "😀")
}

@MainActor
@Test("inserts characters at the correct position after cursor movement over umlauts")
func insertsAfterCursorMoveUmlaut() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("ä")
    editor.handleInput("ö")
    editor.handleInput("ü")
    editor.handleInput("\u{001B}[D")
    editor.handleInput("\u{001B}[D")
    editor.handleInput("x")
    #expect(editor.getText() == "äxöü")
}

@MainActor
@Test("moves cursor across multi-code-unit emojis with single arrow key")
func cursorMovesOverEmoji() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("😀")
    editor.handleInput("👍")
    editor.handleInput("🎉")
    editor.handleInput("\u{001B}[D")
    editor.handleInput("\u{001B}[D")
    editor.handleInput("x")
    #expect(editor.getText() == "😀x👍🎉")
}

@MainActor
@Test("preserves umlauts across line breaks")
func preservesUmlautsAcrossLines() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("ä")
    editor.handleInput("ö")
    editor.handleInput("ü")
    editor.handleInput("\n")
    editor.handleInput("Ä")
    editor.handleInput("Ö")
    editor.handleInput("Ü")
    #expect(editor.getText() == "äöü\nÄÖÜ")
}

@MainActor
@Test("replaces the entire document with unicode text via setText")
func setTextUnicode() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.setText("Hällö Wörld! 😀 äöüÄÖÜß")
    #expect(editor.getText() == "Hällö Wörld! 😀 äöüÄÖÜß")
}

@MainActor
@Test("moves cursor to document start on Ctrl+A and inserts at the beginning")
func ctrlAInsertsAtStart() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.handleInput("a")
    editor.handleInput("b")
    editor.handleInput("\u{0001}")
    editor.handleInput("x")
    #expect(editor.getText() == "xab")
}

@MainActor
@Test("deletes words correctly with Ctrl+W and Alt+Backspace")
func deletesWords() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.setText("foo bar baz")
    editor.handleInput("\u{0017}")
    #expect(editor.getText() == "foo bar ")

    editor.setText("foo bar   ")
    editor.handleInput("\u{0017}")
    #expect(editor.getText() == "foo ")

    editor.setText("foo bar...")
    editor.handleInput("\u{0017}")
    #expect(editor.getText() == "foo bar")

    editor.setText("line one\nline two")
    editor.handleInput("\u{0017}")
    #expect(editor.getText() == "line one\nline ")

    editor.setText("line one\n")
    editor.handleInput("\u{0017}")
    #expect(editor.getText() == "line one")

    editor.setText("foo 😀😀 bar")
    editor.handleInput("\u{0017}")
    #expect(editor.getText() == "foo 😀😀 ")
    editor.handleInput("\u{0017}")
    #expect(editor.getText() == "foo ")

    editor.setText("foo bar")
    editor.handleInput("\u{001B}\u{007F}")
    #expect(editor.getText() == "foo ")
}

@MainActor
@Test("navigates words correctly with Ctrl+Left/Right")
func navigatesWords() {
    let editor = Editor(theme: defaultEditorTheme)
    editor.setText("foo bar... baz")

    editor.handleInput("\u{001B}[1;5D")
    #expect(editor.getCursor().col == 11)
    editor.handleInput("\u{001B}[1;5D")
    #expect(editor.getCursor().col == 7)
    editor.handleInput("\u{001B}[1;5D")
    #expect(editor.getCursor().col == 4)

    editor.handleInput("\u{001B}[1;5C")
    #expect(editor.getCursor().col == 7)
    editor.handleInput("\u{001B}[1;5C")
    #expect(editor.getCursor().col == 10)
    editor.handleInput("\u{001B}[1;5C")
    #expect(editor.getCursor().col == 14)

    editor.setText("   foo bar")
    editor.handleInput("\u{0001}")
    editor.handleInput("\u{001B}[1;5C")
    #expect(editor.getCursor().col == 6)
}

@MainActor
@Test("wraps lines correctly when text contains wide emojis")
func wrapsWideEmoji() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 20
    editor.setText("Hello ✅ World")
    let lines = editor.render(width: width)
    for line in lines.dropFirst().dropLast() {
        #expect(visibleWidth(line) == width)
    }
}

@MainActor
@Test("wraps long text with emojis at correct positions")
func wrapsLongEmoji() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 10
    editor.setText("✅✅✅✅✅✅")
    let lines = editor.render(width: width)
    for line in lines.dropFirst().dropLast() {
        #expect(visibleWidth(line) == width)
    }
}

@MainActor
@Test("wraps CJK characters correctly")
func wrapsCjk() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 10
    editor.setText("日本語テスト")
    let lines = editor.render(width: width)
    for line in lines.dropFirst().dropLast() {
        #expect(visibleWidth(line) == width)
    }
    let contentLines = lines.dropFirst().dropLast().map { stripVTControlCharacters($0).trimmingCharacters(in: .whitespaces) }
    #expect(contentLines.count == 2)
    #expect(contentLines[0] == "日本語テス")
    #expect(contentLines[1] == "ト")
}

@MainActor
@Test("handles mixed ASCII and wide characters in wrapping")
func wrapsMixedWidth() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 15
    editor.setText("Test ✅ OK 日本")
    let lines = editor.render(width: width)
    let contentLines = Array(lines.dropFirst().dropLast())
    #expect(contentLines.count == 1)
    #expect(visibleWidth(contentLines[0]) == width)
}

@MainActor
@Test("renders cursor correctly on wide characters")
func rendersCursorOnWideChars() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 20
    editor.setText("A✅B")
    let lines = editor.render(width: width)
    let contentLine = lines[1]
    #expect(contentLine.contains("\u{001B}[7m"))
    #expect(visibleWidth(contentLine) == width)
}

@MainActor
@Test("does not exceed terminal width with emoji at wrap boundary")
func emojiWrapBoundary() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 11
    editor.setText("0123456789✅")
    let lines = editor.render(width: width)
    for line in lines.dropFirst().dropLast() {
        #expect(visibleWidth(line) <= width)
    }
}

@MainActor
@Test("wraps at word boundaries without leading whitespace")
func wrapsAtWordBoundaries() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 20
    editor.setText("Word1 Word2 Word3 Word4 Word5 Word6")
    let lines = editor.render(width: width)

    for line in lines.dropFirst().dropLast() {
        let stripped = stripVTControlCharacters(line).trimmingTrailingWhitespace()
        if stripped.isEmpty { continue }
        #expect(!stripped.first!.isWhitespace)
    }
}

@MainActor
@Test("breaks long words at character level")
func breaksLongWords() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 30
    editor.setText("Check https://example.com/very/long/path/that/exceeds/width here")
    let lines = editor.render(width: width)
    for line in lines.dropFirst().dropLast() {
        #expect(visibleWidth(line) == width)
    }
}

@MainActor
@Test("preserves multiple spaces within a line")
func preservesMultipleSpaces() {
    let editor = Editor(theme: defaultEditorTheme)
    let width = 50
    editor.setText("Word1   Word2    Word3")
    let lines = editor.render(width: width)
    let contentLine = stripVTControlCharacters(lines[1]).trimmingCharacters(in: .whitespaces)
    #expect(contentLine.contains("Word1   Word2"))
}
