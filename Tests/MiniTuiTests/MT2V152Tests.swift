import Foundation
import Testing
import os
@testable import MiniTui

@MainActor
private func mt2Plain(_ source: String, width: Int = 60, options: MarkdownOptions = .init()) -> [String] {
    Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme, options: options)
        .render(width: width).map { stripAnsiCodes($0).trimmingCharacters(in: .whitespaces) }
}

private func mt2CountingTheme(_ calls: OSAllocatedUnfairLock<[String]>) -> MarkdownTheme {
    MarkdownTheme(
        heading: { Ansi.wrap(["1", "36"], $0) }, link: { Ansi.blue($0) },
        linkUrl: { Ansi.dim($0) }, code: { Ansi.yellow($0) },
        codeBlock: { Ansi.green($0) }, codeBlockBorder: { Ansi.dim($0) },
        quote: { Ansi.italic($0) }, quoteBorder: { Ansi.dim($0) }, hr: { Ansi.dim($0) },
        listBullet: { Ansi.cyan($0) }, bold: { Ansi.bold($0) },
        italic: { Ansi.italic($0) }, strikethrough: { Ansi.strikethrough($0) },
        underline: { Ansi.underline($0) },
        highlightCode: { code, language in
            calls.withLock { $0.append("\(language ?? ""):\(code)") }
            return code.components(separatedBy: "\n").map { Ansi.green($0) }
        }
    )
}

@MainActor
@Test("highlights a code block once across streamed text and resizes, and again after invalidate")
func mt2MarkdownBlockReuse() {
    let calls = OSAllocatedUnfairLock(initialState: [String]())
    let markdown = Markdown("```ts\nx\n```", paddingX: 0, paddingY: 0, theme: mt2CountingTheme(calls))
    _ = markdown.render(width: 80)
    markdown.setText("```ts\nx\n```\n\nafter")
    _ = markdown.render(width: 40)
    #expect(calls.withLock { $0 } == ["ts:x"])
    markdown.invalidate()
    _ = markdown.render(width: 40)
    #expect(calls.withLock { $0 } == ["ts:x", "ts:x"])
}

@MainActor
@Test("renders a block again when the block after it changes its spacing")
func mt2MarkdownNextBlockSpacing() {
    let markdown = Markdown("# Title", paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
    _ = markdown.render(width: 80)
    markdown.setText("# Title\nfoo")
    #expect(markdown.render(width: 80).map { stripAnsiCodes($0).trimmingCharacters(in: .whitespaces) } == ["Title", "", "foo"])
}

@MainActor
@Test("follows changed reference link definitions")
func mt2MarkdownReferenceDefinition() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: false))
    let markdown = Markdown("[a][x]\n\n[x]: https://one.example", paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
    _ = markdown.render(width: 80)
    markdown.setText("[a][x]\n\n[x]: https://two.example")
    #expect(markdown.render(width: 80).joined().contains("https://two.example"))
}

@MainActor
@Test("cached and fresh Markdown agree for 200 random streaming prefixes")
func mt2MarkdownRandomPrefixes() {
    let document = (0..<35).map { index in
        "## Part \(index)\n\nSome **bold** text and [link](https://example.com/\(index)).\n\n```swift\nlet value = \(index)\n```\n"
    }.joined(separator: "\n")
    let characters = Array(document)
    let cached = Markdown("", paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
    var seed: UInt64 = 17
    for _ in 0..<200 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        let length = Int(seed % UInt64(characters.count + 1))
        let source = String(characters.prefix(length))
        let width = [24, 40, 72][Int((seed >> 16) % 3)]
        cached.setText(source)
        let fresh = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
        #expect(cached.render(width: width) == fresh.render(width: width))
    }
}

@MainActor
@Test("falls back to raw source when display math is wider than the content width")
func mt2WideDisplayMath() {
    let source = "\\[\n\\frac{\\partial^2 u}{\\partial x^2} + \\frac{\\partial^2 u}{\\partial y^2} = \\sum_{i=1}^{n} \\frac{1}{i^2} + \\int_0^1 f(x)\\,dx\n\\]"
    let wide = mt2Plain(source, width: 40, options: .init(renderLatex: true))
    let narrow = mt2Plain(source, width: 30, options: .init(renderLatex: true))
    #expect(wide.contains { $0.contains("─") })
    #expect(narrow.first == "\\[")
    #expect(narrow.last == "\\]")
    #expect(!narrow.contains { $0.contains("─") })
    #expect(narrow.allSatisfy { visibleWidth($0) <= 30 })
}

