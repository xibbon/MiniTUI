import Foundation
import Testing
@testable import MiniTui

private final class AltRecordingTerminal: Terminal {
    var columns: Int
    var rows: Int
    var kittyProtocolActive = false
    var writes: [String] = []
    var drainCalls: [(maxMs: Int, idleMs: Int)] = []
    private var onInput: ((String) -> Void)?
    private var onResize: (() -> Void)?

    init(columns: Int = 20, rows: Int = 5) {
        self.columns = columns
        self.rows = rows
    }

    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        self.onInput = onInput
        self.onResize = onResize
    }

    func stop() {
        onInput = nil
        onResize = nil
    }

    func drainInput(maxMs: Int, idleMs: Int) {
        drainCalls.append((maxMs, idleMs))
    }

    func write(_ data: String) { writes.append(data) }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}

    func sendInput(_ data: String) { onInput?(data) }
}

@MainActor
private final class AltLinesComponent: Component {
    var lines: [String]
    private(set) var widths: [Int] = []
    private(set) var inputs: [String] = []

    init(_ lines: [String]) {
        self.lines = lines
    }

    func render(width: Int) -> [String] {
        widths.append(width)
        return lines
    }

    func handleInput(_ data: String) {
        inputs.append(data)
    }
}

@MainActor
private func startAltTUI(
    terminal: Terminal,
    lines: [String],
    options: AltScreenRendererOptions = AltScreenRendererOptions(),
    scrollbar: ScrollViewScrollbar = .hidden
) async -> (TUI, AltScreenRenderer, AltLinesComponent, ScrollView) {
    let content = AltLinesComponent(lines)
    let scrollView = ScrollView(
        content,
        options: ScrollViewOptions(primary: true, scrollbar: scrollbar)
    )
    let tui = TUI(terminal: terminal)
    let renderer = tui.enableAltScreen(options: options)
    renderer.setLayoutRoot(scrollView)
    #expect(tui.switchRenderer(to: .altScreen))
    tui.start()
    await tui.waitForRender()
    return (tui, renderer, content, scrollView)
}

