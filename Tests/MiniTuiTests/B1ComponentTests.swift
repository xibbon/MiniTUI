import Foundation
import Testing
@testable import MiniTui

@MainActor
private final class BorderEditor: Editor {
    override func renderTopBorder(width: Int, hiddenLineCount: Int) -> String { String(repeating: "T", count: width) }
    override func renderBottomBorder(width: Int, hiddenLineCount: Int) -> String { String(repeating: "B", count: width) }
}

@MainActor
private final class IndicatorLoader: Loader {
    var indicator = "custom"
    override func getRenderedIndicator() -> String { indicator }
}

@MainActor
@Suite("B1 component changes")
struct B1ComponentTests {
    @Test("supports a custom prompt and styled placeholder")
    func placeholder() {
        let input = Input(options: InputOptions(prompt: "", placeholder: "Find transcript", placeholderStyle: { "\u{1b}[2m\($0)\u{1b}[22m" }))
        input.focused = true
        let empty = input.render(width: 20)[0]
        #expect(empty.contains("\u{1b}[2m"))
        #expect(empty.contains(systemCursorMarker + "\u{1b}[7m"))
        #expect(stripTerminalSequences(empty.replacingOccurrences(of: systemCursorMarker, with: "")).trimmingCharacters(in: .whitespacesAndNewlines) == "Find transcript")
        input.handleInput("n")
        #expect(stripTerminalSequences(input.render(width: 20)[0].replacingOccurrences(of: systemCursorMarker, with: "")).trimmingCharacters(in: .whitespacesAndNewlines) == "n")
        let narrow = Input(options: InputOptions(prompt: "界> "))
        #expect(visibleWidth(narrow.render(width: 1)[0]) <= 1)
        #expect(visibleWidth(narrow.render(width: 3)[0]) <= 3)
    }

    @Test("input mouse positions graphemes in its horizontal window")
    func inputScroll() {
        let input = Input()
        input.handleInput("0123456789")
        _ = input.render(width: 6)
        _ = input.handleMouse(b1Mouse(.press, 2, 0, width: 6, height: 1))
        input.handleInput("X")
        #expect(input.getValue() == "0123456X789")
        let wide = Input(options: InputOptions(prompt: ""))
        wide.setValue("a界e\u{301}z")
        _ = wide.render(width: 20)
        _ = wide.handleMouse(b1Mouse(.press, 4, 0))
        wide.handleInput("X")
        #expect(wide.getValue() == "aX界e\u{301}z") // Upstream uses x - 2 even with an empty prompt.
    }

    @Test("centers scroll indicators on wide borders")
    func scrollBorders() {
        let ui = TUI(terminal: VirtualTerminal(columns: 40, rows: 24))
        let editor = Editor(ui: ui, theme: defaultEditorTheme)
        editor.setText((0..<20).map { "line \($0)" }.joined(separator: "\n"))
        _ = editor.render(width: 40)
        for _ in 0..<10 { editor.handleInput("\u{1b}[A") }
        let lines = editor.render(width: 40)
        #expect(stripTerminalSequences(lines[0]) == String(repeating: "─", count: 15) + " ↑ 9 more " + String(repeating: "─", count: 15))
        #expect(stripTerminalSequences(lines.last!) == String(repeating: "─", count: 15) + " ↓ 4 more " + String(repeating: "─", count: 15))
        #expect(stripTerminalSequences(editor.renderTopBorder(width: 5, hiddenLineCount: 100)) == "──...")
        let hooks = BorderEditor(theme: defaultEditorTheme)
        #expect(hooks.render(width: 4).first == "TTTT")
        #expect(hooks.render(width: 4).last == "BBBB")
    }

