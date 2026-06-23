import Testing
import MiniTui

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
