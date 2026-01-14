import Testing
import MiniTui

final class SimpleContent: Component {
    private let lines: [String]

    init(_ lines: [String]) {
        self.lines = lines
    }

    func render(width: Int) -> [String] {
        return lines
    }
}

final class SimpleOverlay: Component {
    func render(width: Int) -> [String] {
        return ["OVERLAY_TOP", "OVERLAY_MID", "OVERLAY_BOT"]
    }
}

@MainActor
@Test("overlay renders when content is shorter than terminal height")
func overlayShortContent() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    tui.addChild(SimpleContent(["Line 1", "Line 2", "Line 3"]))
    tui.showOverlay(SimpleOverlay())

    tui.start()
    tui.requestRender(force: true)
    await terminal.flush()

    let viewport = terminal.getViewport()
    let hasOverlay = viewport.contains { $0.contains("OVERLAY") }
    #expect(hasOverlay)

    tui.stop()
}
