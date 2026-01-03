import Foundation
import Markdown

/// Default text styling applied when no specific Markdown style is active.
public struct DefaultTextStyle: Sendable {
    /// Foreground color formatter.
    public let color: (@Sendable (String) -> String)?
    /// Background color formatter.
    public let bgColor: (@Sendable (String) -> String)?
    /// Render text in bold.
    public let bold: Bool
    /// Render text in italic.
    public let italic: Bool
    /// Render text with strikethrough.
    public let strikethrough: Bool
    /// Render text with underline.
    public let underline: Bool

    /// Create a default text style.
    public init(
        color: (@Sendable (String) -> String)? = nil,
        bgColor: (@Sendable (String) -> String)? = nil,
        bold: Bool = false,
        italic: Bool = false,
        strikethrough: Bool = false,
        underline: Bool = false
    ) {
        self.color = color
        self.bgColor = bgColor
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.underline = underline
    }
}

/// Theme configuration for Markdown rendering.
public struct MarkdownTheme: Sendable {
    /// Style for headings.
    public let heading: @Sendable (String) -> String
    /// Style for link text.
    public let link: @Sendable (String) -> String
    /// Style for link URLs.
    public let linkUrl: @Sendable (String) -> String
    /// Style for inline code.
    public let code: @Sendable (String) -> String
    /// Style for code block content.
    public let codeBlock: @Sendable (String) -> String
    /// Style for code block borders.
    public let codeBlockBorder: @Sendable (String) -> String
    /// Style for blockquotes.
    public let quote: @Sendable (String) -> String
    /// Style for blockquote borders.
    public let quoteBorder: @Sendable (String) -> String
    /// Style for horizontal rules.
    public let hr: @Sendable (String) -> String
    /// Style for list bullets.
    public let listBullet: @Sendable (String) -> String
    /// Style for bold text.
    public let bold: @Sendable (String) -> String
    /// Style for italic text.
    public let italic: @Sendable (String) -> String
    /// Style for strikethrough text.
    public let strikethrough: @Sendable (String) -> String
    /// Style for underlined text.
    public let underline: @Sendable (String) -> String
    /// Optional syntax highlighter for fenced code blocks.
    public let highlightCode: (@Sendable (String, String?) -> [String])?

    /// Create a Markdown theme.
    public init(
        heading: @escaping @Sendable (String) -> String,
        link: @escaping @Sendable (String) -> String,
        linkUrl: @escaping @Sendable (String) -> String,
        code: @escaping @Sendable (String) -> String,
        codeBlock: @escaping @Sendable (String) -> String,
        codeBlockBorder: @escaping @Sendable (String) -> String,
        quote: @escaping @Sendable (String) -> String,
        quoteBorder: @escaping @Sendable (String) -> String,
        hr: @escaping @Sendable (String) -> String,
        listBullet: @escaping @Sendable (String) -> String,
        bold: @escaping @Sendable (String) -> String,
        italic: @escaping @Sendable (String) -> String,
        strikethrough: @escaping @Sendable (String) -> String,
        underline: @escaping @Sendable (String) -> String,
        highlightCode: (@Sendable (String, String?) -> [String])? = nil
    ) {
        self.heading = heading
        self.link = link
        self.linkUrl = linkUrl
        self.code = code
        self.codeBlock = codeBlock
        self.codeBlockBorder = codeBlockBorder
        self.quote = quote
        self.quoteBorder = quoteBorder
        self.hr = hr
        self.listBullet = listBullet
        self.bold = bold
        self.italic = italic
        self.strikethrough = strikethrough
        self.underline = underline
        self.highlightCode = highlightCode
    }
}

/// Markdown renderer that outputs styled terminal lines.
public final class Markdown: Component {
    private var text: String
    private let paddingX: Int
    private let paddingY: Int
    private let theme: MarkdownTheme
    private let defaultTextStyle: DefaultTextStyle?
    private var defaultStylePrefix: String?

    private var cachedText: String?
    private var cachedWidth: Int?
    private var cachedLines: [String]?

