import Foundation

public struct AltScreenSearchSegment: Sendable, Equatable {
    public var row: Int
    public var startCol: Int
    public var endCol: Int

    public init(row: Int, startCol: Int, endCol: Int) {
        self.row = row
        self.startCol = startCol
        self.endCol = endCol
    }
}

public struct AltScreenSearchMatch: Sendable, Equatable {
    public var segments: [AltScreenSearchSegment]

    public init(segments: [AltScreenSearchSegment]) { self.segments = segments }
}

public struct AltScreenSearchResult: Sendable, Equatable {
    public var matches: [AltScreenSearchMatch]
    public var changed: Bool

    public init(matches: [AltScreenSearchMatch], changed: Bool) {
        self.matches = matches
        self.changed = changed
    }
}

private struct SearchSourceSpan {
    var textStart: Int
    var textEnd: Int
    var row: Int
    var startCol: Int
    var endCol: Int
    var linearColumns: Bool
}

private struct SearchCorpus {
    var text: String
    var spans: [SearchSourceSpan]
}

// Match ECMAScript whitespace, including BOM and excluding NEL.
private func isSearchWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.value {
    case 0x0009...0x000D, 0x0020, 0x00A0, 0x1680, 0x2000...0x200A,
         0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
        return true
    default:
        return false
    }
}

private func normalizeQuery(_ query: String) -> String {
    var result = ""
    var separator = false
    for scalar in query.unicodeScalars {
        if isSearchWhitespace(scalar) {
            if !result.isEmpty { separator = true }
        } else {
            if separator { result += " " }
            separator = false
            result.unicodeScalars.append(scalar)
        }
    }
    return result
}

private func buildSearchCorpus(_ lines: [String]) -> SearchCorpus {
    var chunks: [String] = []
    var spans: [SearchSourceSpan] = []
    var textLength = 0
    var pendingSeparator = false

    func append(_ text: String, row: Int, column: Int, width: Int, linear: Bool) {
        if pendingSeparator {
            chunks.append(" ")
            textLength += 1
            pendingSeparator = false
        }
        chunks.append(text)
        let length = text.utf16.count
        spans.append(SearchSourceSpan(
            textStart: textLength, textEnd: textLength + length,
            row: row, startCol: column, endCol: column + width, linearColumns: linear
        ))
        textLength += length
    }

    for (row, source) in lines.enumerated() {
        let line = stripTerminalSequences(source)
        var column = 0
        if line.utf8.allSatisfy({ (0x20...0x7E).contains($0) }) {
            let bytes = Array(line.utf8)
            var index = 0
            while index < bytes.count {
                if bytes[index] == 0x20 {
                    if textLength > 0 { pendingSeparator = true }
                    column += 1
                    index += 1
                    continue
                }
                var end = index + 1
                while end < bytes.count, bytes[end] != 0x20 { end += 1 }
                let text = String(decoding: bytes[index..<end], as: UTF8.self)
                append(text, row: row, column: column, width: end - index, linear: true)
                column += end - index
                index = end
            }
        } else {
            for grapheme in line {
                let text = String(grapheme)
                let width = visibleWidth(text)
                if text.unicodeScalars.allSatisfy(isSearchWhitespace) {
                    if textLength > 0 { pendingSeparator = true }
                    column += width
                    continue
                }
                append(text, row: row, column: column, width: width, linear: false)
                column += width
            }
        }
        if textLength > 0 { pendingSeparator = true }
    }
    return SearchCorpus(text: chunks.joined(), spans: spans)
}

