import Testing
import MiniTui

final class StaticLines: Component {
    private let lines: [String]

    init(_ lines: [String]) {
        self.lines = lines
    }

    func render(width: Int) -> [String] {
        return lines
    }
}

final class StaticOverlayLine: Component {
    private let line: String

    init(_ line: String) {
        self.line = line
    }

    func render(width: Int) -> [String] {
        return [line]
    }
}

@MainActor
private func renderAndFlush(_ tui: TUI, _ terminal: VirtualTerminal) async {
    tui.requestRender(force: true)
    await terminal.flush()
}

@MainActor
@Test("overlay compositing does not leak styles without overlays")
func overlayStyleLeakNoOverlay() async {
    let width = 20
    let baseLine = "\u{001B}[3m" + String(repeating: "X", count: width) + "\u{001B}[23m"

    let terminal = VirtualTerminal(columns: width, rows: 6)
    let tui = TUI(terminal: terminal)
    tui.addChild(StaticLines([baseLine, "INPUT"]))
    tui.start()
    await renderAndFlush(tui, terminal)

    #expect(!terminal.isItalic(row: 1, col: 0))
    tui.stop()
}

@MainActor
@Test("overlay slicing does not leak styles")
func overlayStyleLeakWithOverlay() async {
    let width = 20
    let baseLine = "\u{001B}[3m" + String(repeating: "X", count: width) + "\u{001B}[23m"

    let terminal = VirtualTerminal(columns: width, rows: 6)
    let tui = TUI(terminal: terminal)
    tui.addChild(StaticLines([baseLine, "INPUT"]))

    tui.showOverlay(StaticOverlayLine("OVR"), options: OverlayOptions(width: 3, row: 0, col: 5))
    tui.start()
    await renderAndFlush(tui, terminal)

    #expect(!terminal.isItalic(row: 1, col: 0))
    tui.stop()
}