    /// Create a Markdown component.
    public init(
        _ text: String,
        paddingX: Int,
        paddingY: Int,
        theme: MarkdownTheme,
        defaultTextStyle: DefaultTextStyle? = nil
    ) {
        self.text = text
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.theme = theme
        self.defaultTextStyle = defaultTextStyle
    }

    /// Update the Markdown text and invalidate cached lines.
    public func setText(_ text: String) {
        self.text = text
        invalidate()
    }

    /// Clear cached render state.
    public func invalidate() {
        cachedText = nil
        cachedWidth = nil
        cachedLines = nil
    }

    /// Render the Markdown content into terminal lines.
    public func render(width: Int) -> [String] {
        if let cachedLines, cachedText == text, cachedWidth == width {
            return cachedLines
        }

        let contentWidth = max(1, width - paddingX * 2)

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let result: [String] = []
            cachedText = text
            cachedWidth = width
            cachedLines = result
            return result
        }

        let normalizedText = text.replacingOccurrences(of: "\t", with: "   ")
        let document = Document(parsing: normalizedText)
        let blocks = Array(document.children)

        let blockOutputs: [(lines: [String], isBlank: Bool)] = blocks.map { block in
            let lines = renderBlock(block, width: contentWidth)
            let isBlank = lines.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return (lines, isBlank)
        }

        var renderedLines: [String] = []
        var hasPreviousNonBlank = false
        for output in blockOutputs where !output.isBlank {
            if hasPreviousNonBlank, renderedLines.last != "" {
                renderedLines.append("")
            }
            renderedLines.append(contentsOf: output.lines)
            hasPreviousNonBlank = true
        }

        var normalizedLines: [String] = []
        var lastWasEmpty = false
        for line in renderedLines {
            if line.isEmpty {
                if lastWasEmpty {
                    continue
                }
                lastWasEmpty = true
            } else {
                lastWasEmpty = false
            }
            normalizedLines.append(line)
        }

        var wrappedLines: [String] = []
        for line in normalizedLines {
            wrappedLines.append(contentsOf: wrapTextWithAnsi(line, width: contentWidth))
        }

        let leftMargin = String(repeating: " ", count: paddingX)
        let rightMargin = String(repeating: " ", count: paddingX)
        let bgFn = defaultTextStyle?.bgColor
        var contentLines: [String] = []

        for line in wrappedLines {
            let lineWithMargins = leftMargin + line + rightMargin
            if let bgFn {
                contentLines.append(applyBackgroundToLine(lineWithMargins, width: width, bgFn: bgFn))
            } else {
                let visibleLen = visibleWidth(lineWithMargins)
                let paddingNeeded = max(0, width - visibleLen)
                contentLines.append(lineWithMargins + String(repeating: " ", count: paddingNeeded))
            }
        }

        var collapsedContentLines: [String] = []
        var lastWasBlank = false
        for line in contentLines {
            let stripped = stripAnsiCodes(line).trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty {
                if lastWasBlank {
                    continue
                }
                lastWasBlank = true
            } else {
                lastWasBlank = false
            }
            collapsedContentLines.append(line)
        }

        let emptyLine = String(repeating: " ", count: width)
        var emptyLines: [String] = []
        for _ in 0..<paddingY {
            let line = bgFn.map { applyBackgroundToLine(emptyLine, width: width, bgFn: $0) } ?? emptyLine
            emptyLines.append(line)
        }

        let result = emptyLines + collapsedContentLines + emptyLines
        cachedText = text
        cachedWidth = width
        cachedLines = result

