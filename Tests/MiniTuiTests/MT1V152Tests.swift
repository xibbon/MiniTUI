import Foundation
import Testing
@testable import MiniTui
#if canImport(Darwin)
import Darwin
#endif

private final class MT1V152Terminal: Terminal {
    let columns = 30
    let rows = 6
    let kittyProtocolActive = false
    var writes: [String] = []
    var onInput: ((String) -> Void)?
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) { self.onInput = onInput }
    func stop() { onInput = nil }
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
private final class MT1V152Lines: Component {
    var lines: [String]
    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { lines }
}

private struct MT1V152Completions: AutocompleteProvider {
    let triggerCharacters = ["/"]
    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int, signal: CancellationSignal?)
        -> (items: [AutocompleteItem], prefix: String)? {
        ((0..<12).map { AutocompleteItem(value: "/command-\($0)", label: "command-\($0)") }, "/")
    }
    func applyCompletion(lines: [String], cursorLine: Int, cursorCol: Int, item: AutocompleteItem, prefix: String)
        -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        ([item.value], 0, item.value.count)
    }
}

@Test("replaces control characters so the title cannot end the OSC sequence")
func mt1V152TitleControls() {
    let title = "safe\u{001B}]2;bad\u{0007}\u{007F}\u{009F}end"
    #expect(replaceControlCharacters(title) == "safe ]2;bad end")
    #if canImport(Darwin)
    var descriptors: [Int32] = [0, 0]
    #expect(pipe(&descriptors) == 0)
    defer { close(descriptors[0]); close(descriptors[1]) }
    let terminal = ProcessTerminal(inputDescriptor: descriptors[0], outputDescriptor: descriptors[1])
    terminal.setTitle(title)
    var bytes = [UInt8](repeating: 0, count: 128)
    let count = read(descriptors[0], &bytes, bytes.count)
    #expect(count > 0)
    if count > 0 { #expect(String(decoding: bytes.prefix(count), as: UTF8.self) == "\u{001B}]0;safe ]2;bad end\u{0007}") }
    #endif
}

@Test("rewrites ESC+CR to CSI-u Shift+Enter when Shift is pressed")
func mt1V152NativeShiftEnter() {
    #expect(normalizeAppleTerminalInput("\u{001B}\r", isAppleTerminal: true, isShiftPressed: true) == "\u{001B}[13;2u")
    #expect(normalizeAppleTerminalInput("\r", isAppleTerminal: true, isShiftPressed: true) == "\u{001B}[13;2u")
    #expect(normalizeAppleTerminalInput("\u{001B}\r", isAppleTerminal: true, isShiftPressed: false) == "\u{001B}\r")
    #expect(normalizeAppleTerminalInput("\u{001B}\r", isAppleTerminal: false, isShiftPressed: true) == "\u{001B}\r")
    #expect(normalizeAppleTerminalInput("x", isAppleTerminal: true, isShiftPressed: true) == "x")
}

@Test("scores a contiguous occurrence instead of an earlier scattered alignment")
func mt1V152FuzzyContiguous() {
    let opus = fuzzyMatch("opus", "openrouter openrouter/anthropic/claude-opus-4.1")
    let sonnet = fuzzyMatch("opus", "openrouter openrouter/anthropic/claude-sonnet-4.5")
    let oss = fuzzyMatch("opus", "openrouter openrouter/openai/gpt-oss-120b")
    #expect(opus.score < sonnet.score)
    #expect(opus.score < oss.score)
}

@Test("uses the best contiguous occurrence, not the first")
func mt1V152FuzzyBestOccurrence() {
    #expect(fuzzyMatch("opus", "xxopus opus").score == fuzzyMatch("opus", "xxxxxx opus").score)
}

@Test("ranks a model containing the query above models matching a shared provider prefix")
func mt1V152FuzzyModelRank() {
    let models = ["openrouter openrouter/anthropic/claude-sonnet-4.5",
                  "openrouter openrouter/anthropic/claude-opus-4.1",
                  "openrouter openrouter/openai/gpt-oss-120b"]
    #expect(fuzzyFilter(models, query: "opus") { $0 }.first == models[1])
}

@Test("keeps images disabled for Orca without an image capability signal")
func mt1V152OrcaFallback() {
    #expect(detectCapabilities(environment: ["TERM_PROGRAM": "Orca"]).images == nil)
    #expect(detectCapabilities(environment: ["TERM_PROGRAM": "Orca", "TERM": "xterm-kitty"]).images == nil)
}

@Test("enables images and hyperlinks for Orca advertising Kitty support")
func mt1V152OrcaKitty() {
    let capability = detectCapabilities(environment: ["TERM_PROGRAM": "Orca", "ORCA_IMAGE_PROTOCOL": "kitty"])
    #expect(capability.images == .kitty && capability.trueColor && capability.hyperlinks)
}

@Test("enables hyperlinks for Alacritty without TERM_PROGRAM")
func mt1V152Alacritty() {
    for environment in [["TERM": "alacritty", "COLORTERM": "truecolor"],
                        ["TERM": "xterm-256color", "COLORTERM": "truecolor", "ALACRITTY_WINDOW_ID": "1"]] {
        let capability = detectCapabilities(environment: environment)
        #expect(capability.images == nil && capability.trueColor && capability.hyperlinks)
    }
}

@Test("should match Kitty function keys F1-F12 with and without modifiers")
func mt1V152KittyFunctionKeys() {
    for (sequence, key) in [("\u{001B}[P", "f1"), ("\u{001B}[Q", "f2"),
                            ("\u{001B}[13~", "f3"), ("\u{001B}[S", "f4"),
                            ("\u{001B}[15;5~", "ctrl+f5"), ("\u{001B}[24;3~", "alt+f12"),
                            ("\u{001B}[1;5P", "ctrl+f1"), ("\u{001B}[1;2S", "shift+f4")] {
        #expect(matchesKey(sequence, key), "\(sequence) must match \(key)")
        #expect(parseKey(sequence) == key)
    }
    #expect(!matchesKey("\u{001B}[1;5P", "f1"))
    #expect(parseKey("\u{001B}[1;5R") == nil)
    #expect(isKeyRelease("\u{001B}[1;1:3P"))
    #expect(isKeyRepeat("\u{001B}[1;1:2S"))
}

@MainActor
@Test("ignores unmapped Kitty functional keys such as F13-F35")
func mt1V152UnknownFunctionKeys() {
    let editor = Editor(theme: defaultEditorTheme)
    for sequence in ["\u{001B}[57376u", "\u{001B}[57398;2u", "\u{001B}[57382u"] {
        #expect(decodePrintableKey(sequence) == nil)
        editor.handleInput(sequence)
    }
    #expect(editor.getText().isEmpty)
}

@MainActor
@Test("moves by one visible page with selection page keys (#7629)")
func mt1V152ListPages() {
    let items = (0..<12).map { SelectItem(value: "item-\($0)", label: "item-\($0)") }
    let list = SelectList(items: items, maxVisible: 3, theme: defaultSelectListTheme)
    #expect(list.capturesViewportInput)
    list.handleInput("\u{001B}[6~")
    #expect(list.getSelectedItem()?.value == "item-3")
    list.handleInput("\u{001B}[5~")
    #expect(list.getSelectedItem()?.value == "item-0")
    #expect(getSelectPageIndex(keybindings: getKeybindings(), data: "x", selectedIndex: 2, itemCount: 12, pageSize: 3) == nil)
}

@MainActor
@Test("moves by one visible page with selection page keys (#7629) in SettingsList")
func mt1V152SettingsPages() {
    let settings = (0..<12).map { SettingItem(id: "setting-\($0)", label: "Setting \($0)", currentValue: "\($0)") }
    let theme = SettingsListTheme(label: { text, _ in text }, value: { text, _ in text },
        description: { $0 }, cursor: "> ", hint: { $0 })
    let list = SettingsList(items: settings, maxVisible: 5, theme: theme, onChange: { _, _ in }, onCancel: {})
    #expect(list.capturesViewportInput)
    list.handleInput("\u{001B}[6~")
    #expect(list.render(width: 80).joined(separator: "\n").contains("> Setting 5"))
    list.handleInput("\u{001B}[6~")
    list.handleInput("\u{001B}[6~")
    #expect(list.render(width: 80).joined(separator: "\n").contains("> Setting 11"))
    list.handleInput("\u{001B}[5~")
    #expect(list.render(width: 80).joined(separator: "\n").contains("> Setting 6"))
}

@MainActor
@Test("moves the autocomplete selection with selection page keys (#7629)")
func mt1V152EditorAutocompletePages() async throws {
    let editor = Editor(theme: defaultEditorTheme)
    editor.setAutocompleteProvider(MT1V152Completions())
    var submitted = ""
    editor.onSubmit = { submitted = $0 }
    #expect(!editor.capturesViewportInput)
    editor.handleInput("/")
    try await Task.sleep(for: .milliseconds(80))
    #expect(editor.capturesViewportInput)
    editor.handleInput("\u{001B}[6~")
    editor.handleInput("\u{001B}[6~")
    editor.handleInput("\u{001B}[5~")
    editor.handleInput("\r")
    #expect(submitted == "/command-5")
    #expect(!editor.capturesViewportInput)
}

@MainActor
@Test("gives viewport keys back to the transcript when editor autocomplete closes (#7629)")
func mt1V152EditorViewportRestored() async throws {
    let terminal = MT1V152Terminal()
    let tui = TUI(terminal: terminal)
    let renderer = tui.enableAltScreen()
    _ = tui.switchRenderer(to: .altScreen)
    let editor = Editor(theme: defaultEditorTheme)
    editor.setAutocompleteProvider(MT1V152Completions())
    tui.addChild(MT1V152Lines((0..<30).map { "line \($0)" }))
    tui.addChild(editor)
    tui.setFocus(editor)
    tui.start()
    defer { tui.stop() }
    await tui.waitForRender()
    editor.handleInput("/")
    try await Task.sleep(for: .milliseconds(80))
    #expect(editor.capturesViewportInput)
    let before = renderer.viewportTop
    #expect(!renderer.handleInput("\u{001B}[6~"))
    #expect(renderer.viewportTop == before)
    editor.handleInput("\u{001B}[6~")
    editor.handleInput("\r")
    #expect(!editor.capturesViewportInput)
    let after = renderer.viewportTop
    #expect(renderer.handleInput("\u{001B}[5~"))
    #expect(renderer.viewportTop < after)
}

@MainActor
@Test("coalesces slash and hyphen separated segments for double-click word selection")
func mt1V152DoubleClickJoiners() async {
    for (line, needle) in [("extensions/starline/fixed-editor/compositor.ts", "starline"),
                           ("earendil-works/pi-tui", "works"),
                           ("~/.pi/agent/settings.json", "agent"),
                           ("~\\Documents\\pi", "Documents"),
                           ("foo+bar", "bar")] {
        let terminal = MT1V152Terminal()
        var copied: [String] = []
        let options = AltScreenRendererOptions(copySelection: { text in copied.append(text); return .copied })
        let tui = TUI(terminal: terminal)
        let renderer = tui.enableAltScreen(options: options)
        _ = tui.switchRenderer(to: .altScreen)
        tui.addChild(MT1V152Lines([line]))
        tui.start()
        await tui.waitForRender()
        let col = line.distance(from: line.startIndex, to: line.range(of: needle)!.lowerBound) + 1
        for _ in 0..<2 {
            _ = renderer.handleInput("\u{001B}[<0;\(col);1M")
            _ = renderer.handleInput("\u{001B}[<0;\(col);1m")
        }
        await Task.yield()
        await tui.waitForRender()
        #expect(copied == [line])
        tui.stop()
    }
}

@MainActor
@Test("does not write duplicate cursor markers to the terminal")
func mt1V152DuplicateCursorMarkers() async {
    let terminal = MT1V152Terminal()
    let tui = TUI(terminal: terminal, showHardwareCursor: true)
    tui.addChild(MT1V152Lines(["\u{001B}[31m界🙂\u{001B}[0m\(systemCursorMarker) world\(systemCursorMarker)"]))
    tui.start()
    defer { tui.stop() }
    await tui.waitForRender()
    let output = terminal.writes.joined()
    #expect(output.contains("\u{001B}[31m界🙂\u{001B}[0m world"))
    #expect(!output.contains(systemCursorMarker))
}

@MainActor
@Test("defers viewport keys to a focused list instead of scrolling the transcript (#7629)")
func mt1V152FocusedListPages() async {
    let terminal = MT1V152Terminal()
    let tui = TUI(terminal: terminal)
    let renderer = tui.enableAltScreen()
    _ = tui.switchRenderer(to: .altScreen)
    let items = (0..<12).map { SelectItem(value: "item-\($0)", label: "item-\($0)") }
    let list = SelectList(items: items, maxVisible: 3, theme: defaultSelectListTheme)
    tui.addChild(MT1V152Lines((0..<12).map { "line \($0)" }))
    tui.addChild(list)
    tui.setFocus(list)
    tui.start()
    defer { tui.stop() }
    await tui.waitForRender()
    let top = renderer.viewportTop
    terminal.onInput?("\u{001B}[6~")
    await Task.yield()
    await tui.waitForRender()
    #expect(list.getSelectedItem()?.value == "item-3")
    #expect(renderer.viewportTop == top)
}

@MainActor
@Test("does not write OSC 133 prompt markers to the terminal")
func mt1V152MainScreenPromptZones() {
    let terminal = MT1V152Terminal()
    let renderer = MainScreenRenderer(terminal: terminal)
    renderer.start()
    defer { renderer.stop(preserveScreen: true) }
    let lines = ["\u{001B}]133;A\u{0007}prompt", "\u{001B}]133;B\u{0007}\u{001B}]133;C\u{0007}output",
                 "\u{001B}]133;A\u{001B}\\reply", "\u{001B}]133;B\u{001B}\\\u{001B}]133;C\u{001B}\\done"]
    renderer.present(.init(lines: lines, cursor: nil, width: 30, height: 6,
        clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false, useSystemCursor: false))
    let output = terminal.writes.joined()
    #expect(!output.contains("\u{001B}]133;"))
    for word in ["prompt", "output", "reply", "done"] { #expect(output.contains(word)) }
}

@MainActor
@Test("does not write cursor markers from other visible or scrollback lines")
func mt1V152CursorMarkers() async {
    let terminal = MT1V152Terminal()
    let tui = TUI(terminal: terminal)
    let lines = MT1V152Lines(["offscreen\(systemCursorMarker)", "a\(systemCursorMarker)",
                              "visible-b\(systemCursorMarker)"])
    tui.addChild(lines)
    tui.start()
    defer { tui.stop() }
    await tui.waitForRender()
    #expect(!terminal.writes.joined().contains(systemCursorMarker))
}

@MainActor
@Test("renumbers short paste markers without a size suffix")
func mt1V152ShortPasteMarkers() {
    let editor = Editor(theme: defaultEditorTheme)
    let first = (1...11).map { "alpha \($0)" }.joined(separator: "\n")
    let second = (1...11).map { "beta \($0)" }.joined(separator: "\n")
    editor.handleInput("\u{001B}[200~\(first)\u{001B}[201~")
    editor.handleInput("\u{001B}[200~\(second)\u{001B}[201~")
    editor.handleInput("\u{0015}")
    for character in "[paste #1][paste #2]" { editor.handleInput(String(character)) }
    editor.handleInput("\u{001B}[D")
    editor.handleInput("\u{007F}")
    #expect(editor.getText() == "[paste #1]")
    #expect(editor.getExpandedText() == second)
}
