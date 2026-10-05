import Foundation
import Testing
@testable import MiniTui

private final class B2Terminal: Terminal {
    let screen: VirtualTerminal
    var writes: [String] = []
    var columns: Int { screen.columns }
    var rows: Int { screen.rows }
    var kittyProtocolActive: Bool { false }
    init(_ columns: Int = 20, _ rows: Int = 4) { screen = VirtualTerminal(columns: columns, rows: rows) }
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) { screen.start(onInput: onInput, onResize: onResize) }
    func stop() { screen.stop() }
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) {
        writes.append(data)
        // The legacy test terminal frame parser expects CRLF rows. Use its cell buffer for CUP rows.
        screen.write(data.replacingOccurrences(of: "\u{1b}[?2026h", with: "").replacingOccurrences(of: "\u{1b}[?2026l", with: ""))
    }
    func moveBy(lines: Int) { screen.moveBy(lines: lines) }
    func hideCursor() {}
    func showCursor() {}
    func clearLine() { screen.clearLine() }
    func clearFromCursor() { screen.clearFromCursor() }
    func clearScreen() { screen.clearScreen() }
    func setTitle(_ title: String) {}
    func send(_ data: String) { screen.sendInput(data) }
    var viewport: [String] { screen.getViewport() }
    var output: String { writes.joined() }
    func mouse(_ code: Int, _ column: Int, _ row: Int, release: Bool = false) {
        send("\u{1b}[<\(code);\(column);\(row)\(release ? "m" : "M")")
    }
    func click(_ column: Int, _ row: Int) { mouse(0, column, row); mouse(0, column, row, release: true) }
    func select(releaseCode: Int = 0) { mouse(0, 1, 1); mouse(32, 4, 2); mouse(releaseCode, 4, 2, release: true) }
}

@MainActor
private final class B2Control: Component, Focusable {
    var focused = false
    var lines: [String]
    var inputs: [String] = []
    var renderCount = 0
    var onMouse: ((TuiMouseEvent) -> TuiMouseEventResult?)?
    init(_ lines: [String] = ["control"]) { self.lines = lines }
    func render(width: Int) -> [String] { renderCount += 1; return lines }
    func handleInput(_ data: String) { inputs.append(data) }
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? { onMouse?(event) }
}

@MainActor
private final class B2InputOverlay: Container, MouseFocusOwner, Focusable {
    let input = Input()
    var focused = false
    override init() { super.init(); addChild(input) }
    override func handleInput(_ data: String) { input.handleInput(data) }
}

@MainActor
private final class B2LayoutMouseContainer: Container, LayoutComponent {
    let child = B2Control(["one"])
    var clicks = 0
    var layoutNode: LayoutNode {
        .stack(StackLayoutNode(type: .hstack, entries: [
            StackLayoutEntry(component: child, basis: .points(3)),
            StackLayoutEntry(component: child, basis: .points(3)),
        ], gap: 2))
    }
    override func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        guard event.type == .click else { return nil }
        clicks += 1
        return TuiMouseEventResult(handled: true)
    }
}

@MainActor
private func b2Wait(_ tui: TUI) async {
    // Input enters TUI through a MainActor task. Drain it before waiting for the render timer.
    await Task.yield()
    await tui.waitForRender()
    await Task.yield()
    await tui.waitForRender()
}

@MainActor
private func b2Start(_ terminal: B2Terminal, root: any Component,
                     options: AltScreenRendererOptions = .init()) async -> (TUI, AltScreenRenderer) {
    let tui = TUI(terminal: terminal)
    let renderer = tui.enableAltScreen(options: options)
    renderer.setLayoutRoot(root)
    #expect(tui.switchRenderer(to: .altScreen))
    tui.start()
    await b2Wait(tui)
    return (tui, renderer)
}

@MainActor
private func b2Transcript(_ count: Int, follow: ScrollViewFollow = .end,
                          scrollbar: ScrollViewScrollbar = .hidden) -> ScrollView {
    ScrollView(B2Control((1...count).map { "line \($0)" }), options: .init(follow: follow, primary: true, scrollbar: scrollbar))
}

@MainActor
private func b2Dock(_ transcript: ScrollView, _ dock: any Component) -> VStack {
    VStack(children: [.entry(StackEntry(transcript, options: .init(basis: .points(0), grow: 1, minSize: 1))),
                      .entry(StackEntry(dock, options: .init(basis: .auto, minSize: 1)))])
}

