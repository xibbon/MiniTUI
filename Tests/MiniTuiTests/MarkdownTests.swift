import Testing
import MiniTui

@Test("renders simple nested list")
func rendersSimpleNestedList() {
    let markdown = Markdown(
        """
- Item 1
  - Nested 1.1
  - Nested 1.2
- Item 2
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("- Item 1") }))
    #expect(plainLines.contains(where: { $0.contains("  - Nested 1.1") }))
    #expect(plainLines.contains(where: { $0.contains("  - Nested 1.2") }))
    #expect(plainLines.contains(where: { $0.contains("- Item 2") }))
}

@Test("renders deeply nested list")
func rendersDeepNestedList() {
    let markdown = Markdown(
        """
- Level 1
  - Level 2
    - Level 3
      - Level 4
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("- Level 1") }))
    #expect(plainLines.contains(where: { $0.contains("  - Level 2") }))
    #expect(plainLines.contains(where: { $0.contains("    - Level 3") }))
    #expect(plainLines.contains(where: { $0.contains("      - Level 4") }))
}

@Test("renders ordered nested list")
func rendersOrderedNestedList() {
    let markdown = Markdown(
        """
1. First
   1. Nested first
   2. Nested second
2. Second
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("1. First") }))
    #expect(plainLines.contains(where: { $0.contains("  1. Nested first") }))
    #expect(plainLines.contains(where: { $0.contains("  2. Nested second") }))
    #expect(plainLines.contains(where: { $0.contains("2. Second") }))
}

@Test("renders mixed ordered and unordered nested lists")
func rendersMixedLists() {
    let markdown = Markdown(
        """
1. Ordered item
   - Unordered nested
   - Another nested
2. Second ordered
   - More nested
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("1. Ordered item") }))
    #expect(plainLines.contains(where: { $0.contains("  - Unordered nested") }))
    #expect(plainLines.contains(where: { $0.contains("2. Second ordered") }))
}

@Test("renders simple table")
func rendersSimpleTable() {
    let markdown = Markdown(
        """
| Name | Age |
| --- | --- |
| Alice | 30 |
| Bob | 25 |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("Name") }))
    #expect(plainLines.contains(where: { $0.contains("Age") }))
    #expect(plainLines.contains(where: { $0.contains("Alice") }))
    #expect(plainLines.contains(where: { $0.contains("Bob") }))
    #expect(plainLines.contains(where: { $0.contains("│") }))
    #expect(plainLines.contains(where: { $0.contains("─") }))
}

@Test("renders table with alignment")
func rendersTableWithAlignment() {
    let markdown = Markdown(
        """
| Left | Center | Right |
| :--- | :---: | ---: |
| A | B | C |
| Long text | Middle | End |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("Left") }))
    #expect(plainLines.contains(where: { $0.contains("Center") }))
    #expect(plainLines.contains(where: { $0.contains("Right") }))
    #expect(plainLines.contains(where: { $0.contains("Long text") }))
}

@Test("handles tables with varying column widths")
func handlesVaryingTableWidths() {
    let markdown = Markdown(
        """
| Short | Very long column header |
| --- | --- |
| A | This is a much longer cell content |
| B | Short |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("Very long column header") }))
    #expect(plainLines.contains(where: { $0.contains("This is a much longer cell content") }))
}

@Test("wraps table cells when table exceeds available width")
func wrapsTableCells() {
    let markdown = Markdown(
        """
| Command | Description | Example |
| --- | --- | --- |
| npm install | Install all dependencies | npm install |
| npm run build | Build the project | npm run build |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 50)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }

    for line in plainLines {
        #expect(line.count <= 50)
    }

    let allText = plainLines.joined(separator: " ")
    #expect(allText.contains("Command"))
    #expect(allText.contains("Description"))
    #expect(allText.contains("npm install"))
    #expect(allText.contains("Install"))
}