private func findSearchCorpusMatches(_ corpus: SearchCorpus, query: String) -> [AltScreenSearchMatch] {
    guard !query.isEmpty else { return [] }
    var matches: [AltScreenSearchMatch] = []
    var spanIndex = 0
    var searchStart = corpus.text.startIndex
    let queryScalars = Array(query.unicodeScalars)
    while searchStart < corpus.text.endIndex,
          let range = corpus.text.range(of: query, options: [.caseInsensitive, .literal],
                                        range: searchStart..<corpus.text.endIndex) {
        // Foundation also permits multi-scalar case expansions. JavaScript's /iu
        // uses simple folding, so check each scalar before accepting a candidate.
        let candidateScalars = Array(corpus.text[range].unicodeScalars)
        let simpleFoldMatch = candidateScalars.count == queryScalars.count &&
            zip(candidateScalars, queryScalars).allSatisfy {
                String($0).compare(String($1), options: [.caseInsensitive, .literal]) == .orderedSame
            }
        guard simpleFoldMatch else {
            searchStart = corpus.text.unicodeScalars.index(after: range.lowerBound)
            continue
        }
        let start = range.lowerBound.utf16Offset(in: corpus.text)
        let end = range.upperBound.utf16Offset(in: corpus.text)
        searchStart = range.upperBound
        while spanIndex < corpus.spans.count, corpus.spans[spanIndex].textEnd <= start { spanIndex += 1 }
        var segments: [AltScreenSearchSegment] = []
        for span in corpus.spans[spanIndex...] {
            if span.textStart >= end { break }
            if span.textEnd <= start { continue }
            let startCol = span.linearColumns ? span.startCol + max(start, span.textStart) - span.textStart : span.startCol
            let endCol = span.linearColumns ? span.startCol + min(end, span.textEnd) - span.textStart : span.endCol
            if let previous = segments.last, previous.row == span.row, startCol <= previous.endCol {
                segments[segments.count - 1].endCol = max(previous.endCol, endCol)
            } else {
                segments.append(AltScreenSearchSegment(row: span.row, startCol: startCol, endCol: endCol))
            }
        }
        while spanIndex < corpus.spans.count, corpus.spans[spanIndex].textEnd <= end { spanIndex += 1 }
        if !segments.isEmpty { matches.append(AltScreenSearchMatch(segments: segments)) }
    }
    return matches
}

/// Cache the corpus and results until the transcript or normalized query changes.
@MainActor
public final class AltScreenSearchIndex {
    private var sourceLines: [String]?
    private var corpus: SearchCorpus?
    private var normalizedQuery: String?
    private var matches: [AltScreenSearchMatch] = []

    public init() {}

    public func search(lines: [String], query: String) -> AltScreenSearchResult {
        // Swift String equality includes canonical equivalence. Upstream compares
        // the rendered code units, so compare UTF-8 to detect every source change.
        let sourceChanged = sourceLines.map { previous in
            previous.count != lines.count || zip(previous, lines).contains { !$0.utf8.elementsEqual($1.utf8) }
        } ?? true
        if sourceChanged || corpus == nil {
            sourceLines = lines
            corpus = buildSearchCorpus(lines)
        }
        let normalized = normalizeQuery(query)
        let queryChanged = normalizedQuery.map { !$0.utf8.elementsEqual(normalized.utf8) } ?? true
        let changed = sourceChanged || queryChanged
        if changed {
            normalizedQuery = normalized
            if let corpus { matches = findSearchCorpusMatches(corpus, query: normalized) }
        }
        return AltScreenSearchResult(matches: matches, changed: changed)
    }
}

public func findAltScreenSearchMatches(lines: [String], query: String) -> [AltScreenSearchMatch] {
    let normalized = normalizeQuery(query)
    return normalized.isEmpty ? [] : findSearchCorpusMatches(buildSearchCorpus(lines), query: normalized)
}

public func getAltScreenSearchMatchKey(_ match: AltScreenSearchMatch) -> String {
    guard let first = match.segments.first, let last = match.segments.last else { return "" }
    return "\(first.row):\(first.startCol):\(last.row):\(last.endCol)"
}

@MainActor
public final class AltScreenSearchComponent: Focusable {
    private let input = Input(options: InputOptions(
        prompt: " ", placeholder: "Find in transcript",
        placeholderStyle: { "\u{001B}[2m\($0)\u{001B}[22m" }
    ))
    private let onQueryChange: (String) -> Void
    private let navigationButtonStyle: (String, Bool) -> String
    private var resultCount = 0
    private var resultIndex = -1
    private var previousButtonStart = -1
    private var previousButtonEnd = -1
    private var nextButtonStart = -1
    private var nextButtonEnd = -1
    private var hoveredNavigationDirection: Int?

    public var focused = false {
        didSet { input.focused = focused }
    }

    public init(onQueryChange: @escaping (String) -> Void,
                navigationButtonStyle: @escaping (String, Bool) -> String = { text, _ in text }) {
        self.onQueryChange = onQueryChange
        self.navigationButtonStyle = navigationButtonStyle
    }