@Suite("B2 alternate-screen integration", .serialized)
@MainActor
struct B2AltScreenRendererTests {
    @Test("Right-click paste is limited to Windows outside VS Code")
    func rightClickPastePredicate() {
        let press = SgrMouseEvent(rawButton: 2, x: 0, y: 0, release: false)
        #expect(shouldHandleAltScreenRightClickPaste(press, isWindows: true, environment: [:]))
        #expect(!shouldHandleAltScreenRightClickPaste(press, isWindows: true, environment: ["TERM_PROGRAM": "vscode"]))
        #expect(!shouldHandleAltScreenRightClickPaste(press, isWindows: true, environment: ["TERM_PROGRAM": "VSCode"]))
        #expect(!shouldHandleAltScreenRightClickPaste(press, isWindows: false, environment: [:]))
        for code in [0, 3, 6, 10, 18, 34] {
            #expect(!shouldHandleAltScreenRightClickPaste(SgrMouseEvent(rawButton: code, x: 0, y: 0, release: false), isWindows: true, environment: [:]))
        }
        #expect(!shouldHandleAltScreenRightClickPaste(SgrMouseEvent(rawButton: 2, x: 0, y: 0, release: true), isWindows: true, environment: [:]))
    }

    @Test("Jump-to-end label is confined to the transcript and accepts clicks")
    func jumpIndicator() async {
        let terminal = B2Terminal(30, 6)
        let transcript = b2Transcript(8)
        let (tui, _) = await b2Start(terminal, root: b2Dock(transcript, B2Control(["editor", "footer"])),
                                   options: .init(scrollToEndIndicator: { "\u{1b}[7m ↓ Jump to end \u{1b}[27m" }))
        defer { tui.stop() }
        #expect(!terminal.viewport.contains { $0.contains("Jump to end") })
        terminal.mouse(64, 1, 1)
        await b2Wait(tui)
        #expect(!transcript.isFollowingEnd)
        #expect(terminal.viewport[3].contains("Jump to end"))
        #expect(terminal.viewport[4] == "editor")
        terminal.click(2, 4)
        await b2Wait(tui)
        #expect(!transcript.isFollowingEnd)
        terminal.click(15, 4)
        await b2Wait(tui)
        #expect(transcript.isFollowingEnd)
        #expect(terminal.viewport == ["line 5", "line 6", "line 7", "line 8", "editor", "footer"])
    }

    @Test("A full-width jump label leaves the scrollbar available")
    func jumpDoesNotCoverScrollbar() async {
        let terminal = B2Terminal(30, 6)
        let transcript = b2Transcript(12, scrollbar: .always)
        let (tui, _) = await b2Start(terminal, root: b2Dock(transcript, B2Control(["editor", "footer"])),
                                   options: .init(scrollToEndIndicator: { String(repeating: "↓", count: 30) }))
        defer { tui.stop() }
        terminal.mouse(64, 1, 1)
        await b2Wait(tui)
        terminal.click(30, 4)
        await b2Wait(tui)
        #expect(!transcript.isFollowingEnd)
    }

    @Test("Jump label requires follow-end")
    func jumpRequiresFollow() async {
        let terminal = B2Terminal(30, 3)
        let (tui, _) = await b2Start(terminal, root: b2Transcript(5, follow: .none),
                                   options: .init(scrollToEndIndicator: { " ↓ Jump to end " }))
        defer { tui.stop() }
        #expect(!terminal.viewport.contains { $0.contains("Jump to end") })
    }

    @Test("Hidden auto track appears on pointer entry and hides after exit")
    func hiddenAutoHover() async {
        let terminal = B2Terminal(10, 5)
        let scroll = ScrollView(B2Control((1...12).map { "line \($0)" }), options: .init(primary: true, scrollbar: .auto, scrollbarHideDelayMilliseconds: 20))
        let (tui, _) = await b2Start(terminal, root: scroll)
        defer { tui.stop() }
        #expect(!scroll.isScrollbarVisible)
        terminal.mouse(35, 10, 3)
        await b2Wait(tui)
        #expect(scroll.isScrollbarVisible)
        #expect(scroll.isScrollbarActive)
        #expect(terminal.viewport.contains { $0.contains("█") })
        terminal.mouse(35, 9, 3)
        try? await Task.sleep(for: .milliseconds(50))
        await b2Wait(tui)
        #expect(!scroll.isScrollbarVisible)
    }

