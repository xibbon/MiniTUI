import Testing
@testable import MiniTui

private struct MT4FixedCompletion: AutocompleteProvider {
    let prefix: String
    let value: String

    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int,
                        signal: CancellationSignal?) -> (items: [AutocompleteItem], prefix: String)? {
        ([AutocompleteItem(value: value, label: value)], prefix)
    }

    func applyCompletion(lines: [String], cursorLine: Int, cursorCol: Int,
                         item: AutocompleteItem, prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        var result = lines
        let line = lines[cursorLine]
        let start = line.index(line.startIndex, offsetBy: cursorCol - prefix.count)
        let end = line.index(line.startIndex, offsetBy: cursorCol)
        result[cursorLine].replaceSubrange(start..<end, with: item.value)
        return (result, cursorLine, cursorCol - prefix.count + item.value.count)
    }
}

@MainActor
@Suite("MT4 Editor and SettingsList")
struct MT4EditorSettingsTests {
    @Test("Enter on a Tab path menu with a / prefix completes without submitting")
    func tabPathWithSlashPrefix() {
        let editor = Editor(theme: defaultEditorTheme)
        var submitted: [String] = []
        editor.onSubmit = { submitted.append($0) }
        editor.setAutocompleteProvider(MT4FixedCompletion(prefix: "/tmp/x/fi", value: "/tmp/x/file-one.md"))
        editor.setText("look at /tmp/x/fi")
        editor.handleInput("\t")
        #expect(editor.isShowingAutocomplete())
        editor.handleInput("\r")
        #expect(submitted.isEmpty)
        #expect(editor.getText() == "look at /tmp/x/file-one.md")
    }

    @Test("Enter on an argument menu with a / prefix completes without submitting")
    func argumentWithSlashPrefix() {
        let editor = Editor(theme: defaultEditorTheme)
        var submitted: [String] = []
        editor.onSubmit = { submitted.append($0) }
        editor.setAutocompleteProvider(CombinedAutocompleteProvider(commands: [
            SlashCommand(name: "open", getArgumentCompletions: { prefix in
                prefix.hasPrefix("/") ? [AutocompleteItem(value: "/tmp/alpha", label: "alpha")] : nil
            }),
        ]))
        for character in "/open /tm" { editor.handleInput(String(character)) }
        #expect(editor.isShowingAutocomplete())
        editor.handleInput("\r")
        #expect(submitted.isEmpty)
        #expect(editor.getText() == "/open /tmp/alpha")
    }

    @Test("Enter on a Tab slash command menu submits the command")
    func tabSlashCommandSubmits() {
        let editor = Editor(theme: defaultEditorTheme)
        var submitted: [String] = []
        editor.onSubmit = { submitted.append($0) }
        let provider = CombinedAutocompleteProvider(commands: [
            SlashCommand(name: "model"), SlashCommand(name: "session"),
        ])
        editor.setAutocompleteProvider(provider)
        editor.setText("/mo")
        #expect(provider.getSuggestions(lines: ["/mo"], cursorLine: 0, cursorCol: 3, signal: nil) != nil)
        editor.handleInput("\t")
        #expect(editor.getText() == "/mo")
        #expect(editor.isShowingAutocomplete())
        editor.handleInput("\r")
        #expect(submitted == ["/model"])
    }

    @Test("keeps the selection when a cursor key leaves the query unchanged")
    func settingsCursorKeepsSelection() {
        var changes: [String] = []
        let theme = SettingsListTheme(label: { text, _ in text }, value: { text, _ in text },
            description: { $0 }, cursor: "> ", hint: { $0 })
        let list = SettingsList(items: ["Alpha mode", "Beta mode", "Other"].map {
            SettingItem(id: $0, label: $0, currentValue: "off", values: ["off", "on"])
        }, maxVisible: 10, theme: theme, onChange: { id, _ in changes.append(id) }, onCancel: {},
        options: SettingsListOptions(enableSearch: true))
        for character in "mode" { list.handleInput(String(character)) }
        list.handleInput("\u{001B}[B")
        let selected = list.render(width: 80).dropFirst().first { $0.hasPrefix("> ") }
        for key in ["\u{001B}[D", "\u{001B}[C", "\u{001B}[H", "\u{001B}[F"] {
            list.handleInput(key)
            #expect(list.render(width: 80).dropFirst().first { $0.hasPrefix("> ") } == selected)
        }
        list.handleInput("\r")
        #expect(changes.count == 1)
        #expect(selected?.contains(changes[0]) == true)
    }
}
