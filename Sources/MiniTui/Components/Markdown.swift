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

/// Options that control source-preservation behavior in Markdown rendering.
public struct MarkdownOptions: Sendable {
    /// Preserve source backslashes before escaped punctuation. By default, Markdown escapes
    /// are normalized to their literal punctuation.
    public var preserveBackslashEscapes: Bool

    /// Render supported LaTeX math spans as Unicode text.
    public var renderLatex: Bool

    /// Apply these width-aware transforms in order before Markdown parsing.
    public var sourceTransforms: [MarkdownSourceTransform]

    public init(
        preserveBackslashEscapes: Bool = false,
        renderLatex: Bool = false,
        sourceTransforms: [MarkdownSourceTransform] = []
    ) {
        self.preserveBackslashEscapes = preserveBackslashEscapes
        self.renderLatex = renderLatex
        self.sourceTransforms = sourceTransforms
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
    private struct BlockKey: Hashable {
        let source: String
        let kind: String
        let nextKind: String
        let width: Int
    }

    private var renderedBlocks: [BlockKey: [String]] = [:]
    private var highlightedCode: [String: [String]] = [:]
    private var highlightedBytes = 0
    private var renderingLink = false
    private var renderingTable = false
    private struct InlineStyleContext {
        let applyText: (String) -> String
        let stylePrefix: String
    }

    private var text: String
    private let paddingX: Int
    private let paddingY: Int
    private let theme: MarkdownTheme
    private let defaultTextStyle: DefaultTextStyle?
    private let options: MarkdownOptions
    private var defaultStylePrefix: String?
    private var sourceText = ""
    private var cjkParserPadding: String?

    private var cachedText: String?
    private var cachedTransformedText: String?
    private var cachedRawDisplayMath: [String: String]?
    private var cachedWidth: Int?
    private var cachedLines: [String]?
    private var rawDisplayMath: [String: String] = [:]

    /// Create a Markdown component.
    public init(
        _ text: String,
        paddingX: Int,
        paddingY: Int,
        theme: MarkdownTheme,
        defaultTextStyle: DefaultTextStyle? = nil,
        options: MarkdownOptions = MarkdownOptions()
    ) {
        self.text = text
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.theme = theme
        self.defaultTextStyle = defaultTextStyle
        self.options = options
    }

    /// Update the Markdown text and invalidate cached lines.
    public func setText(_ text: String) {
        self.text = text
        clearRenderCache()
    }

    /// Clear cached render state.
    public func invalidate() {
        clearRenderCache()
        renderedBlocks.removeAll()
        highlightedCode.removeAll()
        highlightedBytes = 0
        defaultStylePrefix = nil
    }

    private func clearRenderCache() {
        cachedText = nil
        cachedTransformedText = nil
        cachedRawDisplayMath = nil
        cachedWidth = nil
        cachedLines = nil
        rawDisplayMath.removeAll()
    }

    /// Render the Markdown content into terminal lines.
    public func render(width: Int) -> [String] {
        // A component without caller-supplied transforms has deterministic source at this width.
        if options.sourceTransforms.isEmpty, let cachedLines,
           cachedText == text, cachedWidth == width {
            return cachedLines
        }
        let contentWidth = max(1, width - paddingX * 2)
        var transformedText = text
        var wideMathBlocks: [String: String] = [:]
        for transform in options.sourceTransforms {
            transformedText = transform(transformedText, contentWidth)
        }
        if options.renderLatex {
            let latex = transformMarkdownLatexForRendering(transformedText, width: contentWidth)
            transformedText = latex.source
            wideMathBlocks = latex.rawDisplayMath
        }

        if let cachedLines,
           cachedText == text,
           cachedTransformedText == transformedText,
           cachedRawDisplayMath == wideMathBlocks,
           cachedWidth == width {
            return cachedLines
        }

        if transformedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let result: [String] = []
            cachedText = text
            cachedTransformedText = transformedText
            cachedRawDisplayMath = wideMathBlocks
            cachedWidth = width
            cachedLines = result
            return result
        }

        let normalizedText = trimPartialClosingFence(
            escapeSingleTildeDelimiters(transformedText.replacingOccurrences(of: "\t", with: "   "))
        )
        let parserInput = MarkdownCJKParserInput(normalizedText)
        rawDisplayMath = wideMathBlocks
        sourceText = parserInput.source
        cjkParserPadding = parserInput.padding
        let document = MarkdownDocumentCache.shared.document(for: parserInput.source).document
        let blocks = Array(document.children)
        let sourceLines = parserInput.source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let previousBlocks = renderedBlocks
        var nextBlocks: [BlockKey: [String]] = [:]
        var cacheBytes = 0
        // Definitions outside a block can change a reference link in that block.
        let hasReferenceDefinitions = parserInput.source.range(
            of: #"(?m)^ {0,3}\[[^\]]+\]:"#, options: .regularExpression
        ) != nil

        let blockOutputs: [(lines: [String], isBlank: Bool)] = blocks.enumerated().map { index, block in
            let key = rawBlockSource(block, lines: sourceLines).map {
                BlockKey(source: $0, kind: String(describing: type(of: block)),
                         nextKind: index + 1 < blocks.count ? String(describing: type(of: blocks[index + 1])) : "",
                         width: contentWidth)
            }
            let hasRawMath = key?.source.contains("\u{E000}MiniTuiMath") == true
            let lines = key.flatMap { hasReferenceDefinitions || hasRawMath ? nil : previousBlocks[$0] }
                ?? renderBlock(block, width: contentWidth)
            if let key, !hasReferenceDefinitions, !hasRawMath, nextBlocks.count < 128 {
                let cost = key.source.utf8.count + lines.reduce(0) { $0 + $1.utf8.count }
                if cacheBytes + cost <= 1_048_576 {
                    nextBlocks[key] = lines
                    cacheBytes += cost
                }
            }
            let isBlank = lines.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return (lines, isBlank)
        }
        renderedBlocks = nextBlocks

        var renderedLines: [String] = []
        var hasPreviousNonBlank = false
        for output in blockOutputs where !output.isBlank {
            if hasPreviousNonBlank, renderedLines.last != "" {
                renderedLines.append("")
            }
            renderedLines.append(contentsOf: output.lines)
            hasPreviousNonBlank = true
        }
        // Remove trailing blank lines to avoid extra spacing after the last block element
        while let last = renderedLines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            renderedLines.removeLast()
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
        cachedTransformedText = transformedText
        cachedRawDisplayMath = wideMathBlocks
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

    private func getStylePrefix(_ style: (String) -> String) -> String {
        let sentinel = "\u{0000}"
        let styled = style(sentinel)
        guard let sentinelIndex = styled.firstIndex(of: "\u{0000}") else {
            return ""
        }
        return String(styled[..<sentinelIndex])
    }

    private func defaultInlineStyleContext() -> InlineStyleContext {
        InlineStyleContext(
            applyText: { [weak self] text in
                self?.applyDefaultStyle(text) ?? text
            },
            stylePrefix: getDefaultStylePrefix()
        )
    }

    private func applyTextWithNewlines(_ text: String, context: InlineStyleContext) -> String {
        text.components(separatedBy: "\n").map(context.applyText).joined(separator: "\n")
    }

    private func escapeSingleTildeDelimiters(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        result.reserveCapacity(text.count)

        for index in characters.indices {
            let character = characters[index]
            guard character == "~" else {
                result.append(character)
                continue
            }

            let previousIsTilde = index > characters.startIndex && characters[characters.index(before: index)] == "~"
            let nextIndex = characters.index(after: index)
            let nextIsTilde = nextIndex < characters.endIndex && characters[nextIndex] == "~"
            if previousIsTilde || nextIsTilde {
                result.append(character)
            } else {
                result += "\\~"
            }
        }

        return result
    }

    /// Remove a still-streaming partial closing fence from the final source line. Otherwise the
    /// parser treats it as code content, adding a transient row immediately before the border.
    private func trimPartialClosingFence(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let finalLine = lines.last,
              let finalMarker = fenceMarker(in: finalLine) else {
            return text
        }

        var openFence: (character: Character, length: Int)?
        for line in lines.dropLast() {
            guard let marker = fenceMarker(in: line), marker.length >= 3 else { continue }
            if let fence = openFence {
                if marker.character == fence.character, marker.length >= fence.length {
                    openFence = nil
                }
            } else {
                openFence = marker
            }
        }

        guard let fence = openFence,
              finalMarker.character == fence.character,
              finalMarker.length < fence.length,
              finalLine == String(repeating: String(finalMarker.character), count: finalMarker.length) else {
            return text
        }
        lines.removeLast()
        return lines.joined(separator: "\n")
    }

    private func fenceMarker(in line: String) -> (character: Character, length: Int)? {
        let trimmed = line.drop(while: { $0 == " " })
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == first }).count
        return (first, length)
    }

    private func removeTrailingStylePrefix(from text: String, stylePrefix: String) -> String {
        guard !stylePrefix.isEmpty else { return text }
        var result = text
        while result.hasSuffix(stylePrefix) {
            let start = result.index(result.endIndex, offsetBy: -stylePrefix.count)
            result.removeSubrange(start..<result.endIndex)
        }
        return result
    }

    private func renderBlock(_ block: Markup, width: Int, context: InlineStyleContext? = nil) -> [String] {
        if let heading = block as? Heading {
            let level = heading.level
            let headingStyle: (String) -> String
            if level == 1 {
                headingStyle = { [theme] text in theme.heading(theme.bold(theme.underline(text))) }
            } else {
                headingStyle = { [theme] text in theme.heading(theme.bold(text)) }
            }

            let context = InlineStyleContext(
                applyText: headingStyle,
                stylePrefix: getStylePrefix(headingStyle)
            )
            let headingText = renderInlineChildren(heading, context: context)
            if level >= 3 {
                return [headingStyle(String(repeating: "#", count: level) + " ") + headingText]
            } else if level == 2 {
                return [headingText]
            }
            return [headingText]
        }

        if let paragraph = block as? Paragraph {
            let children = Array(paragraph.children)
            if children.count == 1,
               let marker = (children[0] as? InlineMarkup)?.plainText,
               let raw = rawDisplayMath[marker] {
                return raw.components(separatedBy: "\n").map(applyDefaultStyle)
            }
            if let context {
                return [renderInlineChildren(paragraph, context: context)]
            }
            return [renderInlineChildren(paragraph)]
        }

        if let codeBlock = block as? CodeBlock {
            var lines: [String] = []
            lines.append(theme.codeBlockBorder("```\(codeBlock.language ?? "")"))
            let code = codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
            if let highlightCode = theme.highlightCode {
                let key = (codeBlock.language ?? "") + "\u{0000}" + code
                let highlighted = highlightedCode[key] ?? highlightCode(code, codeBlock.language)
                if highlightedCode[key] == nil, highlightedCode.count < 128 {
                    let cost = key.utf8.count + highlighted.reduce(0) { $0 + $1.utf8.count }
                    if highlightedBytes + cost <= 1_048_576 {
                        highlightedCode[key] = highlighted
                        highlightedBytes += cost
                    }
                }
                for line in highlighted {
                    lines.append("  \(line)")
                }
            } else {
                for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("  \(theme.codeBlock(String(line)))")
                }
            }
            lines.append(theme.codeBlockBorder("```"))
            return lines
        }

        if let list = block as? UnorderedList {
            return renderList(listItems: Array(list.listItems), ordered: false, startIndex: 1, depth: 0, context: context)
        }

        if let list = block as? OrderedList {
            return renderList(listItems: Array(list.listItems), ordered: true, startIndex: Int(list.startIndex), depth: 0, context: context)
        }

        if let table = block as? Table {
            return renderTable(table: table, availableWidth: width, context: context)
        }

        if let blockquote = block as? BlockQuote {
            let quoteStyle: (String) -> String = { [theme] text in theme.quote(text) }
            let quoteStylePrefix = getStylePrefix(quoteStyle)
            let quoteContext = InlineStyleContext(
                applyText: { text in text },
                stylePrefix: quoteStylePrefix
            )

            // Use renderBlocks (block-level traversal) so nested lists and code blocks
            // inside blockquotes are rendered correctly, not just inline paragraphs.
            // Reset style context to avoid parent style bleed-through into blockquote content.
            let savedDefaultStylePrefix = defaultStylePrefix
            defaultStylePrefix = ""
            let quoteLines = renderBlocks(Array(blockquote.children), width: max(1, width - 2), context: quoteContext)
            defaultStylePrefix = savedDefaultStylePrefix
            return quoteLines.map { line in
                let lineWithRestoredQuoteStyle = quoteStylePrefix.isEmpty
                    ? line
                    : line.replacingOccurrences(of: "\u{001B}[0m", with: "\u{001B}[0m\(quoteStylePrefix)")
                return theme.quoteBorder("│ ") + "\u{001B}[0m" + quoteStyle(lineWithRestoredQuoteStyle)
            }
        }

        if block is ThematicBreak {
            return [theme.hr(String(repeating: "─", count: min(width, 80)))]
        }

        if let html = block as? HTMLBlock {
            let remaining = stripHtmlComments(html.rawHTML).trimmingCharacters(in: .whitespacesAndNewlines)
            return remaining.isEmpty ? [] : [applyDefaultStyle(remaining)]
        }

        return renderBlocks(Array(block.children), width: width)
    }

    private func renderBlocks(_ blocks: [Markup], width: Int, context: InlineStyleContext? = nil) -> [String] {
        let blockOutputs: [(lines: [String], isBlank: Bool)] = blocks.map { block in
            let lines = renderBlock(block, width: width, context: context)
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
        // Remove trailing blank lines to avoid extra spacing after block elements
        while let last = lines.last, last.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeLast()
        }
        return lines
    }

    private func renderInlineChildren(_ markup: Markup) -> String {
        renderInlineChildren(markup, context: defaultInlineStyleContext())
    }

    private func renderInlineChildren(_ markup: Markup, context: InlineStyleContext) -> String {
        var rendered = ""
        var dropSpace = false
        for child in markup.children {
            var piece = renderInline(child, context: context)
            if dropSpace, let space = piece.firstIndex(of: " "),
               stripAnsiCodes(String(piece[..<space])).isEmpty {
                piece.remove(at: space)
            }
            dropSpace = child is InlineHTML && piece.isEmpty && rendered.hasSuffix(" ")
            rendered += piece
        }
        return removeTrailingStylePrefix(from: rendered, stylePrefix: context.stylePrefix)
    }

    private func renderInline(_ markup: Markup, context: InlineStyleContext) -> String {
        if let strong = markup as? Strong {
            return theme.bold(renderInlineChildren(strong, context: context)) + context.stylePrefix
        }
        if let emphasis = markup as? Emphasis {
            return theme.italic(renderInlineChildren(emphasis, context: context)) + context.stylePrefix
        }
        if let code = markup as? InlineCode {
            return theme.code(code.code) + context.stylePrefix
        }
        if let link = markup as? Link {
            let previousRenderingLink = renderingLink
            renderingLink = true
            let linkText = renderInlineChildren(link, context: context)
            renderingLink = previousRenderingLink
            // v0.67.6: when the terminal advertises OSC 8 support (and isn't running under tmux/
            // screen, where the sequence is silently dropped), wrap the styled link text with
            // the OSC 8 escape so the link is clickable. Otherwise fall back to the legacy
            // "text (url)" rendering so the URL doesn't disappear on terminals that swallow OSC 8.
            let supportsHyperlink = getCapabilities().hyperlinks
            if link.isAutolink, let raw = sourceText(for: link), !raw.hasPrefix("<"),
               let punctuation = raw.firstIndex(where: isCJKPunctuation),
               let destination = link.destination {
                let prefix = String(raw[..<punctuation])
                let suffix = String(raw[punctuation...])
                let target = destination.hasPrefix("http://") && prefix.hasPrefix("www.")
                    ? "http://" + prefix : prefix
                let styled = theme.link(theme.underline(context.applyText(prefix)))
                return (supportsHyperlink ? hyperlink(styled, url: target) : styled)
                    + context.applyText(suffix) + context.stylePrefix
            }
            if link.isAutolink {
                if supportsHyperlink, let destination = link.destination {
                    return hyperlink(theme.link(theme.underline(linkText)), url: destination) + context.stylePrefix
                }
                return theme.link(theme.underline(linkText)) + context.stylePrefix
            }
            if let destination = link.destination {
                if supportsHyperlink {
                    return hyperlink(theme.link(theme.underline(linkText)), url: destination) + context.stylePrefix
                }
                return theme.link(theme.underline(linkText)) + theme.linkUrl(" (\(destination))") + context.stylePrefix
            }
            return theme.link(theme.underline(linkText)) + context.stylePrefix
        }
        if markup is LineBreak {
            return "\n"
        }
        if let soft = markup as? SoftBreak {
            return soft.plainText
        }
        if let del = markup as? Strikethrough {
            return theme.strikethrough(renderInlineChildren(del, context: context)) + context.stylePrefix
        }
        if let html = markup as? InlineHTML {
            if html.rawHTML == cjkParserPadding { return "" }
            return applyTextWithNewlines(stripHtmlComments(html.rawHTML), context: context)
        }

        if let text = (markup as? InlineMarkup)?.plainText {
            let renderedText = options.preserveBackslashEscapes
                ? sourceText(for: markup) ?? text
                : text
            return renderingLink ? applyTextWithNewlines(renderedText, context: context)
                : renderBareURLs(renderedText, context: context)
        }

        return ""
    }

    /// Swift Markdown retains source ranges for parsed text nodes. Use that source when asked
    /// to preserve escaping; otherwise its `Text.string` intentionally normalizes escapes.
    private func sourceText(for markup: Markup) -> String? {
        guard let range = markup.range,
              range.lowerBound.line == range.upperBound.line else {
            return nil
        }

        let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false)
        let lineIndex = range.lowerBound.line - 1
        guard lines.indices.contains(lineIndex) else { return nil }
        let line = lines[lineIndex]
        let startOffset = range.lowerBound.column - 1
        let endOffset = range.upperBound.column - 1
        guard startOffset >= 0, endOffset >= startOffset,
              startOffset <= line.utf8.count, endOffset <= line.utf8.count else {
            return nil
        }

        let start = line.utf8.index(line.utf8.startIndex, offsetBy: startOffset)
        let end = line.utf8.index(line.utf8.startIndex, offsetBy: endOffset)
        guard let stringStart = String.Index(start, within: line),
              let stringEnd = String.Index(end, within: line) else {
            return nil
        }
        let source = String(line[stringStart..<stringEnd])
        if source.contains("\\") {
            return source
        }

        // cmark can place the escape character immediately before the text node's range.
        // Keep it when it escapes Markdown punctuation instead of treating a literal backslash
        // from an earlier text node as part of this node.
        if startOffset > 0 {
            let before = line.utf8.index(line.utf8.startIndex, offsetBy: startOffset - 1)
            if line.utf8[before] == 0x5C, let first = source.first, isMarkdownEscapable(first) {
                return "\\" + source
            }
        }
        return source
    }

    private func rawBlockSource(_ block: Markup, lines: [String]) -> String? {
        guard let range = block.range,
              range.lowerBound.line > 0, range.upperBound.line >= range.lowerBound.line,
              lines.indices.contains(range.lowerBound.line - 1),
              lines.indices.contains(range.upperBound.line - 1) else { return nil }
        var parts: [String] = []
        for lineNumber in range.lowerBound.line...range.upperBound.line {
            let line = lines[lineNumber - 1]
            let start = lineNumber == range.lowerBound.line ? range.lowerBound.column - 1 : 0
            let end = lineNumber == range.upperBound.line ? range.upperBound.column - 1 : line.utf8.count
            guard start >= 0, end >= start, end <= line.utf8.count else { return nil }
            let first = line.utf8.index(line.utf8.startIndex, offsetBy: start)
            let last = line.utf8.index(line.utf8.startIndex, offsetBy: end)
            guard let firstIndex = String.Index(first, within: line),
                  let lastIndex = String.Index(last, within: line) else { return nil }
            parts.append(String(line[firstIndex..<lastIndex]))
        }
        return parts.joined(separator: "\n")
    }

    private func isMarkdownEscapable(_ character: Character) -> Bool {
        "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".contains(character)
    }

    private func renderBareURLs(_ text: String, context: InlineStyleContext) -> String {
        var remaining = text
        var output = ""
        while let match = remaining.range(of: #"(?:https?://|www\.)[^\s<>]+"#, options: .regularExpression) {
            output += applyTextWithNewlines(String(remaining[..<match.lowerBound]), context: context)
            let candidate = String(remaining[match])
            // Keep the existing ASCII table-cell rendering and its width accounting.
            if renderingTable, candidate.unicodeScalars.allSatisfy({ $0.value < 128 }) {
                output += context.applyText(candidate)
                remaining = String(remaining[match.upperBound...])
                continue
            }
            let boundary = candidate.firstIndex(where: isCJKPunctuation) ?? candidate.endIndex
            var url = String(candidate[..<boundary])
            while let last = url.last, ".,;:!?".contains(last) { url.removeLast() }
            if url.isEmpty {
                output += context.applyText(candidate)
            } else {
                let target = url.hasPrefix("www.") ? "http://" + url : url
                let styled = theme.link(theme.underline(context.applyText(url)))
                output += getCapabilities().hyperlinks ? hyperlink(styled, url: target) : styled
                output += context.applyText(String(candidate.dropFirst(url.count)))
            }
            remaining = String(remaining[match.upperBound...])
        }
        return output + applyTextWithNewlines(remaining, context: context)
    }

    private struct ListLine {
        let text: String
        let isNested: Bool
    }

    private func renderList(listItems: [ListItem], ordered: Bool, startIndex: Int, depth: Int, context: InlineStyleContext? = nil) -> [String] {
        var lines: [String] = []
        let indent = String(repeating: "  ", count: depth)

        for (index, item) in listItems.enumerated() {
            let bullet = ordered ? "\(startIndex + index). " : "- "
            let itemLines = renderListItem(item, depth: depth, context: context)

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

    private func renderListItem(_ item: ListItem, depth: Int, context: InlineStyleContext? = nil) -> [ListLine] {
        var lines: [ListLine] = []

        for child in item.children {
            if let nestedUnordered = child as? UnorderedList {
                let nested = renderList(listItems: Array(nestedUnordered.listItems), ordered: false, startIndex: 1, depth: depth + 1, context: context)
                lines.append(contentsOf: nested.map { ListLine(text: $0, isNested: true) })
            } else if let nestedOrdered = child as? OrderedList {
                let nested = renderList(listItems: Array(nestedOrdered.listItems), ordered: true, startIndex: Int(nestedOrdered.startIndex), depth: depth + 1, context: context)
                lines.append(contentsOf: nested.map { ListLine(text: $0, isNested: true) })
            } else if let paragraph = child as? Paragraph {
                let text = context.map { renderInlineChildren(paragraph, context: $0) } ?? renderInlineChildren(paragraph)
                lines.append(ListLine(text: text, isNested: false))
            } else if let codeBlock = child as? CodeBlock {
                lines.append(ListLine(text: theme.codeBlockBorder("```\(codeBlock.language ?? "")"), isNested: false))
                let code = codeBlock.code.hasSuffix("\n") ? String(codeBlock.code.dropLast()) : codeBlock.code
                if let highlightCode = theme.highlightCode {
                    for line in highlightCode(code, codeBlock.language) {
                        lines.append(ListLine(text: "  \(line)", isNested: false))
                    }
                } else {
                    for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
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

    private func wrapCellText(_ text: String, maxWidth: Int, stylePrefix: String) -> [String] {
        let lines = wrapTextWithAnsi(text, width: max(1, maxWidth))
        return lines.enumerated().map { index, line in
            line + (index < lines.count - 1 ? "\u{001B}[22;23;24;25;27;28;29;39m" : "") + stylePrefix
        }
    }

    private func renderTable(table: Table, availableWidth: Int, context: InlineStyleContext?) -> [String] {
        let previousRenderingTable = renderingTable
        renderingTable = true
        defer { renderingTable = previousRenderingTable }
        let context = context ?? defaultInlineStyleContext()
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
            let text = renderInlineChildren(cell, context: context)
            if index < naturalWidths.count {
                naturalWidths[index] = max(naturalWidths[index], visibleWidth(text))
            }
        }
        for row in rows {
            for (index, cell) in row.cells.enumerated() {
                let text = renderInlineChildren(cell, context: context)
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
            let text = renderInlineChildren(cell, context: context)
            return wrapCellText(text, maxWidth: columnWidths[index], stylePrefix: context.stylePrefix)
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
                let text = index < rowCells.count ? renderInlineChildren(rowCells[index], context: context) : ""
                return wrapCellText(text, maxWidth: columnWidths[index], stylePrefix: context.stylePrefix)
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

private func stripHtmlComments(_ html: String) -> String {
    var remaining = html
    while let range = remaining.range(of: #"<!--[\s\S]*?(?:-->|$)"#, options: .regularExpression) {
        remaining.removeSubrange(range)
    }
    return remaining
}