    @Test("autocomplete mouse selection applies a completion and supports undo")
    func completion() {
        let editor = Editor(theme: defaultEditorTheme)
        editor.setAutocompleteProvider(CombinedAutocompleteProvider(commands: [SlashCommand(name: "hello", description: "hello command")]))
        editor.handleInput("/")
        let lines = editor.render(width: 40)
        #expect(lines.count > 3)
        var changed: String?
        editor.onChange = { changed = $0 }
        #expect(editor.handleMouse(b1Mouse(.press, 2, 3))?.focus == true)
        #expect(editor.handleMouse(b1Mouse(.click, 2, 3))?.handled == true)
        #expect(editor.getText().contains("/hello"))
        #expect(changed == editor.getText())
        #expect(editor.render(width: 40).count == 3)
        editor.handleInput("\u{1f}")
        #expect(editor.getText() == "/")
    }

    @Test("loader invalidation refreshes the overridable indicator")
    func loader() {
        let ui = TUI(terminal: VirtualTerminal())
        let loader = IndicatorLoader(ui: ui, spinnerColorFn: { "color(\($0))" }, messageColorFn: { $0 }, message: "working")
        loader.stop()
        loader.indicator = "new"
        loader.invalidate()
        #expect(loader.render(width: 30).joined().contains("new working"))
        let plain = Loader(ui: ui, spinnerColorFn: { "color(\($0))" }, messageColorFn: { $0 })
        plain.stop()
        #expect(plain.getRenderedIndicator().hasPrefix("color("))
        plain.setIndicator(LoaderIndicatorOptions(frames: ["*"]))
        #expect(plain.getRenderedIndicator() == "*")
        plain.setIndicator(LoaderIndicatorOptions(frames: []))
        #expect(plain.getRenderedIndicator().isEmpty)
    }

    @Test("padded text stays within narrow widths")
    func textPadding() {
        for width in 1...8 {
            for padding in [1, 3, 20] {
                let text = Text("abc def", paddingX: padding, paddingY: 1)
                #expect(text.render(width: width).allSatisfy { visibleWidth($0) <= width })
            }
        }
    }
}

@Suite("B1 LaTeX and ANSI")
struct B1LatexTests {
    @Test("renders relational algebra join operators")
    func joins() {
        #expect(renderLatex(#"R\bowtie S,\quad R\Join S"#) == "R ⋈ S, R ⋈ S")
        #expect(renderLatex(#"R\ltimes S,\quad R\rtimes S"#) == "R ⋉ S, R ⋊ S")
        #expect(renderLatex(#"R\leftouterjoin S,\quad R\rightouterjoin S,\quad R\fullouterjoin S"#) == "R ⟕ S, R ⟖ S, R ⟗ S")
    }
    @Test("treats a backslash followed by a line ending as control space")
    func controlSpace() {
        let source = "\\boxed{\n(1,1,1),\\ (1,1,2),\\ (1,2,5),\\ (1,5,13),\\ (2,5,29),\\\n(1,13,34),\\ (1,34,89)\n}."
        #expect(renderLatex(source, options: RenderLatexOptions(display: true)) == "[(1,1,1), (1,1,2), (1,2,5), (1,5,13), (2,5,29), (1,13,34), (1,34,89)].")
        #expect(renderLatex("a\\\r\nb") == "a b")
    }
    @Test("required LaTeX arguments skip newlines")
    func argument() {
        #expect(renderLatex("\\frac{1}\n{2}", options: RenderLatexOptions(display: true)) == "1\n─\n2")
    }
    @Test("active ANSI background excludes other styles and honors resets")
    func background() {
        #expect(getActiveBackgroundAnsi("\u{1b}[31;42mtext\u{1b}[39m") == "\u{1b}[42m")
        #expect(getActiveBackgroundAnsi("\u{1b}[48;5;123m\u{1b}[1m") == "\u{1b}[48;5;123m")
        #expect(getActiveBackgroundAnsi("\u{1b}[48;2;1;2;3m") == "\u{1b}[48;2;1;2;3m")
        #expect(getActiveBackgroundAnsi("\u{1b}[42m\u{1b}[49m").isEmpty)
        #expect(getActiveBackgroundAnsi("\u{1b}[42m\u{1b}[0m").isEmpty)
    }
}