@MainActor
@Test("hides block and inline comments without extra spacing")
func mt2HtmlComments() {
    let withComments = "## [1.0.0]\n\n<!-- release-notes:start -->\nFixed a bug.\n\nSee <!-- todo: link --> the docs."
    let without = "## [1.0.0]\n\nFixed a bug.\n\nSee the docs."
    #expect(mt2Plain(withComments) == mt2Plain(without))
}

@MainActor
@Test("hides multi-line and unclosed comments")
func mt2UnclosedHtmlComments() {
    #expect(mt2Plain("<!--\nmulti\nline\n-->\ntext") == mt2Plain("text"))
    #expect(mt2Plain("text\n\n<!-- streaming") == mt2Plain("text"))
}

@MainActor
@Test("hides comments in blockquotes and list items")
func mt2NestedHtmlComments() {
    let withComments = "> q\n>\n> <!-- c -->\n>\n> r\n\n- a\n\n  <!-- c -->\n\n  b\n- <!-- c --> item"
    let without = "> q\n>\n> r\n\n- a\n\n  b\n- item"
    #expect(mt2Plain(withComments) == mt2Plain(without))
}

@MainActor
@Test("should stop bare URLs at CJK punctuation and preserve the following text")
func mt2BareURLCJK() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: true))
    for punctuation in "。，；：！？、“”‘’（）【】《》「」『』…—·・〈〉［］｛｝．｡｢｣､･" {
        for url in ["https://example.com", "https://example.com/中文?q=搜索#片段", "www.example.com"] {
            let source = url + String(punctuation) + "后面的中文"
            let output = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme).render(width: 160).joined()
            let href = url.hasPrefix("www.") ? "http://" + url : url
            #expect(output.contains("\u{001B}]8;;\(href)\u{001B}\\"), "\(source)")
            #expect(output.contains("\u{001B}]8;;\u{001B}\\\(punctuation)后面的中文"), "\(source)")
        }
    }
}

@MainActor
@Test("keeps its wrapped lines when the same text is set again")
func mt2TextSameTextSetter() {
    var calls = 0
    let value = Text("hello world", paddingX: 0, paddingY: 0, customBgFn: { value in
        calls += 1
        return value
    })
    let first = value.render(width: 5)
    let count = calls
    value.setText("hello world")
    #expect(value.render(width: 5) == first)
    #expect(calls == count)
}

@Test("matches swapped alpha numeric tokens")
func mt2FuzzySwappedAlphaNumeric() {
    #expect(fuzzyMatch("codex52", "gpt-5.2-codex").matches)
    #expect(fuzzyMatch("52codex", "gpt-5.2-codex").matches)
    #expect(!fuzzyMatch("codex5x", "gpt-5.2-codex").matches)
}

@Test("keeps the closing code on the wrapped line and drops the following space")
func mt2ANSIStyledBoundary() {
    #expect(wrapTextWithAnsi("aaaa \u{1B}[1mbold\u{1B}[22m next word", width: 9) == [
        "aaaa \u{1B}[1mbold\u{1B}[22m", "next word"
    ])
}

@Test("does not re-open a style closed by the dropped space")
func mt2ANSIDroppedSpaceClosesStyle() {
    #expect(wrapTextWithAnsi("aaaa \u{1B}[31mred\u{1B}[39m  next", width: 8) == [
        "aaaa \u{1B}[31mred\u{1B}[39m", "next"
    ])
}

@Test("does not exceed width for styled whitespace wider than the line")
func mt2ANSIWideStyledWhitespace() {
    for value in ["\u{1B}[41m" + String(repeating: " ", count: 20) + "\u{1B}[0m",
                  "ab\u{1B}[41m" + String(repeating: " ", count: 20) + "\u{1B}[49mcd",
                  "\u{1B}[33m" + String(repeating: " ", count: 20) + "x\u{1B}[39m"] {
        #expect(wrapTextWithAnsi(value, width: 10).allSatisfy { visibleWidth($0) <= 10 })
    }
}

@Test("trims trailing spaces before the line-end reset when a long word follows")
func mt2ANSIStrikeTrim() {
    #expect(wrapTextWithAnsi("aaa\u{1B}[9m    abcdefghij\u{1B}[29m", width: 9) == [
        "aaa\u{1B}[9m\u{1B}[29m", "\u{1B}[9mabcdefghi\u{1B}[29m", "\u{1B}[9mj\u{1B}[29m"
    ])
}