private func lastClipboardText(in writes: [String]) -> String? {
    let prefix = "\u{001B}]52;c;"
    for write in writes.reversed() {
        guard let start = write.range(of: prefix),
              let end = write[start.upperBound...].firstIndex(of: "\u{0007}") else {
            continue
        }
        let encoded = String(write[start.upperBound..<end])
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
    return nil
}

@Suite("Alternate-screen renderer", .serialized)
@MainActor
struct AltScreenRendererTests {
    @Test("enter and exit restore terminal state and remove Kitty images")
    func lifecycleSequences() {
        let terminal = AltRecordingTerminal()
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        // Pin the motion mode so this assertion does not depend on whether the test host runs
        // inside a multiplexer; `.auto` resolution is covered by its own test.
        let renderer = AltScreenRenderer(
            terminal: terminal,
            options: AltScreenRendererOptions(mouseMotion: .button)
        )
        renderer.start()
        setCapabilities(nil)
        renderer.stop(preserveScreen: true)

        let output = terminal.writes.joined()
        let enter = "\u{001B}[?1049h\u{001B}[?7l\u{001B}[?1000h\u{001B}[?1002h\u{001B}[?1004h\u{001B}[?1006h\u{001B}[2J\u{001B}[H\u{001B}[?25l"
        #expect(output.hasPrefix(enter))
        #expect(output.contains("\u{001B}[?2026h\u{001B}_Ga=d,d=A,q=2\u{001B}\\"))
        #expect(output.contains("\u{001B}[?1006l\u{001B}[?1004l\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1000l\u{001B}[?7h\u{001B}[?2026l"))
        #expect(output.hasSuffix("\u{001B}[?2026h\u{001B}[?1049l\u{001B}[?25h\u{001B}[?2026l"))
        #expect(terminal.drainCalls.count == 1)
    }

    @Test("auto mouse motion uses button-motion only inside a multiplexer")
    func autoMouseMotionResolution() {
        // Upstream: multiplexers lag when every pointer movement is forwarded, so they get
        // button-motion; everywhere else uses all-motion so hover feedback works.
        #expect(AltScreenMouseMotion.resolved(.auto, environment: [:]) == .all)
        #expect(AltScreenMouseMotion.resolved(.auto, environment: ["TERM": "xterm-256color"]) == .all)
        #expect(AltScreenMouseMotion.resolved(.auto, environment: ["TMUX": "/tmp/tmux-0/default"]) == .button)
        #expect(AltScreenMouseMotion.resolved(.auto, environment: ["ZELLIJ": "0"]) == .button)
        #expect(AltScreenMouseMotion.resolved(.auto, environment: ["STY": "1234.pts-0"]) == .button)
        #expect(AltScreenMouseMotion.resolved(.auto, environment: ["TERM": "screen.xterm"]) == .button)
        #expect(AltScreenMouseMotion.resolved(.auto, environment: ["TERM": "tmux-256color"]) == .button)
        // Explicit choices are never overridden.
        #expect(AltScreenMouseMotion.resolved(.all, environment: ["TMUX": "x"]) == .all)
        #expect(AltScreenMouseMotion.resolved(.button, environment: [:]) == .button)
    }

    @Test("all-motion mouse tracking is an explicit option")
    func allMotionOption() {
        let terminal = AltRecordingTerminal()
        let renderer = AltScreenRenderer(
            terminal: terminal,
            options: AltScreenRendererOptions(mouseMotion: .all)
        )
        renderer.start()
        #expect(terminal.writes.joined().contains("\u{001B}[?1003h"))
        renderer.stop(preserveScreen: true)
    }

    @Test("SGR mouse parser decodes buttons, motion, wheel, and modifiers")
    func mouseParsing() {
        let press = parseSgrMouseEvent("\u{001B}[<0;5;7M")
        #expect(press?.button == .primary)
        #expect(press?.x == 4)
        #expect(press?.y == 6)
        #expect(press?.release == false)

        let release = parseSgrMouseEvent("\u{001B}[<0;5;7m")
        #expect(release?.release == true)
        let drag = parseSgrMouseEvent("\u{001B}[<32;2;3M")
        #expect(drag?.motion == true)
        #expect(drag?.button == .primary)
        #expect(parseSgrMouseEvent("\u{001B}[<64;2;3M")?.button == .wheelUp)
        #expect(parseSgrMouseEvent("\u{001B}[<65;2;3M")?.button == .wheelDown)

        let modified = parseSgrMouseEvent("\u{001B}[<28;2;3M")
        #expect(modified?.modifiers == SgrMouseModifiers(shift: true, alt: true, control: true))
        #expect(parseSgrMouseEvent("\u{001B}[<0;2M") == nil)
        #expect(parseSgrMouseEvent("\u{001B}[<x;2;3M") == nil)
        #expect(parseSgrMouseEvent("\u{001B}[<0;0;3M") == nil)
        #expect(parseSgrMouseEvent("junk") == nil)
    }

    @Test("mouse reports never reach the focused component")
    func mouseIsConsumed() async {
        let terminal = AltRecordingTerminal()
        let (tui, _, content, _) = await startAltTUI(terminal: terminal, lines: ["hello"])
        tui.setFocus(content)
        terminal.sendInput("\u{001B}[<0;1;1M")
        terminal.sendInput("\u{001B}[<0;1;1m")
        await tui.waitForRender()
        #expect(content.inputs.isEmpty)
        tui.stop()
    }

    @Test("wheel, page, Home, and End move the viewport")
    func viewportNavigation() async {
        let terminal = VirtualTerminal(columns: 12, rows: 6)
        let lines = (0..<20).map { "line-\($0)" }
        let (tui, renderer, _, _) = await startAltTUI(
            terminal: terminal,
            lines: lines,
            options: AltScreenRendererOptions(wheelScrollLines: 2)
        )

        terminal.sendInput("\u{001B}[<65;1;1M")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 2)
        terminal.sendInput("\u{001B}[6~")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 4)
        terminal.sendInput("\u{001B}[H")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 0)
        terminal.sendInput("\u{001B}[F")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 14)
        tui.stop()
    }

    @Test("scrollbar reserves only the always-visible column and dragging is proportional")
    func scrollbarModesAndDragging() async {
        let probe = AltLinesComponent((0..<20).map { "row-\($0)" })
        let scrollView = ScrollView(
            probe,
            options: ScrollViewOptions(primary: true, scrollbar: .always)
        )
        var frame = renderLayoutFrame(root: scrollView, width: 10, height: 5) {}
        #expect(probe.widths.last == 9)
        #expect(getScrollbarGeometry(frame.root)?.maxScrollTop == 15)
        scrollView.setScrollbar(.hidden)
        frame = renderLayoutFrame(root: scrollView, width: 10, height: 5) {}
        #expect(probe.widths.last == 10)
        #expect(getScrollbarGeometry(frame.root) == nil)

        let terminal = VirtualTerminal(columns: 10, rows: 5)
        let (tui, renderer, _, _) = await startAltTUI(
            terminal: terminal,
            lines: (0..<20).map { "row-\($0)" },
            scrollbar: .always
        )
        terminal.sendInput("\u{001B}[<0;10;1M")
        terminal.sendInput("\u{001B}[<32;10;5M")
        terminal.sendInput("\u{001B}[<0;10;5m")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 15)
        tui.stop()
    }

    @Test("drag selection maps wide characters to complete graphemes")
    func wideCharacterSelection() async {
        let terminal = AltRecordingTerminal(columns: 12, rows: 3)
        let (tui, _, _, _) = await startAltTUI(terminal: terminal, lines: ["A界B"])
        terminal.writes.removeAll()
        terminal.sendInput("\u{001B}[<0;2;1M")
        terminal.sendInput("\u{001B}[<32;4;1M")
        terminal.sendInput("\u{001B}[<0;4;1m")
        await Task.yield()
        await tui.waitForRender()
        #expect(lastClipboardText(in: terminal.writes) == "界B")
        tui.stop()
    }

    @Test("double-click selects a word and triple-click selects a line")
    func clickGranularity() async {
        let terminal = AltRecordingTerminal(columns: 20, rows: 5)
        let (tui, _, _, _) = await startAltTUI(
            terminal: terminal,
            lines: ["alpha", "beta word", "", "other"]
        )
        terminal.writes.removeAll()
        for _ in 0..<2 {
            terminal.sendInput("\u{001B}[<0;7;2M")
            terminal.sendInput("\u{001B}[<0;7;2m")
        }
        await Task.yield()
        await tui.waitForRender()
        #expect(lastClipboardText(in: terminal.writes) == "word")
        terminal.sendInput("\u{001B}[<0;7;2M")
        terminal.sendInput("\u{001B}[<0;7;2m")
        await Task.yield()
        await tui.waitForRender()
        // Upstream's triple-click granularity is a single line, not a paragraph.
        #expect(lastClipboardText(in: terminal.writes) == "beta word")
        tui.stop()
    }

    @Test("edge drag auto-scroll advances selection viewport")
    func edgeAutoScroll() async {
        let terminal = VirtualTerminal(columns: 12, rows: 3)
        let (tui, renderer, _, _) = await startAltTUI(
            terminal: terminal,
            lines: (0..<20).map { "line-\($0)" }
        )
        terminal.sendInput("\u{001B}[<0;1;2M")
        terminal.sendInput("\u{001B}[<32;1;4M")
        try? await Task.sleep(for: .milliseconds(140))
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop > 0)
        terminal.sendInput("\u{001B}[<0;1;4m")
        tui.stop()
    }

    @Test("OSC 133 prompt navigation uses semantic prompt zones")
    func promptNavigation() async {
        let terminal = VirtualTerminal(columns: 20, rows: 3)
        let marker = "\u{001B}]133;A\u{0007}"
        let lines = ["zero", "one", "two", marker + "prompt-1", "four", "five", "six", marker + "prompt-2", "eight", "nine"]
        let (tui, renderer, _, _) = await startAltTUI(terminal: terminal, lines: lines)

        terminal.sendInput("\u{001B}[1;6B")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 3)
        terminal.sendInput("\u{001B}[1;6B")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 7)
        terminal.sendInput("\u{001B}[1;6A")
        await terminal.waitForRender(tui)
        #expect(renderer.viewportTop == 3)
        tui.stop()
    }

    @Test("main and alternate renderer swap does not replay document content")
    func rendererSwap() async {
        let terminal = AltRecordingTerminal(columns: 20, rows: 4)
        let tui = TUI(terminal: terminal)
        tui.addChild(AltLinesComponent(["first", "second"]))
        tui.start()
        await tui.waitForRender()
        let renderer = tui.enableAltScreen()
        #expect(tui.switchRenderer(to: .altScreen))
        await tui.waitForRender()

        terminal.writes.removeAll()
        #expect(tui.switchRenderer(to: .mainScreen))
        await tui.waitForRender()
        let output = terminal.writes.joined()
        #expect(!output.contains("\r\u{001B}[2Kfirst"))
        #expect(!output.contains("\r\u{001B}[2Ksecond"))
        #expect(renderer.mode == .altScreen)
        tui.stop()
    }

    @Test("alternate navigation and prompt history actions are rebindable")
    func rebindableActions() {
        let defaults = TUIKeybindingsManager()
        #expect(defaults.getKeys(TUIKeybinding.altScreenHalfPageUp).isEmpty)
        #expect(defaults.getKeys(TUIKeybinding.altScreenHalfPageDown).isEmpty)
        #expect(defaults.getKeys(TUIKeybinding.editorCursorLineStart).contains(Key.ctrl(Key.home)))
        #expect(defaults.getKeys(TUIKeybinding.editorCursorLineEnd).contains(Key.ctrl(Key.end)))
        #expect(defaults.getKeys(TUIKeybinding.editorPageUp).contains(Key.ctrl(Key.pageUp)))
        #expect(defaults.getKeys(TUIKeybinding.editorPageDown).contains(Key.ctrl(Key.pageDown)))

        let previous = getKeybindings()
        defer { setKeybindings(previous) }
        let rebound = TUIKeybindingsManager(userBindings: [
            TUIKeybinding.editorHistoryPrevious: [Key.ctrl("p")],
            TUIKeybinding.editorHistoryNext: [Key.ctrl("n")],
        ])
        setKeybindings(rebound)
        let editor = Editor(theme: defaultEditorTheme)
        editor.addToHistory("older")
        editor.addToHistory("newer")
        editor.handleInput("\u{0010}")
        #expect(editor.getText() == "newer")
        editor.handleInput("\u{000E}")
        #expect(editor.getText().isEmpty)
    }

    @Test("Kitty images clip to layout and moving a placement does not retransmit payload")
    func kittyImageClippingAndPlacementReuse() {
        let savedCellDimensions = getCellDimensions()
        defer {
            setCellDimensions(savedCellDimensions)
            setCapabilities(nil)
        }
        setCellDimensions(CellDimensions(widthPx: 9, heightPx: 18))
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        guard let image = renderImage(
            base64Data: "AAAA",
            imageDimensions: ImageDimensions(widthPx: 9, heightPx: 9),
            options: ImageRenderOptions(maxWidthCells: 4)
        ) else {
            Issue.record("Expected a Kitty image")
            return
        }
        #expect(image.rows == 2)

        let clipped = renderLayoutFrame(
            root: AltLinesComponent([image.sequence]),
            width: 4,
            height: 1
        ) {}
        #expect(clipped.lines[0].contains("r=1"))

        let terminal = AltRecordingTerminal(columns: 4, rows: 2)
        let renderer = AltScreenRenderer(terminal: terminal)
        renderer.start()
        renderer.present(TuiRenderFrame(
            lines: [image.sequence, ""],
            cursor: nil,
            width: 4,
            height: 2,
            clearOnShrink: false,
            hasOverlayEntries: false,
            hasVisibleOverlay: false,
            useSystemCursor: false
        ))
        terminal.writes.removeAll()
        renderer.present(TuiRenderFrame(
            lines: ["", image.sequence],
            cursor: nil,
            width: 4,
            height: 2,
            clearOnShrink: false,
            hasOverlayEntries: false,
            hasVisibleOverlay: false,
            useSystemCursor: false
        ))
        let moved = terminal.writes.joined()
        #expect(moved.contains("a=p,q=2"))
        #expect(!moved.contains(";AAAA"))
        renderer.stop(preserveScreen: true)
    }
}