    @Test("Track press jumps and then drag reaches the end without copying")
    func scrollbarTrackJump() async {
        let terminal = B2Terminal(10, 10)
        let scroll = b2Transcript(50, follow: .none, scrollbar: .always)
        let (tui, _) = await b2Start(terminal, root: scroll)
        defer { tui.stop() }
        terminal.mouse(0, 10, 6)
        await b2Wait(tui)
        #expect(scroll.scrollTop == 20)
        terminal.mouse(32, 10, 10)
        await b2Wait(tui)
        #expect(scroll.scrollTop == 40)
        terminal.mouse(0, 10, 10, release: true)
        await b2Wait(tui)
        #expect(!terminal.output.contains("\u{1b}]52;c;"))
    }

    @Test("Injected copy takes priority over OSC 52")
    func injectedCopy() async {
        let terminal = B2Terminal()
        var copied: [String] = []
        let (tui, renderer) = await b2Start(terminal, root: B2Control(["alpha", "beta", "gamma", "delta"]),
            options: .init(copySelection: { copied.append($0); return true }))
        defer { tui.stop() }
        #expect(renderer.getCopyOnSelect())
        terminal.select()
        await Task.yield()
        await b2Wait(tui)
        #expect(copied == ["alpha\nbeta"])
        #expect(!terminal.output.contains("\u{1b}]52;c;"))
        #expect(terminal.viewport.contains { $0.contains("Copied!") })
    }

    @Test("Disabled automatic copy retains the selection and permits explicit copy")
    func copyOnSelectAndProgrammaticCopy() async {
        let terminal = B2Terminal()
        var copied: [String] = []
        let (tui, renderer) = await b2Start(terminal, root: B2Control(["alpha", "beta", "gamma", "delta"]),
            options: .init(copyOnSelect: false, copySelection: { copied.append($0); return true }))
        defer { tui.stop() }
        #expect(!renderer.getCopyOnSelect())
        #expect(!renderer.hasActiveSelection())
        #expect(await !renderer.copyActiveSelectionToClipboard())
        terminal.select()
        await b2Wait(tui)
        #expect(copied.isEmpty)
        #expect(renderer.hasActiveSelection())
        #expect(terminal.output.contains("\u{1b}[7m"))
        #expect(!terminal.viewport.contains { $0.contains("Copied!") })
        #expect(await renderer.copyActiveSelectionToClipboard())
        await b2Wait(tui)
        #expect(copied == ["alpha\nbeta"])
        renderer.setCopyOnSelect(true)
        #expect(renderer.getCopyOnSelect())
    }

