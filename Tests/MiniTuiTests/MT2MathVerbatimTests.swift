import Foundation
import Testing
@testable import MiniTui

@MainActor
@Test("wide display math preserves all Markdown-significant source characters")
func mt2WideMathVerbatimSource() {
    let wide = #"\frac{\partial^2 u}{\partial x^2} + \frac{\partial^2 u}{\partial y^2} = \sum_{i=1}^{n} \frac{1}{i^2} + \int_0^1 f(x)\,dx"#
    let cases: [(String, [String])] = [
        ("emphasis", ["a_1 * b_2 * c_3"]),
        ("HTML and entity", [#"\text{<b>&amp;</b>}"#]),
        ("backticks", ["`code` and ``two ticks``"]),
        ("stacked scripts", ["x_{i}^{2}", "y_{j}^{3}"]),
        ("list and heading", ["- list shaped source", "# heading shaped source"]),
        ("table pipe", ["a | b | c"]),
        ("setext marker", ["==="]),
    ]
    for (name, extraLines) in cases {
        let lines = [#"\["#, wide] + extraLines + [#"\]"#]
        let source = lines.joined(separator: "\n")
        for preserve in [false, true] {
            let markdown = Markdown(source, paddingX: 0, paddingY: 0,
                theme: defaultMarkdownTheme,
                defaultTextStyle: DefaultTextStyle(bold: true),
                options: MarkdownOptions(preserveBackslashEscapes: preserve, renderLatex: true))
            let width = 30
            let rendered = markdown.render(width: width)
            let plain = rendered.map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
            let expected = lines.flatMap { wrapTextWithAnsi($0, width: width) }
                .map { $0.trimmingTrailingWhitespace() }
            #expect(plain == expected, "\(name), preserveBackslashEscapes=\(preserve)")
            #expect(rendered.allSatisfy { $0.contains("\u{1B}[1m") }, "\(name): default bold style")
            #expect(transformMarkdownLatex(source, width: width) == source, "\(name): public source transform")
        }
    }
}

@MainActor
@Test("wide dollar display math preserves source delimiters and line structure")
func mt2WideDollarMathVerbatim() {
    let lines = ["$$", #"\text{<b>&amp;</b>}"#, "a_1 * b_2 * c_3", "- source", "# source", "|", "===", "$$"]
    let source = lines.joined(separator: "\n")
    let width = 8
    for preserve in [false, true] {
        let markdown = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme,
            options: MarkdownOptions(preserveBackslashEscapes: preserve, renderLatex: true))
        let actual = markdown.render(width: width).map { stripAnsiCodes($0).trimmingTrailingWhitespace() }
        let expected = lines.flatMap { wrapTextWithAnsi($0, width: width) }
            .map { $0.trimmingTrailingWhitespace() }
        #expect(actual == expected, "preserveBackslashEscapes=\(preserve)")
    }
}

@MainActor
@Test("cached wide display markers use the current raw source")
func mt2WideMathMarkerCacheParity() {
    let wide = #"\frac{\partial^2 u}{\partial x^2} + \frac{\partial^2 u}{\partial y^2} = \sum_{i=1}^{n} \frac{1}{i^2} + \int_0^1 f(x)\,dx"#
    let first = [#"\["#, wide, "a_1 * b_2", #"\]"#].joined(separator: "\n")
    let second = [#"\["#, wide, #"\text{<b>&amp;</b>}"#, #"\]"#].joined(separator: "\n")
    let cached = Markdown(first, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme,
                          options: MarkdownOptions(renderLatex: true))
    _ = cached.render(width: 30)
    cached.setText(second)
    let fresh = Markdown(second, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme,
                         options: MarkdownOptions(renderLatex: true))
    #expect(cached.render(width: 30) == fresh.render(width: 30))
}
