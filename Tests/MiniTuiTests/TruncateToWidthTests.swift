import Testing
@testable import MiniTui

@Test("normalizeTerminalOutput expands visible tabs")
func normalizeTerminalOutputExpandsVisibleTabs() {
    #expect(normalizeTerminalOutput("a\tb") == "a   b")
}

@Test("normalizeTerminalOutput preserves tabs inside ANSI sequences")
func normalizeTerminalOutputPreservesAnsiTabs() {
    let text = "\u{001B}[3\t1mred\u{001B}[0m\ttext"
    #expect(normalizeTerminalOutput(text) == "\u{001B}[3\t1mred\u{001B}[0m   text")
}

@Test("normalizeTerminalOutput leaves strings without tabs unchanged")
func normalizeTerminalOutputLeavesTablessStringsUnchanged() {
    let text = "\u{001B}[31mred\u{001B}[0m"
    #expect(normalizeTerminalOutput(text) == text)
}

@Test("truncateToWidth keeps large unicode output within width")
func truncateLargeUnicodeWithinWidth() {
    let text = String(repeating: "🙂界", count: 100_000)
    let truncated = truncateToWidth(text, maxWidth: 40, ellipsis: "…")

    #expect(visibleWidth(truncated) <= 40)
    #expect(truncated.hasSuffix("…\u{001B}[0m"))
}

@Test("truncateToWidth preserves ANSI styling and brackets ellipsis with resets")
func truncatePreservesAnsiAndResetsEllipsis() {
    let text = "\u{001B}[31m" + String(repeating: "hello ", count: 1_000) + "\u{001B}[0m"
    let truncated = truncateToWidth(text, maxWidth: 20, ellipsis: "…")

    #expect(visibleWidth(truncated) <= 20)
    #expect(truncated.contains("\u{001B}[31m"))
    #expect(truncated.hasSuffix("\u{001B}[0m…\u{001B}[0m"))
}

@Test("truncateToWidth handles malformed ANSI prefixes without hanging")
func truncateHandlesMalformedAnsiPrefix() {
    let text = "abc\u{001B}not-ansi " + String(repeating: "🙂", count: 1_000)
    let truncated = truncateToWidth(text, maxWidth: 20, ellipsis: "…")

    #expect(visibleWidth(truncated) <= 20)
}

@Test("truncateToWidth clips wide ellipsis safely")
func truncateClipsWideEllipsisSafely() {
    #expect(truncateToWidth("abcdef", maxWidth: 1, ellipsis: "🙂") == "")
    #expect(truncateToWidth("abcdef", maxWidth: 2, ellipsis: "🙂") == "\u{001B}[0m🙂\u{001B}[0m")
    #expect(visibleWidth(truncateToWidth("abcdef", maxWidth: 2, ellipsis: "🙂")) <= 2)
}

@Test("truncateToWidth returns fitting text when ellipsis is too wide")
func truncateReturnsFittingTextWhenEllipsisTooWide() {
    #expect(truncateToWidth("a", maxWidth: 2, ellipsis: "🙂") == "a")
    #expect(truncateToWidth("界", maxWidth: 2, ellipsis: "🙂") == "界")
}

@Test("truncateToWidth pads truncated output")
func truncatePadsOutput() {
    let truncated = truncateToWidth("🙂界🙂界🙂界", maxWidth: 8, ellipsis: "…", pad: true)
    #expect(visibleWidth(truncated) == 8)
}

@Test("truncateToWidth adds trailing reset without ellipsis")
func truncateAddsTrailingResetWithoutEllipsis() {
    let truncated = truncateToWidth("\u{001B}[31m" + String(repeating: "hello", count: 100), maxWidth: 10, ellipsis: "")
    #expect(visibleWidth(truncated) <= 10)
    #expect(truncated.hasSuffix("\u{001B}[0m"))
}

@Test("truncateToWidth keeps contiguous prefix")
func truncateKeepsContiguousPrefix() {
    let truncated = truncateToWidth("🙂\t界 \u{001B}_abc\u{0007}", maxWidth: 7, ellipsis: "…", pad: true)
    #expect(truncated == "🙂\t\u{001B}[0m…\u{001B}[0m ")
}

@Test("truncateToWidth closes an active OSC 8 hyperlink")
func truncateClosesActiveHyperlink() {
    let open = "\u{001B}]8;;https://example.com\u{001B}\\"
    let truncated = truncateToWidth(open + "linked text that is too long", maxWidth: 8, ellipsis: "…")

    #expect(truncated.contains(osc8HyperlinkCloseStringTerminator + "\u{001B}[0m…"))
    #expect(visibleWidth(truncated) == 8)
}

@Test("visibleWidth follows upstream spacing-mark cell accounting")
func visibleWidthHandlesIndicThaiAndMyanmarClusters() {
    // v0.84.1 counts the conjunct consonant and spacing vowel as terminal cells.
    #expect(visibleWidth("क्षि") == 3)
    #expect(visibleWidth("र्क") == 2)
    #expect(visibleWidth("🙂") == 2)
    #expect(visibleWidth("界") == 2)
    #expect(visibleWidth("ำ") == 1)
    #expect(visibleWidth("กำ") == 2)
    #expect(visibleWidth("ကာ") == 2)
    #expect(visibleWidth("ကို") == 1)
}

@Test("stripTerminalSequences removes CSI OSC and APC")
func stripsTerminalSequences() {
    let input = "a\u{001B}[31mb\u{001B}[0mc"
        + "\u{001B}]8;;https://example.com\u{001B}\\d\u{001B}]8;;\u{001B}\\"
        + "\u{001B}_Gpayload\u{0007}e"
    #expect(stripTerminalSequences(input) == "abcde")
}

@Test("getGraphemeCellRange finds wide and combining graphemes")
func graphemeCellRanges() {
    let line = "a\u{001B}[31m界\u{001B}[0me\u{0301}z"
    #expect(getGraphemeCellRange(line: line, column: 0) == GraphemeCellRange(start: 0, end: 1))
    #expect(getGraphemeCellRange(line: line, column: 1) == GraphemeCellRange(start: 1, end: 3))
    #expect(getGraphemeCellRange(line: line, column: 2) == GraphemeCellRange(start: 1, end: 3))
    #expect(getGraphemeCellRange(line: line, column: 3) == GraphemeCellRange(start: 3, end: 4))
    #expect(getGraphemeCellRange(line: line, column: 4) == GraphemeCellRange(start: 4, end: 5))
    #expect(getGraphemeCellRange(line: line, column: 5) == nil)
}