@Test("resets strikethrough at line end and restores it on the next line")
func mt2ANSIStrikeReset() {
    #expect(wrapTextWithAnsi("aaaa \u{1B}[9mstrike me\u{1B}[29m next", width: 12) == [
        "aaaa \u{1B}[9mstrike\u{1B}[29m", "\u{1B}[9mme\u{1B}[29m next"
    ])
}

@Test("preserves background when resetting strikethrough at line end")
func mt2ANSIStrikeBackground() {
    #expect(wrapTextWithAnsi("\u{1B}[41;9mstrike me\u{1B}[0m", width: 6) == [
        "\u{1B}[41;9mstrike\u{1B}[29m", "\u{1B}[9;41mme\u{1B}[0m"
    ])
}

@MainActor
private final class MT2Lines: Component {
    var lines: [String]
    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { lines }
    func handleInput(_ data: String) {}
}

@MainActor
@Test("crops a Kitty image in a padded, colored box whose first line is above the viewport")
func mt2CroppedBoxedKittyImage() {
    registerKittyImageMetadata(imageID: 11271, columns: 2, rows: 3, widthPx: 100, heightPx: 100)
    let imageLine = encodeKitty(base64Data: "AAAA", columns: 2, rows: 3, imageId: 11271, moveCursor: false)
    let box = Box(paddingX: 1, paddingY: 0, bgFn: { "\u{1B}[44m" + $0 + "\u{1B}[49m" })
    box.addChild(MT2Lines([imageLine, "", ""]))
    let stack = VStack()
    stack.addChild(MT2Lines(["before"]))
    stack.addChild(box)
    stack.addChild(MT2Lines(["after", "end"]))
    let scroll = ScrollView(stack, options: .init(follow: .end, primary: true))
    let frame = renderLayoutFrame(root: scroll, width: 20, height: 3) {}
    #expect(scroll.scrollTop == 3)
    #expect(frame.lines.contains { $0.contains("i=11271") && $0.contains("y=66,h=34,r=1") })
}

@Test("bounds reverse Kitty image search by the tallest registered image")
func mt2KittyTallImageBound() {
    registerKittyImageMetadata(imageID: 200001, columns: 2, rows: 7, widthPx: 20, heightPx: 70)
    #expect(getMaxKittyImageRows() >= 7)
}


@MainActor
@Test("drops one blank line around comment-only blocks")
func mt2CommentBlockSpacing() {
    let source = "<!-- start -->\n\n## [1.0.0]\n\n<!-- a -->\n\n- item\n\n<!-- b -->\n\n## [0.9.0]\n\n<!-- end -->"
    #expect(mt2Plain(source) == mt2Plain("## [1.0.0]\n\n- item\n\n## [0.9.0]"))
}

@MainActor
@Test("keeps other HTML and the text after a comment in a block")
func mt2CommentTrailingText() {
    #expect(mt2Plain("with <tag> markers") == ["with <tag> markers"])
    #expect(mt2Plain("<!-- c --> trailing text") == ["trailing text"])
    #expect(mt2Plain("<div>\n<!-- c -->a</div>") == ["<div>", "a</div>"])
}

@MainActor
@Test("should preserve Chinese characters without punctuation in bare URLs")
func mt2BareURLChinese() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: true))
    for url in ["https://example.com紧接着中文", "https://example.com/中文?q=搜索#片段", "https://example.com/テストー한글"] {
        let output = Markdown(url, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme).render(width: 160).joined()
        #expect(output.contains("\u{1B}]8;;\(url)\u{1B}\\"))
    }
}

@MainActor
@Test("should preserve CJK punctuation in explicit links and angle autolinks")
func mt2ExplicitCJKLinks() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: true))
    let url = "https://example.com/中文，路径·テスト・한글…—。"
    for source in ["[文档](\(url))", "<\(url)>"] {
        let output = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme).render(width: 160).joined()
        #expect(output.contains("\u{1B}]8;;\(url)\u{1B}\\"))
    }
}

private final class MT2RecordingTerminal: Terminal {
    let columns = 20
    let rows = 4
    var kittyProtocolActive = false
    var writes: [String] = []
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {}
    func stop() {}
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) { writes.append(data) }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}
}

