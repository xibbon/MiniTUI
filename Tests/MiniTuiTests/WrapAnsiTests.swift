import Testing
import MiniTui

@MainActor
@Test("underline styling does not apply before styled text")
func underlineDoesNotLead() {
    let underlineOn = "\u{001B}[4m"
    let underlineOff = "\u{001B}[24m"
    let url = "https://example.com/very/long/path/that/will/wrap"
    let text = "read this thread \(underlineOn)\(url)\(underlineOff)"

    let wrapped = wrapTextWithAnsi(text, width: 40)
    #expect(wrapped.first == "read this thread")
    if wrapped.count > 1 {
        #expect(wrapped[1].hasPrefix(underlineOn))
        #expect(wrapped[1].contains("https://"))
    }
}

@MainActor
@Test("no whitespace before underline reset")
func noWhitespaceBeforeUnderlineReset() {
    let underlineOn = "\u{001B}[4m"
    let underlineOff = "\u{001B}[24m"
    let text = "\(underlineOn)underlined text here \(underlineOff)more"

    let wrapped = wrapTextWithAnsi(text, width: 18)
    #expect(!wrapped[0].contains(" \(underlineOff)"))
}

@MainActor
@Test("trims trailing whitespace that exceeds width")
func trimsTrailingWhitespaceThatExceedsWidth() {
    let wrapped = wrapTextWithAnsi("  ", width: 1)
    #expect(visibleWidth(wrapped[0]) <= 1)
}

@MainActor
@Test("underline does not bleed to padding")
func underlineDoesNotBleed() {
    let underlineOn = "\u{001B}[4m"
    let underlineOff = "\u{001B}[24m"
    let url = "https://example.com/very/long/path/that/will/definitely/wrap"
    let text = "prefix \(underlineOn)\(url)\(underlineOff) suffix"

    let wrapped = wrapTextWithAnsi(text, width: 30)
    for line in wrapped.dropFirst().dropLast() {
        if line.contains(underlineOn) {
            #expect(line.hasSuffix(underlineOff))
            #expect(!line.hasSuffix("\u{001B}[0m"))
        }
    }
}

@MainActor
@Test("preserves background color across wrapped lines")
func preservesBackgroundColor() {
    let bgBlue = "\u{001B}[44m"
    let reset = "\u{001B}[0m"
    let text = "\(bgBlue)hello world this is blue background text\(reset)"

    let wrapped = wrapTextWithAnsi(text, width: 15)
    for line in wrapped {
        #expect(line.contains(bgBlue))
    }
    for line in wrapped.dropLast() {
        #expect(!line.hasSuffix("\u{001B}[0m"))
    }
}

@MainActor
@Test("resets underline but preserves background")
func resetsUnderlineButPreservesBackground() {
    let underlineOn = "\u{001B}[4m"
    let underlineOff = "\u{001B}[24m"
    let reset = "\u{001B}[0m"
    let text = "\u{001B}[41mprefix \(underlineOn)UNDERLINED_CONTENT_THAT_WRAPS\(underlineOff) suffix\(reset)"

    let wrapped = wrapTextWithAnsi(text, width: 20)
    for line in wrapped {
        let hasBg = line.contains("[41m") || line.contains(";41m") || line.contains("[41;")
        #expect(hasBg)
    }

    for line in wrapped.dropLast() {
        if (line.contains("[4m") || line.contains("[4;") || line.contains(";4m")), !line.contains(underlineOff) {
            #expect(line.hasSuffix(underlineOff))
            #expect(!line.hasSuffix("\u{001B}[0m"))
        }
    }
}

@MainActor
@Test("wraps plain text correctly")
func wrapsPlainText() {
    let text = "hello world this is a test"
    let wrapped = wrapTextWithAnsi(text, width: 10)
    #expect(wrapped.count > 1)
    for line in wrapped {
        #expect(visibleWidth(line) <= 10)
    }
}

@MainActor
@Test("preserves color codes across wraps")
func preservesColorCodes() {
    let red = "\u{001B}[31m"
    let reset = "\u{001B}[0m"
    let text = "\(red)hello world this is red\(reset)"

    let wrapped = wrapTextWithAnsi(text, width: 10)
    for line in wrapped.dropFirst() {
        #expect(line.hasPrefix(red))
    }
    for line in wrapped.dropLast() {
        #expect(!line.hasSuffix("\u{001B}[0m"))
    }
}
