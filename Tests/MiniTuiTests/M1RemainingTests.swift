import Foundation
import Testing
@testable import MiniTui

private final class M1RemainingProvider: AutocompleteProvider {
    let triggerCharacters = ["@", "#", "$", "-"]
    private(set) var requests: [String] = []

    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int, signal: CancellationSignal?) -> (items: [AutocompleteItem], prefix: String)? {
        let prefix = lines[cursorLine].prefixCharacters(cursorCol)
        requests.append(prefix)
        return ([AutocompleteItem(value: "choice", label: "choice")], prefix)
    }

    func applyCompletion(lines: [String], cursorLine: Int, cursorCol: Int, item: AutocompleteItem, prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        (lines, cursorLine, cursorCol)
    }
}

@MainActor
private final class M1ChangingLines: Component {
    var lines = ["a\nb"]
    func render(width: Int) -> [String] { lines }
}

@MainActor
private final class M1SubmenuHost: Container, MouseFocusOwner {
    let list = SelectList(items: [
        SelectItem(value: "first", label: "First"),
        SelectItem(value: "second", label: "Second"),
    ], maxVisible: 5, theme: defaultSelectListTheme)

    init(done: @escaping (String?) -> Void) {
        super.init()
        list.onSelect = { done($0.value) }
        addChild(list)
    }

    override func handleInput(_ data: String) { list.handleInput(data) }
}

