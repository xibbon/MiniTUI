import Foundation
import Testing
@testable import MiniTui

private final class MT1CursorTerminal: Terminal {
    let columns: Int
    let rows: Int
    let kittyProtocolActive = false
    var writes: [String] = []
    var input: ((String) -> Void)?
    var output: String { writes.joined() }
    init(_ columns: Int = 20, _ rows: Int = 5) { self.columns = columns; self.rows = rows }
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) { input = onInput }
    func stop() { input = nil }
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
private final class MT1CursorComponent: Component, Focusable {
    var lines: [String]
    var focused = false
    var inputs: [String] = []
    var wheelEvents = 0
    var consumesWheel = false
    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { lines }
    func handleInput(_ data: String) { inputs.append(data) }
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        guard event.type == .wheel, consumesWheel else { return nil }
        wheelEvents += 1
        return .init(handled: true)
    }
}

@MainActor
private final class MT1FrameRecorder: TuiRenderer {
    let mode = TuiMode.mainScreen
    var frame: TuiRenderFrame?
    func start() {}
    func stop(preserveScreen: Bool) {}
    func present(_ frame: TuiRenderFrame) { self.frame = frame }
    func invalidateRenderState() {}
    func invalidateCursorState() {}
    func clearRenderState() {}
    func takeOverRenderState(from previous: any TuiRenderer) {}
}

@MainActor
private func mt1CursorWait(_ tui: TUI) async {
    await Task.yield()
    await tui.waitForRender()
    await Task.yield()
    await tui.waitForRender()
}

@Suite("MT1 fake cursors and overlay input")
@MainActor
struct MT1CursorOverlayTests {
    @Test("fake cursor helper uses the exact APC pair")
    func helper() {
        #expect(renderFakeCursor("a") == "\u{1b}_pi:fc\u{07}a\u{1b}_pi:/fc\u{07}")
        #expect(visibleWidth(renderFakeCursor("界")) == 2)
    }