@Test("wraps long cell content to multiple lines")
func wrapsLongCellContent() {
    let markdown = Markdown(
        """
| Header |
| --- |
| This is a very long cell content that should wrap |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 25)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    let dataRows = plainLines.filter { $0.hasPrefix("│") && !$0.contains("─") }
    #expect(dataRows.count > 2)

    let allText = plainLines.joined(separator: " ")
    #expect(allText.contains("very long"))
    #expect(allText.contains("cell content"))
    #expect(allText.contains("should wrap"))
}

@Test("wraps long unbroken tokens inside table cells")
func wrapsLongTokensInTableCells() {
    let url = "https://example.com/this/is/a/very/long/url/that/should/wrap"
    let markdown = Markdown(
        """
| Value |
| --- |
| prefix \(url) |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let width = 30
    let lines = markdown.render(width: width)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    for line in plainLines {
        #expect(line.count <= width)
    }

    let tableLines = plainLines.filter { $0.hasPrefix("│") }
    for line in tableLines {
        let borderCount = line.split(separator: "│", omittingEmptySubsequences: false).count - 1
        #expect(borderCount == 2)
    }

    let extracted = plainLines.joined().replacingOccurrences(of: "│", with: "").replacingOccurrences(of: "├", with: "").replacingOccurrences(of: "┤", with: "").replacingOccurrences(of: "─", with: "").replacingOccurrences(of: " ", with: "")
    #expect(extracted.contains("prefix"))
    #expect(extracted.contains(url))
}

@Test("wraps styled inline code inside table cells")
func wrapsStyledInlineCode() {
    let markdown = Markdown(
        """
| Code |
| --- |
| `averyveryveryverylongidentifier` |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let width = 20
    let lines = markdown.render(width: width)
    let joinedOutput = lines.joined(separator: "\n")
    #expect(joinedOutput.contains("\u{001B}[33m"))

    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    for line in plainLines {
        #expect(line.count <= width)
    }

    let tableLines = plainLines.filter { $0.hasPrefix("│") }
    for line in tableLines {
        let borderCount = line.split(separator: "│", omittingEmptySubsequences: false).count - 1
        #expect(borderCount == 2)
    }
}

@Test("handles extremely narrow width gracefully")
func handlesExtremelyNarrowWidth() {
    let markdown = Markdown(
        """
| A | B | C |
| --- | --- | --- |
| 1 | 2 | 3 |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 15)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    #expect(!lines.isEmpty)
    for line in plainLines {
        #expect(line.count <= 15)
    }
}

@Test("renders table correctly when it fits naturally")
func rendersTableNaturally() {
    let markdown = Markdown(
        """
| A | B |
| --- | --- |
| 1 | 2 |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }

    let headerLine = plainLines.first(where: { $0.contains("A") && $0.contains("B") })
    #expect(headerLine != nil)
    #expect(headerLine?.contains("│") == true)

    let separatorLine = plainLines.first(where: { $0.contains("├") && $0.contains("┼") })
    #expect(separatorLine != nil)

    let dataLine = plainLines.first(where: { $0.contains("1") && $0.contains("2") })
    #expect(dataLine != nil)
}

@Test("respects paddingX when calculating table width")
func respectsPaddingX() {
    let markdown = Markdown(
        """
| Column One | Column Two |
| --- | --- |
| Data 1 | Data 2 |
""",
        paddingX: 2,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    for line in plainLines {
        #expect(line.count <= 40)
    }

    let tableRow = plainLines.first(where: { $0.contains("│") })
    #expect(tableRow?.hasPrefix("  ") == true)
}

@Test("renders lists and tables together")
func rendersListsAndTables() {
    let markdown = Markdown(
        """
# Test Document

- Item 1
  - Nested item
- Item 2

| Col1 | Col2 |
| --- | --- |
| A | B |
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    #expect(plainLines.contains(where: { $0.contains("Test Document") }))
    #expect(plainLines.contains(where: { $0.contains("- Item 1") }))
    #expect(plainLines.contains(where: { $0.contains("  - Nested item") }))
    #expect(plainLines.contains(where: { $0.contains("Col1") }))
    #expect(plainLines.contains(where: { $0.contains("│") }))
}

@Test("preserves gray italic styling after inline code")
func preservesGrayItalicAfterInlineCode() {
    let markdown = Markdown(
        "This is thinking with `inline code` and more text after",
        paddingX: 1,
        paddingY: 0,
        theme: defaultMarkdownTheme,
        defaultTextStyle: DefaultTextStyle(color: { Ansi.gray($0) }, italic: true)
    )

    let lines = markdown.render(width: 80)
    let joinedOutput = lines.joined(separator: "\n")
    #expect(joinedOutput.contains("inline code"))
    #expect(joinedOutput.contains("\u{001B}[90m"))
    #expect(joinedOutput.contains("\u{001B}[3m"))
    #expect(joinedOutput.contains("\u{001B}[33m"))
}

@Test("preserves gray italic styling after bold text")
func preservesGrayItalicAfterBold() {
    let markdown = Markdown(
        "This is thinking with **bold text** and more after",
        paddingX: 1,
        paddingY: 0,
        theme: defaultMarkdownTheme,
        defaultTextStyle: DefaultTextStyle(color: { Ansi.gray($0) }, italic: true)
    )

    let lines = markdown.render(width: 80)
    let joinedOutput = lines.joined(separator: "\n")
    #expect(joinedOutput.contains("bold text"))
    #expect(joinedOutput.contains("\u{001B}[90m"))
    #expect(joinedOutput.contains("\u{001B}[3m"))
    #expect(joinedOutput.contains("\u{001B}[1m"))
}

@Test("has only one blank line between code block and following paragraph")
func spacingAfterCodeBlock() {
    let markdown = Markdown(
        """
hello world

```js
const hello = "world";
```

again, hello world
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    guard let closingIndex = plainLines.firstIndex(of: "```") else {
        #expect(Bool(false))
        return
    }
    let afterBackticks = plainLines.suffix(from: closingIndex + 1)
    let emptyLineCount = afterBackticks.prefix(while: { $0.isEmpty }).count
    #expect(emptyLineCount == 1)
}

@Test("has only one blank line between divider and following paragraph")
func spacingAfterDivider() {
    let markdown = Markdown(
        """
hello world

---

again, hello world
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    let dividerIndex = plainLines.firstIndex(where: { $0.contains("─") })
    #expect(dividerIndex != nil)
    if let dividerIndex {
        let afterDivider = plainLines.suffix(from: dividerIndex + 1)
        let emptyLineCount = afterDivider.prefix(while: { $0.isEmpty }).count
        #expect(emptyLineCount == 1)
    }
}

@Test("has only one blank line between heading and following paragraph")
func spacingAfterHeading() {
    let markdown = Markdown(
        """
# Hello

This is a paragraph
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    let headingIndex = plainLines.firstIndex(where: { $0.contains("Hello") })
    #expect(headingIndex != nil)
    if let headingIndex {
        let afterHeading = plainLines.suffix(from: headingIndex + 1)
        let emptyLineCount = afterHeading.prefix(while: { $0.isEmpty }).count
        #expect(emptyLineCount == 1)
    }
}

@Test("has only one blank line between blockquote and following paragraph")
func spacingAfterBlockquote() {
    let markdown = Markdown(
        """
hello world

> This is a quote

again, hello world
""",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
    let quoteIndex = plainLines.firstIndex(where: { $0.contains("This is a quote") })
    #expect(quoteIndex != nil)
    if let quoteIndex {
        let afterQuote = plainLines.suffix(from: quoteIndex + 1)
        let emptyLineCount = afterQuote.prefix(while: { $0.isEmpty }).count
        #expect(emptyLineCount == 1)
    }
}

@Test("renders HTML-like tags as text")
func rendersHtmlLikeTags() {
    let markdown = Markdown(
        "This is text with <thinking>hidden content</thinking> that should be visible",
        paddingX: 0,
        paddingY: 0,
        theme: defaultMarkdownTheme
    )

    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    let joined = plainLines.joined(separator: " ")
    #expect(joined.contains("hidden content") || joined.contains("<thinking>"))
}

@Test("renders HTML tags in code blocks correctly")
func rendersHtmlInCodeBlocks() {
    let markdown = Markdown("```html\n<div>Some HTML</div>\n```", paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
    let lines = markdown.render(width: 80)
    let plainLines = lines.map(stripAnsiCodes)
    let joined = plainLines.joined(separator: "\n")
    #expect(joined.contains("<div>") && joined.contains("</div>"))
}