@MainActor
@Suite("M1 remaining upstream changes", .serialized)
struct M1RemainingTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("m1-remaining-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("slash skills match both bare names and the skill prefix")
    func skillSlash() {
        let commands = ["skill:deep-research", "skill:research-idea", "skill:to-sidecar", "skill:brainstorm", "model"]
            .map { SlashCommand(name: $0) }
        let provider = CombinedAutocompleteProvider(commands: commands)
        func values(_ query: String) -> [String] {
            let line = "/" + query
            return provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)?.items.map(\.value) ?? []
        }
        let idea = values("idea")
        #expect(idea.first == "skill:research-idea")
        #expect(idea.contains("skill:deep-research"))
        #expect(values("mod").contains("model"))
        #expect(values("skill:side").contains("skill:to-sidecar"))
        #expect(values("skill").filter { $0.hasPrefix("skill:") } == commands.prefix(4).map(\.name))
        #expect(values("skbra").contains("skill:brainstorm"))
    }

    @Test("path completion strips only unclosed leading wrappers")
    func pathWrappers() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["src/main.ts", "[slug]/page.tsx", "(group)/layout.tsx", "my dir/main.ts"] {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x".write(to: file, atomically: true, encoding: .utf8)
        }
        let provider = CombinedAutocompleteProvider(basePath: root.path)
        for wrapper in ["(", "[", "{", "<", "`", "((", "(`"] {
            for prefix in ["src/ma", "./src/ma"] {
                let line = "see \(wrapper)\(prefix)"
                let result = provider.getForceFileSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)
                #expect(result?.prefix == prefix, "\(line)")
                #expect(result?.items.map(\.value) == [prefix.replacingOccurrences(of: "src/ma", with: "src/main.ts")])
            }
        }
        let quoted = "see (\"my dir/ma"
        #expect(provider.getForceFileSuggestions(lines: [quoted], cursorLine: 0, cursorCol: quoted.count)?.prefix == "\"my dir/ma")
        for prefix in ["[slug]/pa", "(group)/la", "./[slug]/pa"] {
            let line = "see \(prefix)"
            #expect(provider.getForceFileSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)?.prefix == prefix)
        }
    }

    @Test("attachment completion recognizes opening wrappers but rejects embedded at signs")
    func attachmentWrappers() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try "readme".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let fd = root.appendingPathComponent("fd")
        try "#!/bin/sh\nprintf '%s\\n' README.md\n".write(to: fd, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fd.path)
        let provider = CombinedAutocompleteProvider(basePath: root.path, fdPath: fd.path)
        for before in ["(", "see (", "[", "{", "<", "`"] {
            let line = before + "@REA"
            let result = provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)
            #expect(result?.prefix == "@REA")
            #expect(result?.items.map(\.value) == ["@README.md"])
        }
        let embedded = "foo(@REA"
        #expect(provider.getSuggestions(lines: [embedded], cursorLine: 0, cursorCol: embedded.count) == nil)
    }

    @Test("editor triggers and debounces wrapped symbols")
    func wrappedEditorSymbols() async {
        for before in ["(", "see (", "[", "`", "<", "{"] {
            for symbol in ["@", "#", "$", "-"] {
                let provider = M1RemainingProvider()
                let editor = Editor(theme: defaultEditorTheme)
                editor.setAutocompleteProvider(provider)
                editor.setText(before)
                editor.handleInput(symbol)
                #expect(provider.requests.isEmpty, "\(before)\(symbol) should be debounced")
                try? await Task.sleep(for: .milliseconds(40))
                #expect(provider.requests == [before + symbol])
            }
        }
        let provider = M1RemainingProvider()
        let editor = Editor(theme: defaultEditorTheme)
        editor.setAutocompleteProvider(provider)
        editor.setText("foo(")
        editor.handleInput("@")
        try? await Task.sleep(for: .milliseconds(40))
        #expect(provider.requests.isEmpty)
    }

    @Test("settings list retains focus when a mouse selected submenu closes")
    func submenuFocus() async {
        let terminal = VirtualTerminal(columns: 30, rows: 6)
        let tui = TUI(terminal: terminal)
        tui.enableAltScreen()
        #expect(tui.switchRenderer(to: .altScreen))
        let theme = SettingsListTheme(label: { text, _ in text }, value: { text, _ in text }, description: { $0 }, cursor: "> ", hint: { $0 })
        var changes: [String] = []
        let settings = SettingsList(items: [
            SettingItem(id: "theme", label: "Theme", currentValue: "first", submenu: { _, done in M1SubmenuHost(done: done) }),
            SettingItem(id: "other", label: "Other", currentValue: "off", values: ["off", "on"]),
        ], maxVisible: 5, theme: theme, onChange: { changes.append("\($0):\($1)") }, onCancel: {})
        tui.addChild(settings)
        tui.setFocus(settings)
        tui.start()
        defer { tui.stop() }
        await tui.waitForRender()
        terminal.sendInput("\r")
        try? await Task.sleep(for: .milliseconds(30))
        await tui.waitForRender()
        terminal.sendInput("\u{001B}[<0;3;2M")
        terminal.sendInput("\u{001B}[<0;3;2m")
        try? await Task.sleep(for: .milliseconds(30))
        await tui.waitForRender()
        #expect(changes == ["theme:second"], "\(changes)")
        #expect(tui.getFocusedComponent() === settings)
        terminal.sendInput("\u{001B}[B")
        terminal.sendInput("\r")
        try? await Task.sleep(for: .milliseconds(30))
        await tui.waitForRender()
        #expect(changes == ["theme:second", "other:on"], "\(changes)")
    }

    @Test("box cache compares child lines without joining them")
    func boxLineCache() {
        let child = M1ChangingLines()
        let box = Box(paddingX: 0, paddingY: 0, bgFn: { "<\($0)>" })
        box.addChild(child)
        #expect(box.render(width: 5).count == 1)
        child.lines = ["a", "b"]
        #expect(box.render(width: 5) == ["<a    >", "<b    >"])
    }

    @Test("Markdown re-renders a normalized source across invalidation and width changes")
    func markdownParseReuse() {
        let markdown = Markdown("**alpha**\tbeta", paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
        let wide = markdown.render(width: 40)
        markdown.invalidate()
        #expect(markdown.render(width: 40) == wide)
        let narrow = markdown.render(width: 8).map(stripTerminalSequences).joined(separator: " ")
        #expect(narrow.contains("alpha"))
        #expect(narrow.contains("beta"))
        markdown.setText("**gamma**")
        let changed = markdown.render(width: 40).map(stripTerminalSequences).joined(separator: " ")
        #expect(changed.contains("gamma"))
        #expect(!changed.contains("alpha"))
    }
}
