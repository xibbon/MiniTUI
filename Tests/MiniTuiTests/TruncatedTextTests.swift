import Testing
import MiniTui

@MainActor
@Test("pads output lines to exactly match width")
func padsOutputLines() {
    let text = TruncatedText("Hello world", paddingX: 1, paddingY: 0)
    let lines = text.render(width: 50)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 50)
}

@MainActor
@Test("pads output with vertical padding lines to width")
func padsOutputWithVerticalPadding() {
    let text = TruncatedText("Hello", paddingX: 0, paddingY: 2)
    let lines = text.render(width: 40)
    #expect(lines.count == 5)
    for line in lines {
        #expect(visibleWidth(line) == 40)
    }
}

@MainActor
@Test("truncates long text and pads to width")
func truncatesLongText() {
    let longText = "This is a very long piece of text that will definitely exceed the available width"
    let text = TruncatedText(longText, paddingX: 1, paddingY: 0)
    let lines = text.render(width: 30)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 30)
    let stripped = stripAnsiCodes(lines[0])
    #expect(stripped.contains("..."))
}

@MainActor
@Test("preserves ANSI codes in output and pads correctly")
func preservesAnsiCodes() {
    let styledText = "\(Ansi.red("Hello")) \(Ansi.blue("world"))"
    let text = TruncatedText(styledText, paddingX: 1, paddingY: 0)
    let lines = text.render(width: 40)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 40)
    #expect(lines[0].contains("\u{001B}["))
}

@MainActor
@Test("truncates styled text and adds reset code before ellipsis")
func truncatesStyledText() {
    let longStyledText = Ansi.red("This is a very long red text that will be truncated")
    let text = TruncatedText(longStyledText, paddingX: 1, paddingY: 0)
    let lines = text.render(width: 20)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 20)
    #expect(lines[0].contains("\u{001B}[0m..."))
}

@MainActor
@Test("handles text that fits exactly")
func handlesExactText() {
    let text = TruncatedText("Hello world", paddingX: 1, paddingY: 0)
    let lines = text.render(width: 30)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 30)
    let stripped = stripAnsiCodes(lines[0])
    #expect(!stripped.contains("..."))
}

@MainActor
@Test("handles empty text")
func handlesEmptyText() {
    let text = TruncatedText("", paddingX: 1, paddingY: 0)
    let lines = text.render(width: 30)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 30)
}

@MainActor
@Test("stops at newline and only shows first line")
func stopsAtNewline() {
    let multilineText = "First line\nSecond line\nThird line"
    let text = TruncatedText(multilineText, paddingX: 1, paddingY: 0)
    let lines = text.render(width: 40)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 40)
    let stripped = stripAnsiCodes(lines[0]).trimmingCharacters(in: .whitespaces)
    #expect(stripped.contains("First line"))
    #expect(!stripped.contains("Second line"))
    #expect(!stripped.contains("Third line"))
}

@MainActor
@Test("truncates first line even with newlines in text")
func truncatesFirstLineWithNewlines() {
    let longMultilineText = "This is a very long first line that needs truncation\nSecond line"
    let text = TruncatedText(longMultilineText, paddingX: 1, paddingY: 0)
    let lines = text.render(width: 25)
    #expect(lines.count == 1)
    #expect(visibleWidth(lines[0]) == 25)
    let stripped = stripAnsiCodes(lines[0])
    #expect(stripped.contains("..."))
    #expect(!stripped.contains("Second line"))
}