    public func setResult(index: Int, count: Int) {
        resultIndex = index
        resultCount = count
    }

    public func getNavigationDirectionAt(row: Int, column: Int) -> Int? {
        guard row == 2 else { return nil }
        if column >= previousButtonStart, column < previousButtonEnd { return -1 }
        if column >= nextButtonStart, column < nextButtonEnd { return 1 }
        return nil
    }

    @discardableResult
    public func setHoveredNavigationDirection(_ direction: Int?) -> Bool {
        guard direction != hoveredNavigationDirection else { return false }
        hoveredNavigationDirection = direction
        return true
    }

    public func handleInput(_ data: String) {
        let previous = input.getValue()
        input.handleInput(data)
        let query = input.getValue()
        if !query.utf8.elementsEqual(previous.utf8) { onQueryChange(query) }
    }

    public func invalidate() { input.invalidate() }

    public func render(width: Int) -> [String] {
        let safeWidth = max(1, width)
        let innerWidth = max(0, safeWidth - 2)
        func formatKey(_ key: String?) -> String {
            guard let key else { return "Unbound" }
            return key.components(separatedBy: "+").map { part in
                #if os(macOS)
                if part.lowercased() == "alt" { return "Option" }
                #endif
                return part.prefix(1).uppercased() + part.dropFirst()
            }.joined(separator: "+")
        }
        let keybindings = getKeybindings()
        let previousKey = formatKey(keybindings.getKeys(TUIKeybinding.altScreenSearchPrevious).first)
        let nextKey = formatKey(keybindings.getKeys(TUIKeybinding.altScreenSearchNext).first)
        let query = input.getValue()
        let result = query.isEmpty ? "" : resultCount == 0 ? "No matches" : "\(resultIndex + 1)/\(resultCount)"
        let visibleResult = truncateToWidth(result, maxWidth: max(0, innerWidth - 3), ellipsis: "")
        let resultText = visibleResult.isEmpty ? "" : "\u{001B}[2m \(visibleResult) \u{001B}[22m"
        let inputWidth = max(0, innerWidth - visibleWidth(resultText))
        let inputLine = truncateToWidth(input.render(width: max(1, inputWidth)).first ?? "", maxWidth: inputWidth, ellipsis: "")
        let content = inputLine + String(repeating: " ", count: max(0, inputWidth - visibleWidth(inputLine))) + resultText

        var previousButton = "↑ \(previousKey)"
        var nextButton = "↓ \(nextKey)"
        var separator = " · "
        let availableControlsWidth = max(0, innerWidth - 3)
        var controlsWidth = visibleWidth(previousButton) + visibleWidth(separator) + visibleWidth(nextButton)
        if controlsWidth > availableControlsWidth {
            previousButton = "↑"
            nextButton = "↓"
            separator = " "
            controlsWidth = 3
        }
        let showButtons = controlsWidth <= availableControlsWidth
        let renderedButtons = showButtons ?
            navigationButtonStyle(previousButton, hoveredNavigationDirection == -1) + separator +
            navigationButtonStyle(nextButton, hoveredNavigationDirection == 1) : ""
        let outerGapsWidth = showButtons ? 2 : 0
        let rightRuleWidth = !renderedButtons.isEmpty && innerWidth > controlsWidth + outerGapsWidth ? 1 : 0
        let leftRuleWidth = max(0, innerWidth - (showButtons ? controlsWidth : 0) - outerGapsWidth - rightRuleWidth)
        let previousStart = 1 + leftRuleWidth + 1
        previousButtonStart = showButtons ? previousStart : -1
        previousButtonEnd = showButtons ? previousStart + visibleWidth(previousButton) : -1
        nextButtonStart = showButtons ? previousButtonEnd + visibleWidth(separator) : -1
        nextButtonEnd = showButtons ? nextButtonStart + visibleWidth(nextButton) : -1
        if safeWidth == 1 { return ["┌", "│", "└"] }
        let gap = renderedButtons.isEmpty ? "" : " "
        return [
            "┌" + String(repeating: "─", count: innerWidth) + "┐",
            "│" + content + "│",
            "└" + String(repeating: "─", count: leftRuleWidth) + gap + renderedButtons + gap +
                String(repeating: "─", count: rightRuleWidth) + "┘",
        ]
    }
}