        return result.isEmpty ? [""] : result
    }

    private func applyDefaultStyle(_ text: String) -> String {
        guard let defaultTextStyle else { return text }
        var styled = text

        if let color = defaultTextStyle.color {
            styled = color(styled)
        }

        if defaultTextStyle.bold {
            styled = theme.bold(styled)
        }
        if defaultTextStyle.italic {
            styled = theme.italic(styled)
        }
        if defaultTextStyle.strikethrough {
            styled = theme.strikethrough(styled)
        }
        if defaultTextStyle.underline {
            styled = theme.underline(styled)
        }

        return styled
    }

    private func getDefaultStylePrefix() -> String {
        guard let defaultTextStyle else { return "" }
        if let prefix = defaultStylePrefix { return prefix }

        let sentinel = "\u{0000}"
        var styled = sentinel

        if let color = defaultTextStyle.color {
            styled = color(styled)
        }
        if defaultTextStyle.bold {
            styled = theme.bold(styled)
        }
        if defaultTextStyle.italic {
            styled = theme.italic(styled)
        }
        if defaultTextStyle.strikethrough {
            styled = theme.strikethrough(styled)
        }
        if defaultTextStyle.underline {
            styled = theme.underline(styled)
        }

        if let sentinelIndex = styled.firstIndex(of: "\u{0000}") {
            let prefix = String(styled[..<sentinelIndex])
            defaultStylePrefix = prefix
            return prefix
        }

        defaultStylePrefix = ""
        return ""
    }

    private func renderBlock(_ block: Markup, width: Int) -> [String] {
        if let heading = block as? Heading {
            let headingText = renderInlineChildren(heading)
            let level = heading.level
            if level == 1 {
                return [theme.heading(theme.bold(theme.underline(headingText)))]
            } else if level == 2 {
                return [theme.heading(theme.bold(headingText))]
            }
            return [theme.heading(theme.bold(String(repeating: "#", count: level) + " " + headingText))]
        }

        if let paragraph = block as? Paragraph {
            return [renderInlineChildren(paragraph)]
        }

        if let codeBlock = block as? CodeBlock {
            var lines: [String] = []
            lines.append(theme.codeBlockBorder("```\(codeBlock.language ?? "")"))
            if let highlightCode = theme.highlightCode {
                for line in highlightCode(codeBlock.code, codeBlock.language) {
                    lines.append("  \(line)")
                }
            } else {
                for line in codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("  \(theme.codeBlock(String(line)))")
                }
            }
            lines.append(theme.codeBlockBorder("```"))
            return lines
        }

        if let list = block as? UnorderedList {
            return renderList(listItems: Array(list.listItems), ordered: false, startIndex: 1, depth: 0)
        }

        if let list = block as? OrderedList {
            return renderList(listItems: Array(list.listItems), ordered: true, startIndex: Int(list.startIndex), depth: 0)
        }

        if let table = block as? Table {
            return renderTable(table: table, availableWidth: width)
        }

        if let blockquote = block as? BlockQuote {
            let quoteLines = renderBlocks(Array(blockquote.children), width: width)
            return quoteLines.map { line in
                theme.quoteBorder("│ ") + theme.quote(theme.italic(line))
            }
        }

        if block is ThematicBreak {
            return [theme.hr(String(repeating: "─", count: min(width, 80)))]
        }

        if let html = block as? HTMLBlock {
            return [applyDefaultStyle(html.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines))]
        }

        return renderBlocks(Array(block.children), width: width)
    }

    private func renderBlocks(_ blocks: [Markup], width: Int) -> [String] {
        let blockOutputs: [(lines: [String], isBlank: Bool)] = blocks.map { block in
            let lines = renderBlock(block, width: width)
            let isBlank = lines.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return (lines, isBlank)
        }

        var lines: [String] = []
        var hasPreviousNonBlank = false
        for output in blockOutputs where !output.isBlank {
            if hasPreviousNonBlank, lines.last != "" {
                lines.append("")
            }
            lines.append(contentsOf: output.lines)
            hasPreviousNonBlank = true
        }
        return lines
    }

    private func renderInlineChildren(_ markup: Markup) -> String {
        return markup.children.map { renderInline($0) }.joined()
    }

    private func renderInline(_ markup: Markup) -> String {
        if let strong = markup as? Strong {
            return theme.bold(renderInlineChildren(strong)) + getDefaultStylePrefix()
        }
        if let emphasis = markup as? Emphasis {
            return theme.italic(renderInlineChildren(emphasis)) + getDefaultStylePrefix()
        }
        if let code = markup as? InlineCode {
            return theme.code(code.code) + getDefaultStylePrefix()
        }
        if let link = markup as? Link {
            let linkText = renderInlineChildren(link)
            if link.isAutolink {
                return theme.link(theme.underline(linkText)) + getDefaultStylePrefix()
            }
            if let destination = link.destination {
                return theme.link(theme.underline(linkText)) + theme.linkUrl(" (\(destination))") + getDefaultStylePrefix()
            }
            return theme.link(theme.underline(linkText)) + getDefaultStylePrefix()
        }
        if markup is LineBreak {
            return "\n"
        }
        if let soft = markup as? SoftBreak {
            return soft.plainText
        }
        if let del = markup as? Strikethrough {
            return theme.strikethrough(renderInlineChildren(del)) + getDefaultStylePrefix()
        }
        if let html = markup as? InlineHTML {
            return applyDefaultStyle(html.rawHTML)
        }

        if let text = (markup as? InlineMarkup)?.plainText {
            return applyDefaultStyle(text)
        }

        return ""
    }

    private struct ListLine {
        let text: String
        let isNested: Bool
    }

    private func renderList(listItems: [ListItem], ordered: Bool, startIndex: Int, depth: Int) -> [String] {
        var lines: [String] = []
        let indent = String(repeating: "  ", count: depth)

        for (index, item) in listItems.enumerated() {
            let bullet = ordered ? "\(startIndex + index). " : "- "
            let itemLines = renderListItem(item, depth: depth)

            if let first = itemLines.first {
                if first.isNested {
                    lines.append(first.text)
                } else {
                    lines.append(indent + theme.listBullet(bullet) + first.text)
                }

                for line in itemLines.dropFirst() {
                    if line.isNested {
                        lines.append(line.text)
                    } else {
                        lines.append(indent + "  " + line.text)
                    }
                }
            } else {
                lines.append(indent + theme.listBullet(bullet))
            }
        }

        return lines
    }

    private func renderListItem(_ item: ListItem, depth: Int) -> [ListLine] {
        var lines: [ListLine] = []

        for child in item.children {
            if let nestedUnordered = child as? UnorderedList {
                let nested = renderList(listItems: Array(nestedUnordered.listItems), ordered: false, startIndex: 1, depth: depth + 1)
                lines.append(contentsOf: nested.map { ListLine(text: $0, isNested: true) })
            } else if let nestedOrdered = child as? OrderedList {
                let nested = renderList(listItems: Array(nestedOrdered.listItems), ordered: true, startIndex: Int(nestedOrdered.startIndex), depth: depth + 1)
                lines.append(contentsOf: nested.map { ListLine(text: $0, isNested: true) })
            } else if let paragraph = child as? Paragraph {
                let text = renderInlineChildren(paragraph)
                lines.append(ListLine(text: text, isNested: false))
            } else if let codeBlock = child as? CodeBlock {
                lines.append(ListLine(text: theme.codeBlockBorder("```\(codeBlock.language ?? "")"), isNested: false))
                if let highlightCode = theme.highlightCode {
                    for line in highlightCode(codeBlock.code, codeBlock.language) {
                        lines.append(ListLine(text: "  \(line)", isNested: false))
                    }
                } else {
                    for line in codeBlock.code.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append(ListLine(text: "  \(theme.codeBlock(String(line)))", isNested: false))
                    }
                }
                lines.append(ListLine(text: theme.codeBlockBorder("```"), isNested: false))
            } else {
                let text = renderBlock(child, width: Int.max).joined(separator: "\n")
                if !text.isEmpty {
                    lines.append(ListLine(text: text, isNested: false))
                }
            }
        }

        return lines
    }

    private func wrapCellText(_ text: String, maxWidth: Int) -> [String] {
        return wrapTextWithAnsi(text, width: max(1, maxWidth))
    }

    private func renderTable(table: Table, availableWidth: Int) -> [String] {
        let headerCells = Array(table.head.cells)
        let rows = Array(table.body.rows)
        let numCols = max(headerCells.count, table.maxColumnCount)

        if numCols == 0 {
            return []
        }

        let borderOverhead = 3 * numCols + 1
        let minTableWidth = borderOverhead + numCols
        if availableWidth < minTableWidth {
            let fallbackText = renderTableFallback(table: table)
            return wrapTextWithAnsi(fallbackText, width: availableWidth)
        }

        var naturalWidths = Array(repeating: 0, count: numCols)
        for (index, cell) in headerCells.enumerated() {
            let text = renderInlineChildren(cell)
            if index < naturalWidths.count {
                naturalWidths[index] = max(naturalWidths[index], visibleWidth(text))
            }
        }
        for row in rows {
            for (index, cell) in row.cells.enumerated() {
                let text = renderInlineChildren(cell)
                if index < naturalWidths.count {
                    naturalWidths[index] = max(naturalWidths[index], visibleWidth(text))
                }
            }
        }

        let totalNaturalWidth = naturalWidths.reduce(0, +) + borderOverhead
        var columnWidths = naturalWidths

        if totalNaturalWidth > availableWidth {
            let availableForCells = availableWidth - borderOverhead
            if availableForCells <= numCols {
                let each = max(1, availableForCells / numCols)
                columnWidths = naturalWidths.map { _ in each }
            } else {
                let totalNatural = max(1, naturalWidths.reduce(0, +))
                let totalNaturalDouble = Double(totalNatural)
                let availableDouble = Double(availableForCells)
                columnWidths = naturalWidths.map { width in
                    let ratio = Double(width) / totalNaturalDouble
                    let computed = Int(ratio * availableDouble)
                    return max(1, computed)
                }

                let allocated = columnWidths.reduce(0, +)
                var remaining = availableForCells - allocated
                var idx = 0
                while remaining > 0 {
                    columnWidths[idx % columnWidths.count] += 1
                    remaining -= 1
                    idx += 1
                }
            }
        }

        var lines: [String] = []
        let topBorderCells = columnWidths.map { String(repeating: "─", count: $0) }
        lines.append("┌─" + topBorderCells.joined(separator: "─┬─") + "─┐")

        let headerCellLines = headerCells.enumerated().map { index, cell -> [String] in
            let text = renderInlineChildren(cell)
            return wrapCellText(text, maxWidth: columnWidths[index])
        }
        let headerLineCount = headerCellLines.map { $0.count }.max() ?? 0

        for lineIndex in 0..<headerLineCount {
            let parts = headerCellLines.enumerated().map { index, cellLines -> String in
                let text = cellLines.indices.contains(lineIndex) ? cellLines[lineIndex] : ""
                let padded = text + String(repeating: " ", count: max(0, columnWidths[index] - visibleWidth(text)))
                return theme.bold(padded)
            }
            lines.append("│ " + parts.joined(separator: " │ ") + " │")
        }

        let separatorCells = columnWidths.map { String(repeating: "─", count: $0) }
        lines.append("├─" + separatorCells.joined(separator: "─┼─") + "─┤")

        for row in rows {
            let rowCells = Array(row.cells)
            let rowCellLines: [[String]] = columnWidths.indices.map { index in
                let text = index < rowCells.count ? renderInlineChildren(rowCells[index]) : ""
                return wrapCellText(text, maxWidth: columnWidths[index])
            }
            let rowLineCount = rowCellLines.map { $0.count }.max() ?? 0

            for lineIndex in 0..<rowLineCount {
                let parts = rowCellLines.enumerated().map { index, cellLines -> String in
                    let text = cellLines.indices.contains(lineIndex) ? cellLines[lineIndex] : ""
                    return text + String(repeating: " ", count: max(0, columnWidths[index] - visibleWidth(text)))
                }
                lines.append("│ " + parts.joined(separator: " │ ") + " │")
            }
        }

        let bottomBorderCells = columnWidths.map { String(repeating: "─", count: $0) }
        lines.append("└─" + bottomBorderCells.joined(separator: "─┴─") + "─┘")

        return lines
    }

    private func renderTableFallback(table: Table) -> String {
        let headerCells = Array(table.head.cells).map { renderInlineChildren($0) }
        var lines: [String] = []
        if !headerCells.isEmpty {
            lines.append(headerCells.joined(separator: " | "))
        }
        for row in table.body.rows {
            let rowText = Array(row.cells).map { renderInlineChildren($0) }.joined(separator: " | ")
            lines.append(rowText)
        }
        return lines.joined(separator: "\n")
    }
}