    @Test("draws the focused fake cursor in reverse video and omits it when the hardware cursor is shown", arguments: [false, true])
    func focusedCursor(alt: Bool) async {
        let terminal = MT1CursorTerminal()
        let tui = TUI(terminal: terminal)
        if alt { tui.enableAltScreen(); #expect(tui.switchRenderer(to: .altScreen)) }
        let input = Input()
        input.setValue("abc")
        tui.addChild(input)
        tui.setFocus(input)
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        #expect(terminal.output.replacingOccurrences(of: systemCursorMarker, with: "").contains("> \u{1b}[7ma\u{1b}[27mbc"))
        #expect(!terminal.output.contains("\u{1b}_pi:"))

        terminal.writes = []
        tui.useSystemCursor = true
        tui.requestRender()
        await mt1CursorWait(tui)
        #expect(terminal.output.contains("> abc"))
        #expect(!terminal.output.contains("\u{1b}[7m"))
        #expect(!terminal.output.contains("\u{1b}_pi:"))
    }

    @Test("keeps the fake cursor of an unfocused input when the hardware cursor is shown", arguments: [false, true])
    func unfocusedCursor(alt: Bool) async {
        let terminal = MT1CursorTerminal()
        let tui = TUI(terminal: terminal, showHardwareCursor: true)
        if alt { tui.enableAltScreen(); #expect(tui.switchRenderer(to: .altScreen)) }
        let input = Input()
        input.setValue("abc")
        tui.addChild(input)
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        #expect(terminal.output.replacingOccurrences(of: systemCursorMarker, with: "").contains("> \u{1b}[7ma\u{1b}[27mbc"))
        #expect(!terminal.output.contains("\u{1b}_pi:"))
    }

    @Test("omits the focused fake cursor when truncation dropped its end marker", arguments: [false, true])
    func truncatedCursor(alt: Bool) async {
        let terminal = MT1CursorTerminal()
        let tui = TUI(terminal: terminal, showHardwareCursor: true)
        if alt { tui.enableAltScreen(); #expect(tui.switchRenderer(to: .altScreen)) }
        let truncated = sliceByColumn("ab" + systemCursorMarker + renderFakeCursor("c") + "def",
            startCol: 0, length: 3, strict: true)
        #expect(!truncated.contains(fakeCursorEnd))
        tui.addChild(MT1CursorComponent([truncated]))
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        #expect(terminal.output.contains("abc"))
        #expect(!terminal.output.contains("\u{1b}[7m"))
        #expect(!terminal.output.contains("\u{1b}_pi:"))
        #expect(terminal.output.contains(alt ? "\u{1b}[1;3H" : "\u{1b}[3G"))
    }

    @Test("keeps the cursor when an overlay ends directly left of it", arguments: [false, true])
    func overlayBoundary(hardware: Bool) async throws {
        let terminal = MT1CursorTerminal()
        let tui = TUI(terminal: terminal, showHardwareCursor: hardware)
        let recorder = MT1FrameRecorder()
        tui.registerRenderer(recorder)
        #expect(tui.switchRenderer(to: .mainScreen))
        tui.addChild(MT1CursorComponent(["abc" + systemCursorMarker + renderFakeCursor("d") + "ef"]))
        tui.showOverlay(MT1CursorComponent(["XXX"]), options: .init(width: 3, row: 0, col: 0))
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        let frame = try #require(recorder.frame)
        let line = try #require(frame.lines.first)
        #expect(stripTerminalSequences(line).replacingOccurrences(of: systemCursorMarker, with: "").hasPrefix("XXXdef"))
        #expect(line.contains("\u{1b}[7md") == !hardware)
        #expect(!line.contains("\u{1b}_pi:"))
        if hardware {
            #expect(frame.cursor == CursorPosition(row: 0, col: 3))
        } else {
            let marker = try #require(line.range(of: systemCursorMarker))
            #expect(visibleWidth(String(line[..<marker.lowerBound])) == 3)
        }
        // Swift keeps the existing rule that hides the hardware cursor under an overlay.
    }

    @Test("keeps APC and NUL markers at the start of a retained suffix")
    func retainedSuffixMarkers() {
        let apc = "\u{1b}_pi:c\u{07}"
        for marker in [apc, systemCursorMarker] {
            let result = extractSegments("abc" + marker + "def", beforeEnd: 3, afterStart: 3, afterLen: 3)
            #expect(result.before == "abc")
            #expect(result.after == marker + "def")
            #expect(result.afterWidth == 3)
        }
    }

    @Test("resolves focused and unfocused custom overlay cursors", arguments: [false, true])
    func overlayCursors(hardware: Bool) async {
        let terminal = MT1CursorTerminal()
        let tui = TUI(terminal: terminal, showHardwareCursor: hardware)
        tui.addChild(MT1CursorComponent(["background"]))
        tui.showOverlay(MT1CursorComponent([systemCursorMarker + renderFakeCursor("a") + renderFakeCursor("b") + "c"]),
            options: .init(width: 3, row: 0, col: 0))
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        #expect(terminal.output.contains("\u{1b}[7ma") == !hardware)
        #expect(terminal.output.contains("\u{1b}[7mb\u{1b}[27m"))
        #expect(!terminal.output.contains("\u{1b}_pi:"))
    }

    @Test("placeholder fake cursor is omitted in hardware mode and retains its text style", arguments: [false, true])
    func placeholder(hardware: Bool) async {
        let terminal = MT1CursorTerminal()
        let tui = TUI(terminal: terminal, showHardwareCursor: hardware)
        let input = Input(options: .init(prompt: "", placeholder: "Find", placeholderStyle: { "\u{1b}[2m" + $0 + "\u{1b}[22m" }))
        tui.addChild(input)
        tui.setFocus(input)
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        #expect(terminal.output.contains("\u{1b}[2mF\u{1b}[22m"))
        #expect(terminal.output.contains("\u{1b}[7m") == !hardware)
        #expect(!terminal.output.contains("\u{1b}_pi:"))
    }

    @Test("keeps the selection highlight after a fake cursor cell")
    func selectionAfterCursor() async {
        let terminal = MT1CursorTerminal(20, 4)
        let tui = TUI(terminal: terminal)
        tui.enableAltScreen(options: .init(copyOnSelect: false))
        #expect(tui.switchRenderer(to: .altScreen))
        tui.addChild(MT1CursorComponent(["> " + renderFakeCursor("a") + "bcd"]))
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        terminal.input?("\u{1b}[<0;1;1M")
        terminal.input?("\u{1b}[<32;6;1M")
        terminal.input?("\u{1b}[<3;6;1m")
        await mt1CursorWait(tui)
        #expect(terminal.output.contains("\u{1b}[27m\u{1b}[7mbcd"))
    }

    @Test("fullscreen stop output resolves fake cursors", arguments: [false, true])
    func stopOutput(hardware: Bool) async {
        let terminal = MT1CursorTerminal(20, 4)
        let tui = TUI(terminal: terminal, showHardwareCursor: hardware)
        tui.enableAltScreen()
        #expect(tui.switchRenderer(to: .altScreen))
        tui.addChild(MT1CursorComponent([systemCursorMarker + renderFakeCursor("a") + renderFakeCursor("b")]))
        tui.start()
        await mt1CursorWait(tui)
        terminal.writes = []
        tui.stop()
        #expect(terminal.output.contains("\u{1b}[7ma") == !hardware)
        #expect(terminal.output.contains("\u{1b}[7mb\u{1b}[27m"))
        #expect(!terminal.output.contains("\u{1b}_pi:"))
        #expect(!terminal.output.contains(systemCursorMarker))
    }

    @Test("scrolls the transcript on wheel input a focused overlay does not handle", arguments: [false, true])
    func wheelFallback(consumes: Bool) async {
        let terminal = MT1CursorTerminal(20, 6)
        let tui = TUI(terminal: terminal)
        let renderer = tui.enableAltScreen()
        #expect(tui.switchRenderer(to: .altScreen))
        tui.addChild(MT1CursorComponent((1...12).map { "line \($0)" }))
        tui.start()
        defer { tui.stop() }
        await mt1CursorWait(tui)
        let top = renderer.viewportTop
        let overlay = MT1CursorComponent(["overlay"])
        overlay.consumesWheel = consumes
        tui.showOverlay(overlay, options: .init(width: 10, anchor: .topLeft))
        await mt1CursorWait(tui)
        #expect(overlay.focused)
        terminal.input?("\u{1b}[<64;3;1M")
        await mt1CursorWait(tui)
        #expect(overlay.inputs.isEmpty)
        #expect(overlay.wheelEvents == (consumes ? 1 : 0))
        if consumes { #expect(renderer.viewportTop == top) }
        else { #expect(renderer.viewportTop < top) }
    }

    @Test("shows cursor at end of line before wrap, wraps on next char", arguments: [0, 1])
    func editorWrapCursor(padding: Int) {
        let editor = Editor(theme: defaultEditorTheme, options: .init(paddingX: padding))
        for ch in "aaaaaaaaa" { editor.handleInput(String(ch)) }
        let content = Array(editor.render(width: 10 + padding).dropFirst().dropLast())
        #expect(content.count == 1)
        #expect(content[0].hasSuffix(renderFakeCursor(" ")))
        editor.handleInput("a")
        #expect(editor.render(width: 10 + padding).dropFirst().dropLast().count == 2)
    }

    @Test("wraps at word boundaries instead of mid-word")
    func editorWordWrapping() {
        let editor = Editor(theme: defaultEditorTheme)
        editor.setText("Hello world this is a test of word wrapping functionality")
        let lines = editor.render(width: 40).dropFirst().dropLast().map {
            stripTerminalSequences($0).trimmingCharacters(in: .whitespaces)
        }
        #expect(!lines[0].hasSuffix("-"))
        for line in lines {
            #expect(line.isEmpty || line.range(of: "[\\w.,!?;:]$", options: .regularExpression) != nil)
        }
    }

    @Test("Herdr images stay off inside tmux and screen")
    func herdrMultiplexers() {
        for hints in [["TMUX": "/tmp/tmux"], ["STY": "session"], ["TERM": "screen-256color"], ["TERM": "tmux-256color"]] {
            let env = hints.merging(["TERM_PROGRAM": "herdr", "KITTY_WINDOW_ID": "1", "COLORTERM": "24bit"]) { _, new in new }
            let caps = detectCapabilities(environment: env, tmuxForwardsHyperlink: { true })
            #expect(caps.images == nil)
            #expect(caps.trueColor)
        }
        #expect(detectCapabilities(environment: ["TERM_PROGRAM": "herdr"]).images == .kitty)
    }
}