    @Test("Copy failure flashes an error without OSC 52")
    func copyFailure() async {
        let terminal = B2Terminal()
        let (tui, _) = await b2Start(terminal, root: B2Control(["alpha", "beta", "gamma", "delta"]),
            options: .init(copySelection: { _ in false }))
        defer { tui.stop() }
        terminal.select()
        await Task.yield()
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("Copy failed") })
        #expect(!terminal.output.contains("\u{1b}]52;c;"))
    }

    @Test("Generic release copies selected text and reapplies inverse after an embedded reset")
    func genericReleaseAndStyleReset() async {
        let terminal = B2Terminal()
        let (tui, _) = await b2Start(terminal, root: B2Control(["\u{1b}[1mal\u{1b}[0mpha", "beta", "gamma", "delta"]))
        defer { tui.stop() }
        terminal.select(releaseCode: 3)
        await Task.yield()
        await b2Wait(tui)
        let encoded = Data("alpha\nbeta".utf8).base64EncodedString()
        #expect(terminal.output.contains("\u{1b}]52;c;\(encoded)\u{7}"))
        #expect(terminal.output.contains("al\u{1b}[0m\u{1b}[7mpha"))
    }

    @Test("Double-click keeps slash and hyphen joined words whole")
    func joinedWords() async {
        for (line, needle) in [("extensions/starline/fixed-editor/compositor.ts", "starline"), ("earendil-works/pi-tui", "works")] {
            let terminal = B2Terminal(80, 1)
            var copied: [String] = []
            let (tui, _) = await b2Start(terminal, root: B2Control([line]), options: .init(copySelection: { copied.append($0); return true }))
            let index = line.distance(from: line.startIndex, to: line.range(of: needle)!.lowerBound) + 1
            terminal.click(index, 1); terminal.click(index, 1)
            await Task.yield()
            await b2Wait(tui)
            #expect(copied == [line])
            tui.stop()
        }
    }

    @Test("Generic and specific release open links but drag does not")
    func linkRelease() async {
        let terminal = B2Terminal(20, 3)
        let urls = ["https://example.com/path?q=1", "https://example.com/bel", "https://example.com/emoji"]
        var opened: [String] = []
        let lines = urls.enumerated().map { index, url in "\u{1b}]8;;\(url)\u{7}\(index == 2 ? "🙂" : "link")\u{1b}]8;;\u{7}" }
        let (tui, _) = await b2Start(terminal, root: B2Control(lines), options: .init(openURL: { opened.append($0) }))
        defer { tui.stop() }
        terminal.mouse(0, 2, 1); terminal.mouse(3, 2, 1, release: true)
        await b2Wait(tui)
        terminal.click(2, 2); terminal.click(2, 3)
        await b2Wait(tui)
        #expect(opened == urls)
        terminal.mouse(0, 2, 1); terminal.mouse(32, 4, 1); terminal.mouse(0, 4, 1, release: true)
        await b2Wait(tui)
        #expect(opened == urls)
    }

    @Test("Idle and zero-width selections do not repaint on focus change")
    func idleFocus() async {
        let terminal = B2Terminal()
        let (tui, _) = await b2Start(terminal, root: B2Control(["alpha", "beta", "gamma", "delta"]))
        defer { tui.stop() }
        let idleWrites = terminal.writes.count
        terminal.send("\u{1b}[O"); terminal.send("\u{1b}[I")
        await b2Wait(tui)
        #expect(terminal.writes.count == idleWrites)
        terminal.click(1, 1)
        terminal.mouse(32, 4, 2); terminal.mouse(0, 4, 2, release: true)
        await b2Wait(tui)
        #expect(!terminal.output.contains("\u{1b}]52;c;"))
        terminal.mouse(0, 1, 3)
        await b2Wait(tui)
        let pressedWrites = terminal.writes.count
        terminal.send("\u{1b}[O"); terminal.send("\u{1b}[I")
        await b2Wait(tui)
        #expect(terminal.writes.count == pressedWrites)
        terminal.mouse(32, 4, 2); terminal.mouse(0, 4, 2, release: true)
        await b2Wait(tui)
        #expect(!terminal.output.contains("\u{1b}]52;c;"))
    }

    @Test("Focus loss clears an unfinished visible selection and rejects orphan events")
    func activeFocusLoss() async {
        let terminal = B2Terminal()
        let (tui, renderer) = await b2Start(terminal, root: B2Control(["alpha", "beta", "gamma", "delta"]))
        defer { tui.stop() }
        terminal.mouse(0, 1, 1); terminal.mouse(32, 4, 2)
        await b2Wait(tui)
        #expect(renderer.hasActiveSelection())
        terminal.writes.removeAll()
        terminal.send("\u{1b}[O"); terminal.send("\u{1b}[I")
        await b2Wait(tui)
        #expect(!renderer.hasActiveSelection())
        #expect(terminal.output.contains("alpha"))
        #expect(!terminal.output.contains("\u{1b}[7m"))
        terminal.mouse(32, 4, 2); terminal.mouse(0, 4, 2, release: true)
        await b2Wait(tui)
        #expect(!terminal.output.contains("\u{1b}]52;c;"))
    }

    @Test("Completed visible selection remains after focus changes")
    func completedFocus() async {
        let terminal = B2Terminal()
        let (tui, renderer) = await b2Start(terminal, root: B2Control(["alpha", "beta", "gamma", "delta"]), options: .init(copyOnSelect: false))
        defer { tui.stop() }
        terminal.select()
        await b2Wait(tui)
        let writes = terminal.writes.count
        terminal.send("\u{1b}[O"); terminal.send("\u{1b}[I")
        await b2Wait(tui)
        #expect(terminal.writes.count == writes)
        #expect(renderer.hasActiveSelection())
        terminal.writes.removeAll()
        tui.requestRender(force: true)
        await b2Wait(tui)
        #expect(terminal.output.contains("\u{1b}[7m"))
    }

    @Test("Nested mouse region click leaves drag selection available")
    func regionClickAndDrag() async {
        let terminal = B2Terminal(20, 2)
        var clicks = 0
        let region = MouseRegion(child: B2Control(["clickable", "selectable"])) { event in
            guard event.type == .click else { return nil }
            clicks += 1
            return TuiMouseEventResult(handled: true)
        }
        let (tui, _) = await b2Start(terminal, root: region)
        defer { tui.stop() }
        terminal.click(2, 1)
        await b2Wait(tui)
        #expect(clicks == 1)
        terminal.select()
        await Task.yield()
        await b2Wait(tui)
        #expect(clicks == 1)
        #expect(terminal.output.contains("\u{1b}]52;c;"))
    }

    @Test("Handled press focuses and captures drag outside the component")
    func captureAndFocus() async {
        let terminal = B2Terminal(20, 2)
        let control = B2Control()
        var events: [TuiMouseEventType] = []
        control.onMouse = { event in
            events.append(event.type)
            return event.type == .press ? TuiMouseEventResult(handled: true, capture: true, focus: true) : TuiMouseEventResult(handled: true)
        }
        let (tui, renderer) = await b2Start(terminal, root: control)
        defer { tui.stop() }
        terminal.mouse(0, 1, 1); terminal.mouse(32, 5, 2); terminal.mouse(0, 5, 2, release: true)
        await b2Wait(tui)
        #expect(events == [.press, .drag, .release])
        #expect(control.focused)
        #expect(!renderer.hasActiveSelection())
    }

    @Test("Component click counts cycle from one through three")
    func componentClickCounts() async {
        let terminal = B2Terminal(20, 1)
        let control = B2Control()
        var counts: [Int] = []
        control.onMouse = { event in
            if event.type == .press { return TuiMouseEventResult(handled: true) }
            if event.type == .click { counts.append(event.clickCount ?? 0); return TuiMouseEventResult(handled: true) }
            return nil
        }
        let (tui, _) = await b2Start(terminal, root: control)
        defer { tui.stop() }
        for _ in 0..<4 { terminal.click(1, 1) }
        await b2Wait(tui)
        #expect(counts == [1, 2, 3, 1])
    }

    @Test("Handled pointer motion does not request a render by default")
    func noOpPointerMove() async {
        let terminal = B2Terminal(20, 2)
        let control = B2Control()
        control.onMouse = { $0.type == .move ? TuiMouseEventResult(handled: true) : nil }
        let (tui, _) = await b2Start(terminal, root: control)
        defer { tui.stop() }
        let count = control.renderCount
        let writes = terminal.writes.count
        terminal.mouse(35, 1, 1)
        await b2Wait(tui)
        #expect(control.renderCount == count)
        #expect(terminal.writes.count == writes)
    }

    @Test("Mouse dispatch honors explicit render flags")
    func explicitRenderFlags() async {
        let terminal = B2Terminal(20, 2)
        let control = B2Control()
        control.onMouse = { event in TuiMouseEventResult(handled: true, render: event.type == .move) }
        let (tui, _) = await b2Start(terminal, root: control)
        defer { tui.stop() }
        let count = control.renderCount
        terminal.mouse(0, 1, 1)
        await b2Wait(tui)
        #expect(control.renderCount == count)
        terminal.mouse(35, 2, 1)
        await b2Wait(tui)
        #expect(control.renderCount > count)
    }

    @Test("Mouse components can consume wheel input before viewport scrolling")
    func consumedWheel() async {
        let terminal = B2Terminal(20, 3)
        var wheels = 0
        let region = MouseRegion(child: B2Control((1...8).map { "line \($0)" })) { event in
            guard event.type == .wheel else { return nil }
            wheels += 1
            return TuiMouseEventResult(handled: true)
        }
        let scroll = ScrollView(region, options: .init(follow: .end, primary: true))
        let (tui, renderer) = await b2Start(terminal, root: scroll)
        defer { tui.stop() }
        let top = renderer.viewportTop
        terminal.mouse(64, 1, 1)
        await b2Wait(tui)
        #expect(wheels == 1)
        #expect(renderer.viewportTop == top)
    }

    @Test("Horizontal layout misses do not dispatch to an unrelated child")
    func horizontalMiss() async {
        let terminal = B2Terminal(20, 2)
        let left = B2Control(["left", "left"])
        var events = 0
        left.onMouse = { _ in events += 1; return TuiMouseEventResult(handled: true) }
        let root = HStack(children: [.entry(StackEntry(left, options: .init(basis: .points(10)))),
                                    .entry(StackEntry(B2Control(["plain"]), options: .init(basis: .points(10))))])
        let (tui, _) = await b2Start(terminal, root: root)
        defer { tui.stop() }
        terminal.click(15, 1)
        await b2Wait(tui)
        #expect(events == 0)
    }

    @Test("A plain container can dispatch through a nested scroll view")
    func nestedScrollDispatchInPlainContainer() async {
        let terminal = B2Terminal(20, 3)
        let control = B2Control()
        var clicks = 0
        control.onMouse = { event in
            guard event.type == .click else { return nil }
            clicks += 1
            return TuiMouseEventResult(handled: true)
        }
        let container = Container()
        container.addChild(ScrollView(control))
        let root = VStack(children: [.component(container)])
        let (tui, _) = await b2Start(terminal, root: root)
        defer { tui.stop() }
        terminal.click(1, 1)
        await b2Wait(tui)
        #expect(clicks == 1)
    }

    @Test("A custom layout container receives clicks in its layout gap")
    func customLayoutContainerMouseOverride() async {
        let terminal = B2Terminal(10, 2)
        let root = B2LayoutMouseContainer()
        let (tui, _) = await b2Start(terminal, root: root)
        defer { tui.stop() }
        terminal.click(4, 1)
        await b2Wait(tui)
        #expect(root.clicks == 1)
    }

    @Test("Copied selection retains indentation on its first line")
    func copyPreservesIndentation() async {
        let terminal = B2Terminal()
        var copied: [String] = []
        let (tui, _) = await b2Start(terminal, root: B2Control(["  alpha", "beta"]), options: .init(copySelection: { copied.append($0); return true }))
        defer { tui.stop() }
        terminal.select()
        await b2Wait(tui)
        #expect(copied == ["  alpha\nbeta"])
    }

    @Test("Focused overlay receives wheel and viewport keys")
    func focusedOverlayNavigation() async {
        let terminal = B2Terminal(20, 6)
        let (tui, renderer) = await b2Start(terminal, root: b2Transcript(12))
        defer { tui.stop() }
        let top = renderer.viewportTop
        let overlay = B2Control(["overlay"])
        let handle = tui.showOverlay(overlay)
        await b2Wait(tui)
        #expect(overlay.focused)
        let keys = ["\u{1b}[5~", "\u{1b}[6~", "\u{1b}OH", "\u{1b}OF", "\u{1b}[<64;10;3M"]
        for key in keys { terminal.send(key) }
        await b2Wait(tui)
        #expect(overlay.inputs == keys)
        #expect(renderer.viewportTop == top)
        handle.hide()
        await b2Wait(tui)
        terminal.send("\u{1b}[5~")
        await b2Wait(tui)
        #expect(renderer.viewportTop < top)
    }

    @Test("Unfocused overlays do not take viewport keys")
    func unfocusedOverlayNavigation() async {
        let terminal = B2Terminal(20, 6)
        let (tui, renderer) = await b2Start(terminal, root: b2Transcript(12))
        defer { tui.stop() }
        let top = renderer.viewportTop
        let hidden = tui.showOverlay(B2Control())
        hidden.setHidden(true)
        let nonCapturing = B2Control()
        _ = tui.showOverlay(nonCapturing, options: .init(nonCapturing: true))
        let unfocused = B2Control()
        _ = tui.showOverlay(unfocused)
        // Swift overlay handles have no unfocus operation. Restore a separate input owner.
        tui.setFocus(B2Control())
        await b2Wait(tui)
        #expect(!nonCapturing.focused)
        #expect(!unfocused.focused)
        terminal.send("\u{1b}[5~"); terminal.mouse(64, 10, 3)
        await b2Wait(tui)
        #expect(renderer.viewportTop < top)
        #expect(nonCapturing.inputs.isEmpty && unfocused.inputs.isEmpty)
    }

    @Test("Single-line viewport actions use the configured keys")
    func singleLineNavigation() async {
        let original = getKeybindings()
        defer { setKeybindings(original) }
        setKeybindings(TUIKeybindingsManager(userBindings: [TUIKeybinding.altScreenLineUp: [Key.ctrl("y")], TUIKeybinding.altScreenLineDown: [Key.ctrl("e")]]))
        let terminal = B2Terminal(20, 10)
        let (tui, renderer) = await b2Start(terminal, root: b2Transcript(30))
        defer { tui.stop() }
        #expect(renderer.viewportTop == 20)
        terminal.send("\u{19}")
        await b2Wait(tui)
        #expect(renderer.viewportTop == 19)
        terminal.send("\u{5}")
        await b2Wait(tui)
        #expect(renderer.viewportTop == 20)
    }

    @Test("Nested input clicks retain the delegating overlay focus")
    func nestedOverlayInput() async {
        let terminal = B2Terminal(20, 4)
        let (tui, _) = await b2Start(terminal, root: B2Control(["transcript"]))
        defer { tui.stop() }
        let overlay = B2InputOverlay()
        overlay.input.setValue("hi")
        _ = tui.showOverlay(overlay, options: .init(width: .absolute(20), anchor: .topLeft))
        await b2Wait(tui)
        terminal.click(5, 1)
        terminal.send("!")
        await b2Wait(tui)
        #expect(overlay.input.getValue() == "hi!")
        #expect(overlay.focused)
    }

    @Test("Editor click places the cursor and focuses the editor")
    func editorClick() async {
        let terminal = B2Terminal(20, 6)
        let editor = Editor(theme: defaultEditorTheme)
        editor.setText("hello")
        let (tui, _) = await b2Start(terminal, root: editor)
        defer { tui.stop() }
        terminal.click(3, 2)
        terminal.send("X")
        await b2Wait(tui)
        #expect(editor.getText() == "heXllo")
        #expect(tui.getFocusedComponent() === editor)
    }

    @Test("Drag over editor selects text without moving its cursor")
    func editorDrag() async {
        let terminal = B2Terminal(20, 6)
        let editor = Editor(theme: defaultEditorTheme)
        editor.setText("hello world")
        var copied: [String] = []
        let (tui, _) = await b2Start(terminal, root: editor, options: .init(copySelection: { copied.append($0); return true }))
        defer { tui.stop() }
        let cursor = editor.getCursor()
        terminal.mouse(0, 1, 2); terminal.mouse(32, 5, 2); terminal.mouse(0, 5, 2, release: true)
        await Task.yield()
        await b2Wait(tui)
        #expect(copied == ["hello"])
        #expect(editor.getCursor().line == cursor.line)
        #expect(editor.getCursor().col == cursor.col)
    }

    @Test("Search styles distinguish the current match")
    func searchStyles() async {
        let terminal = B2Terminal(60, 4)
        let root = ScrollView(B2Control(["needle first", "middle", "needle second", "end"]), options: .init(primary: true))
        let (tui, _) = await b2Start(terminal, root: root, options: .init(
            searchMatchStyle: { "\u{1b}[41m\($0)\u{1b}[49m" }, searchCurrentMatchStyle: { "\u{1b}[42m\($0)\u{1b}[49m" }))
        defer { tui.stop() }
        terminal.send("\u{1b}[102;6u"); terminal.send("needle")
        await b2Wait(tui)
        #expect(terminal.output.contains("\u{1b}[42mneedle\u{1b}[49m"))
        #expect(terminal.output.contains("\u{1b}[41mneedle\u{1b}[49m"))
    }

    @Test("Search arrow controls support hover, navigation, and shortcut close")
    func searchArrowButtons() async {
        let terminal = B2Terminal(120, 6)
        let root = ScrollView(B2Control(["needle one", "middle", "needle two", "end"]), options: .init(primary: true))
        let (tui, _) = await b2Start(terminal, root: root, options: .init(searchNavigationButtonStyle: { text, hovered in "\u{1b}[\(hovered ? 45 : 44)m\(text)\u{1b}[49m" }))
        defer { tui.stop() }
        terminal.send("\u{1b}[102;6u"); terminal.send("needle")
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("1/2") })
        guard let row = terminal.viewport.firstIndex(where: { $0.contains("↑") && $0.contains("↓") }),
              let next = terminal.viewport[row].range(of: "Enter", options: .backwards) else {
            Issue.record("Search controls must be visible")
            return
        }
        let column = terminal.viewport[row].distance(from: terminal.viewport[row].startIndex, to: next.lowerBound) + 1
        terminal.mouse(35, column, row + 1)
        await b2Wait(tui)
        #expect(terminal.output.contains("\u{1b}[45m↓ Enter\u{1b}[49m"))
        terminal.mouse(0, column, row + 1)
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("2/2") })
        let previous = terminal.viewport[row].range(of: "Shift+Enter")!
        let previousColumn = terminal.viewport[row].distance(from: terminal.viewport[row].startIndex, to: previous.lowerBound) + 4
        terminal.mouse(0, previousColumn, row + 1)
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("1/2") })
        terminal.send("\u{1b}[102;6u")
        await b2Wait(tui)
        #expect(!terminal.viewport.contains { $0.contains("Shift+Enter") })
    }

    @Test("Transcript box borders do not act as search buttons")
    func searchIgnoresTranscriptBorders() async {
        let terminal = B2Terminal(80, 10)
        let root = ScrollView(B2Control(["needle one", "middle", "needle two", "filler", "┌────────────────────────────────────────┐", "│ box                                    │", "└────────────────────────────────────────┘", "end"]), options: .init(primary: true))
        let (tui, _) = await b2Start(terminal, root: root)
        defer { tui.stop() }
        terminal.send("\u{1b}[102;6u"); terminal.send("needle")
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("1/2") })
        guard let row = terminal.viewport.firstIndex(where: { $0.hasPrefix("└") }) else { Issue.record("Transcript border missing"); return }
        terminal.mouse(0, 24, row + 1)
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("1/2") })
        #expect(!terminal.viewport.contains { $0.contains("2/2") })
    }

    @Test("Search selects from the viewport anchor and retains manual scroll until navigation")
    func searchNavigationAndFocus() async {
        let terminal = B2Terminal(60, 8)
        let lines = (1...12).map { $0 == 5 ? "line 5 needle one" : $0 == 10 ? "line 10 needle two" : "line \($0)" }
        let transcript = ScrollView(B2Control(lines), options: .init(follow: .end, primary: true))
        let editor = B2Control(["editor"])
        let (tui, _) = await b2Start(terminal, root: b2Dock(transcript, editor))
        defer { tui.stop() }
        tui.setFocus(editor)
        terminal.send("\u{1b}[102;6u"); terminal.send("needle")
        await b2Wait(tui)
        #expect(!transcript.isFollowingEnd)
        #expect(terminal.viewport.contains { $0.contains("2/2") })
        #expect(terminal.viewport.contains { $0.contains("line 10 needle two") })
        #expect(editor.inputs.isEmpty)
        #expect(terminal.output.contains("\u{1b}[1;7mneedle\u{1b}[22;27m"))
        for _ in 0..<6 { terminal.mouse(64, 1, 4) }
        await b2Wait(tui)
        #expect(transcript.scrollTop == 0)
        #expect(terminal.viewport.contains { $0.contains("2/2") })
        terminal.send("\u{7}")
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("1/2") })
        #expect(terminal.viewport.contains { $0.contains("line 5 needle one") })
        terminal.send("\u{1b}[103;6u")
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("2/2") })
        terminal.send("\u{1b}"); terminal.send("x")
        await b2Wait(tui)
        #expect(editor.inputs == ["x"])
        #expect(tui.getFocusedComponent() === editor)
    }

    // v1.0.3 (#10314), upstream tui-alt-screen.test.ts "routes Home and End to the focused
    // component and Ctrl+Home/End to the transcript".
    @Test("Home and End reach the focused component; Ctrl+Home and Ctrl+End move the transcript")
    func homeEndRouting() async {
        let terminal = B2Terminal(20, 6)
        let transcript = b2Transcript(12)
        let editor = B2Control(["editor"])
        let (tui, _) = await b2Start(terminal, root: b2Dock(transcript, editor))
        defer { tui.stop() }
        tui.setFocus(editor)
        await b2Wait(tui)

        let bottom = transcript.scrollTop
        #expect(bottom > 0)

        let editorKeys = ["\u{1b}OH", "\u{1b}[F", "\u{1b}[57423u", "\u{1b}[5;5~", "\u{1b}[6;5~"]
        for input in editorKeys { terminal.send(input) }
        await b2Wait(tui)
        #expect(transcript.scrollTop == bottom)
        #expect(editor.inputs == editorKeys)

        terminal.send("\u{1b}[1;5H")
        await b2Wait(tui)
        #expect(transcript.scrollTop == 0)

        terminal.send("\u{1b}[1;5F")
        await b2Wait(tui)
        #expect(transcript.scrollTop == bottom)
        #expect(transcript.isFollowingEnd)

        terminal.send("\u{1b}[57423;5u")
        terminal.send("\u{1b}[57423;5:3u")
        await b2Wait(tui)
        #expect(transcript.scrollTop == 0)

        terminal.send("\u{1b}[6~")
        await b2Wait(tui)
        #expect(transcript.scrollTop == 1)
        #expect(editor.inputs == editorKeys)
    }

    @Test("Focused search permits viewport keys and wheel scrolling")
    func searchAllowsViewportNavigation() async {
        let terminal = B2Terminal(20, 6)
        let (tui, renderer) = await b2Start(terminal, root: b2Transcript(12))
        defer { tui.stop() }
        let top = renderer.viewportTop
        terminal.send("\u{1b}[102;6u")
        await b2Wait(tui)
        #expect(terminal.viewport.contains { $0.contains("↑ ↓") })
        terminal.send("\u{1b}[5~"); terminal.mouse(64, 1, 4)
        await b2Wait(tui)
        #expect(renderer.viewportTop < top)
        #expect(terminal.viewport.contains { $0.contains("↑ ↓") })
    }
}
