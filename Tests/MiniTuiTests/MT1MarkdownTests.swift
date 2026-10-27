import Foundation
import Markdown
import Testing
@testable import MiniTui

private let mt1Table = ["| A | B |", "|---|---|", "| 1 | 2 |"]
private let mt1TableOutput = ["┌───┬───┐", "│ A │ B │", "├───┼───┤", "│ 1 │ 2 │", "└───┴───┘"]

struct MT1MathTableFixture: Sendable {
    let name: String
    let lines: [String]
    let transformedLines: [String]
    let tableOutput: [String]
    let renderedLines: [String]

    var source: String { lines.joined(separator: "\n") }
    var transformed: String { transformedLines.joined(separator: "\n") }
}

// Keep the exact source bytes from upstream markdown.test.ts:976-1035. In
// particular, each bracket opener below has TWO actual backslashes.
private let mt1MathTableFixtures: [MT1MathTableFixture] = [
    .init(name: "orphan dollars", lines: ["Intro", "", "$$", ""] + mt1Table + ["", "After"],
          transformedLines: ["Intro", "", "$$", ""] + mt1Table + ["", "After"], tableOutput: mt1TableOutput,
          renderedLines: ["Intro", "", "$$", ""] + mt1TableOutput + ["", "After"]),
    .init(name: "orphan dollars with math", lines: ["$$", "x = 1", ""] + mt1Table,
          transformedLines: ["$$", "x = 1", ""] + mt1Table, tableOutput: mt1TableOutput,
          renderedLines: ["$$ x = 1", ""] + mt1TableOutput),
    .init(name: "later dollars", lines: ["Intro", "", "$$", "x = 1", ""] + mt1Table + ["", "$$", "y^2", "$$"],
          transformedLines: ["Intro", "", "$$", "x = 1", ""] + mt1Table + ["", "y²"], tableOutput: mt1TableOutput,
          renderedLines: ["Intro", "", "$$ x = 1", ""] + mt1TableOutput + ["", "y²"]),
    .init(name: "aligned pipe-free delimiter", lines: ["$$", "", "| A |", ":---:", "| 1 |"],
          transformedLines: ["$$", "", "| A |", ":---:", "| 1 |"],
          tableOutput: ["┌───┐", "│ A │", "├───┤", "│ 1 │", "└───┘"],
          renderedLines: ["$$", "", "┌───┐", "│ A │", "├───┤", "│ 1 │", "└───┘"]),
    .init(name: "two-backslash bracket", lines: [#"\\["#, "x^2", ""] + mt1Table,
          transformedLines: [#"\\["#, "x^2", ""] + mt1Table, tableOutput: mt1TableOutput,
          renderedLines: [#"\[ x^2"#, ""] + mt1TableOutput),
    .init(name: "later two-backslash bracket", lines: [#"\\["#, "x = 1", ""] + mt1Table + ["", #"\\["#, "y^2", #"\\]"#],
          transformedLines: [#"\\["#, "x = 1", ""] + mt1Table + ["", #"\\["#, "y^2", #"\\]"#], tableOutput: mt1TableOutput,
          renderedLines: [#"\[ x = 1"#, ""] + mt1TableOutput + ["", #"\[ y^2 \]"#]),
    .init(name: "pipe-free header", lines: ["$$", "x^2", "", "Value", "| --- |", "1"],
          transformedLines: ["$$", "x^2", "", "Value", "| --- |", "1"],
          tableOutput: ["┌───────┐", "│ Value │", "├───────┤", "│ 1     │", "└───────┘"],
          renderedLines: ["$$ x^2", "", "┌───────┐", "│ Value │", "├───────┤", "│ 1     │", "└───────┘"]),
    .init(name: "closed multiline math", lines: ["$$", "a", "+ b", "$$", ""] + mt1Table,
          transformedLines: ["a + b", ""] + mt1Table, tableOutput: mt1TableOutput,
          renderedLines: ["a + b", ""] + mt1TableOutput),
]

@MainActor
private func mt1Render(_ source: String, options: MarkdownOptions = MarkdownOptions(), theme: MarkdownTheme = defaultMarkdownTheme) -> [String] {
    MiniTui.Markdown(source, paddingX: 0, paddingY: 0, theme: theme, options: options)
        .render(width: 80).map { stripAnsiCodes($0).trimmedRight() }
}

private func mt1HasLines(_ expected: [String], in actual: [String]) -> Bool {
    guard actual.count >= expected.count else { return false }
    return (0...(actual.count - expected.count)).contains { start in
        Array(actual[start..<(start + expected.count)]) == expected
    }
}

@MainActor
@Suite("MT1 Markdown math and CJK emphasis")
struct MT1MarkdownTests {
    @Test("all eight upstream math/table source fixtures", arguments: mt1MathTableFixtures)
    func mathTables(_ fixture: MT1MathTableFixture) {
        #expect(transformMarkdownLatex(fixture.source, width: 80) == fixture.transformed,
                Comment(rawValue: fixture.name))
        let output = mt1Render(fixture.source, options: MarkdownOptions(renderLatex: true))
        #expect(output == fixture.renderedLines, Comment(rawValue: fixture.name))
        #expect(mt1HasLines(fixture.tableOutput, in: output), Comment(rawValue: fixture.name))
        if fixture.name == "later dollars" {
            #expect(output.last == "y²")
        }
        if fixture.name == "two-backslash bracket" || fixture.name == "later two-backslash bracket" {
            // cmark normalizes the source's escaped backslash to one literal backslash.
            #expect(output.contains { $0.contains(#"\["#) })
            #expect(output.contains { $0.contains("x") })
            #expect(!output.contains { $0.contains("y²") })
        }
    }

    @Test("single-backslash math can resume after a table")
    func singleBackslash() {
        let source = ([#"\["#, "x^2", ""] + mt1Table + ["", #"\["#, "y^2", #"\]"#]).joined(separator: "\n")
        let expected = ([#"\["#, "x^2", ""] + mt1Table + ["", "y²"]).joined(separator: "\n")
        #expect(transformMarkdownLatex(source, width: 80) == expected)
        let output = mt1Render(source, options: MarkdownOptions(renderLatex: true))
        #expect(mt1HasLines(mt1TableOutput, in: output))
        #expect(output.last == "y²")
    }

    @Test("whole-text streaming keeps each complete table boundary")
    func streaming() {
        for fixture in mt1MathTableFixtures {
            let component = MiniTui.Markdown("", paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme,
                                             options: MarkdownOptions(renderLatex: true))
            var prefix = ""
            for character in fixture.source {
                prefix.append(character)
                component.setText(prefix)
                let actual = component.render(width: 80).map { stripAnsiCodes($0).trimmedRight() }
                #expect(actual == mt1Render(prefix, options: MarkdownOptions(renderLatex: true)))
                if let tableEnd = prefix.range(of: fixture.lines.contains("Value") ? "Value\n| --- |\n1" : fixture.lines.contains(":---:") ? "| A |\n:---:\n| 1 |" : mt1Table.joined(separator: "\n")) {
                    let transformed = transformMarkdownLatex(prefix, width: 80)
                    #expect(transformed.contains(prefix[tableEnd]))
                    #expect(mt1HasLines(fixture.tableOutput, in: actual))
                }
            }
        }
    }

    @Test("table boundary accepts alignment and rejects thematic breaks")
    func tableBoundaries() {
        for source in ["| A |\n:---:", "A\n| --- |", "A | B\n:-- | --:", "| A |\n   ---", "A\n| - |"] {
            #expect(containsMarkdownTableStart(source))
        }
        for source in ["A\n---", "A\n:---:", "A\n    | --- |", "A\n| : |", "| A |\n--x--"] {
            #expect(!containsMarkdownTableStart(source))
        }
        #expect(transformMarkdownLatex("$$\na\n---\nb\n$$", width: 80) != "$$\na\n---\nb\n$$")
    }

    @Test("math code protection and the default option stay in force")
    func mathOptionsAndCode() {
        let source = "`$$x^2$$`\n\n```tex\n$$x^2$$\n\\[x^2\\]\n```"
        #expect(transformMarkdownLatex(source, width: 80) == source)
        #expect(mt1Render("$x^2$") == ["$x^2$"])
        #expect(mt1Render("$x^2$", options: MarkdownOptions(renderLatex: true)) == ["x²"])
    }

    private var tagTheme: MarkdownTheme {
        MarkdownTheme(heading: { $0 }, link: { $0 }, linkUrl: { $0 }, code: { $0 },
                      codeBlock: { $0 }, codeBlockBorder: { $0 }, quote: { $0 }, quoteBorder: { $0 },
                      hr: { $0 }, listBullet: { $0 }, bold: { "<b>\($0)</b>" },
                      italic: { "<i>\($0)</i>" }, strikethrough: { $0 }, underline: { $0 })
    }

    @Test("the five upstream CJK sources produce emphasis nodes")
    func cjkFixtures() {
        let fixtures = [
            ("**这是测试。**后面", "<b>这是测试。</b>后面"),
            ("**一句话说清：**一台机器", "<b>一句话说清：</b>一台机器"),
            ("**要点到此为止。**20 小时", "<b>要点到此为止。</b>20 小时"),
            ("字**「引用」**字", "字<b>「引用」</b>字"),
            ("*斜体。*后面", "<i>斜体。</i>后面"),
        ]
        for (source, expected) in fixtures {
            #expect(mt1Render(source, theme: tagTheme) == [expected])
            let input = MarkdownCJKParserInput(source)
            let document = Document(parsing: input.source)
            #expect(Array(document.children).first?.children.contains { $0 is Strong || $0 is Emphasis } == true)
            #expect(MarkdownCJKParserInput(input.source).source == input.source)
        }
    }

    @Test("non-CJK flanking and unmatched markers stay literal")
    func commonMarkAndUnmatched() {
        for source in ["**end.**Then next", "**end.**20 hours", "word_italic_word", "字**「引用」", "**这是测试。后面", "字*「引用」"] {
            #expect(mt1Render(source, theme: tagTheme) == [source])
        }
        #expect(mt1Render("**bold** and *italic*", theme: tagTheme) == ["<b>bold</b> and <i>italic</i>"])
    }

    @Test("nested CJK emphasis keeps cmark delimiter matching")
    func nested() {
        #expect(mt1Render("**粗体 *斜体。*后面**", theme: tagTheme) == ["<b>粗体 <i>斜体。</i>后面</b>"])
        #expect(mt1Render("***强调。***后面", theme: tagTheme) == ["<i><b>强调。</b></i>后面"])
    }

    @Test("code, escapes, HTML, and link destinations are not adapted")
    func protectedSource() {
        for source in ["`**这是测试。**后面`", "``**这是测试。**后面``", "```\n**这是测试。**后面\n```",
                       "    **这是测试。**后面", #"\*\*这是测试。\*\*后面"#,
                       #"<span title="**这是测试。**后面">x</span>"#,
                       "[x](https://example.com/**这是测试。**后面)"] {
            #expect(MarkdownCJKParserInput(source).source == source)
        }
        #expect(mt1Render("`**这是测试。**后面`", theme: tagTheme) == ["**这是测试。**后面"])
        #expect(mt1Render(#"\*\*这是测试。\*\*后面"#, theme: tagTheme) == ["**这是测试。**后面"])
        #expect(mt1Render(#"\*\*这是测试。\*\*后面"#, options: MarkdownOptions(preserveBackslashEscapes: true), theme: tagTheme)
                == [#"\*\*这是测试。\*\*后面"#])
    }

    @Test("padding cannot remove user comments or decoded entities")
    func paddingCollision() {
        let source = "字<!--minitui-cjk--> **这是测试。**后面 &lt;!--minitui-cjk-x--&gt;"
        let input = MarkdownCJKParserInput(source)
        #expect(input.padding != "<!--minitui-cjk-->")
        // cmark's existing smart punctuation converts decoded double hyphens.
        #expect(mt1Render(source, theme: tagTheme) == ["字<!--minitui-cjk--> <b>这是测试。</b>后面 <!–minitui-cjk-x–>"])
    }

    @Test("the document cache uses the final parser input")
    func finalParserCacheKey() {
        MarkdownDocumentCache.shared.removeAll()
        let source = "**这是测试。**后面"
        let input = MarkdownCJKParserInput(source)
        #expect(input.source != source)
        _ = mt1Render(source, theme: tagTheme)
        #expect(MarkdownDocumentCache.shared.cachedDocument(for: source) == nil)
        let entry = MarkdownDocumentCache.shared.cachedDocument(for: input.source)
        #expect(entry != nil)
        #expect(entry === MarkdownDocumentCache.shared.document(for: input.source))
    }
}
