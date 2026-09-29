import Testing
@testable import MiniTui

@Suite("Visible width escape scan")
struct VisibleWidthScanTests {
    @Test("styled ASCII, tabs, and terminal escapes")
    func styledASCII() {
        #expect(visibleWidth("\u{001B}[31mhello\u{001B}[39m") == 5)
        #expect(visibleWidth("a\tb") == 5)
        #expect(visibleWidth("\u{001B}]8;;https://example.com\u{0007}link\u{001B}]8;;\u{0007}") == 4)
        #expect(visibleWidth("\u{001B}_Gpayload\u{001B}\\text") == 4)
        #expect(visibleWidth("\u{001B}[31m日本語\u{001B}[39m") == 6)
    }

    @Test("incomplete escapes stay in the visible text")
    func incomplete() {
        #expect(stripTerminalSequences("a\u{001B}[31") == "a\u{001B}[31")
        #expect(visibleWidth("\u{001B}[31") == 3)
        #expect(visibleWidth("a\u{001B}") == 1)
    }

    @Test("offset based extraction and tracker keep their results")
    func extraction() {
        let text = "界\u{001B}[48;5;42mred\u{001B}[49m"
        #expect(extractAnsiCode(text, at: 1)?.code == "\u{001B}[48;5;42m")
        #expect(extractAnsiCode(text, at: 1)?.length == 10)
        #expect(getActiveBackgroundAnsi("\u{001B}[48;5;42mred") == "\u{001B}[48;5;42m")
        #expect(getActiveBackgroundAnsi(text) == "")
    }
}
