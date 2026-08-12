import Testing
@testable import MiniTui

private final class RendererRecordingTerminal: Terminal {
    var columns = 40
    var rows = 10
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
private final class RendererTestComponent: Component {
    let lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    func render(width: Int) -> [String] {
        lines
    }
}

@MainActor
@Test("main-screen renderer reports its mode")
func mainScreenRendererReportsMode() {
    let terminal = RendererRecordingTerminal()
    let renderer: any TuiRenderer = MainScreenRenderer(terminal: terminal)

    #expect(renderer.mode == .mainScreen)
}

@MainActor
@Test("renderer swap preserves main-screen differential state")
func rendererSwapPreservesMainScreenState() async {
    let terminal = RendererRecordingTerminal()
    let tui = TUI(terminal: terminal)
    tui.addChild(RendererTestComponent(lines: ["first", "second"]))
    tui.start()
    await tui.waitForRender()

    terminal.writes = []
    let replacement = MainScreenRenderer(terminal: terminal)
    tui.registerRenderer(replacement)
    #expect(tui.switchRenderer(to: .mainScreen))
    await tui.waitForRender()

    #expect(terminal.writes.isEmpty)
    tui.stop()
}

@MainActor
@Test("unregistered renderer mode switch is a no-op")
func unregisteredRendererModeSwitchIsNoOp() {
    let terminal = RendererRecordingTerminal()
    let tui = TUI(terminal: terminal)

    #expect(!tui.switchRenderer(to: .altScreen))
    #expect(tui.mode == .mainScreen)
    #expect(terminal.writes.isEmpty)
}