@MainActor
@Test("redraws Kitty images after writes to covered rows")
func mt2KittyRedrawAfterCoveredWrite() throws {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
    let imageID: UInt32 = 10319
    registerKittyImageMetadata(imageID: imageID, columns: 2, rows: 3, widthPx: 100, heightPx: 100)
    let image = encodeKitty(base64Data: "AAAA", columns: 2, rows: 3, imageId: Int(imageID), moveCursor: false)
    let terminal = MT2RecordingTerminal()
    let renderer = AltScreenRenderer(terminal: terminal)
    renderer.start()
    defer { renderer.stop(preserveScreen: true) }
    func frame(_ lines: [String]) -> TuiRenderFrame {
        .init(lines: lines, cursor: nil, width: 20, height: 4, clearOnShrink: false,
              hasOverlayEntries: false, hasVisibleOverlay: false, useSystemCursor: false)
    }
    renderer.present(frame([image, "", "", "after"]))
    renderer.present(frame([image, "changed", "", "after"]))
    let output = try #require(terminal.writes.last)
    let text = try #require(output.range(of: "changed"))
    let placement = try #require(output.range(of: "\u{1B}_Ga=p,q=2"))
    #expect(output.contains("\u{1B}_Ga=d,d=a,q=2\u{1B}\\"))
    #expect(text.lowerBound < placement.lowerBound)
    #expect(!output.contains("\u{1B}_Ga=T"))
}

@MainActor
@Test("crops a Kitty image whose placeholder rows contain text when its first line is above the viewport")
func mt2CroppedImageWithTextPlaceholders() {
    registerKittyImageMetadata(imageID: 11272, columns: 2, rows: 3, widthPx: 100, heightPx: 100)
    let image = encodeKitty(base64Data: "AAAA", columns: 2, rows: 3, imageId: 11272, moveCursor: false)
    let scroll = ScrollView(MT2Lines(["before", image, "   | side", "   | side", "after", "end"]),
                            options: .init(follow: .end, primary: true))
    let frame = renderLayoutFrame(root: scroll, width: 20, height: 3) {}
    #expect(scroll.scrollTop == 3)
    #expect(frame.lines.contains { $0.contains("i=11272") && $0.contains("y=66,h=34,r=1") })
}

@MainActor
@Test("should preserve English punctuation trimming before Chinese punctuation")
func mt2BareURLEnglishPunctuation() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: true))
    let source = "https://example.com.，后面的中文"
    let output = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme).render(width: 160).joined()
    #expect(output.contains("\u{1B}]8;;https://example.com\u{1B}\\"))
    #expect(output.contains("\u{1B}]8;;\u{1B}\\.，后面的中文"))
}

@MainActor
@Test("bare URLs stop at all script-extension punctuation missing from the old hand-written set")
func mt2BareURLScriptExtensionPunctuation() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: true))
    let url = "https://example.com/中文"
    for value: UInt32 in [0x301C, 0x3014, 0x3015, 0x3016, 0x3017, 0x301D, 0x301E, 0x30A0, 0x3003] {
        let punctuation = String(Unicode.Scalar(value)!)
        let source = url + punctuation + "后面的中文"
        let output = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
            .render(width: 160).joined()
        #expect(output.contains("\u{1B}]8;;\(url)\u{1B}\\"), "U+\(String(value, radix: 16))")
        #expect(output.contains("\u{1B}]8;;\u{1B}\\\(punctuation)后面的中文"), "U+\(String(value, radix: 16))")
    }
}

@MainActor
@Test("CJK letters without punctuation remain inside bare URLs")
func mt2BareURLNoCJKPunctuation() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: true))
    for value: UInt32 in [0xFF5F, 0xFF60] {
        let url = "https://example.com/中文" + String(Unicode.Scalar(value)!) + "后续"
        let output = Markdown(url, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
            .render(width: 160).joined()
        #expect(output.contains("\u{1B}]8;;\(url)\u{1B}\\"))
    }
}

@MainActor
@Test("bare URLs in table cells stop at CJK punctuation")
func mt2BareURLTableCJK() {
    defer { setCapabilities(nil) }
    setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: true))
    let url = "https://example.com/中文"
    let source = "| Link |\n| --- |\n| \(url)。后面 |"
    let output = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
        .render(width: 80).joined(separator: "\n")
    #expect(output.contains("\u{1B}]8;;\(url)\u{1B}\\"))
    #expect(output.contains("\u{1B}]8;;\u{1B}\\。后面"))
}
