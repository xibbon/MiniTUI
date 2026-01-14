import Testing
import MiniTui

final class TestComponent: Component {
    var lines: [String] = []

    func render(width: Int) -> [String] {
        return lines
    }
}

@MainActor
private func renderAndFlush(_ tui: TUI, _ terminal: VirtualTerminal, force: Bool = true) async {
    tui.requestRender(force: force)
    await terminal.flush()
}

@MainActor
@Test("tracks cursor correctly when content shrinks with unchanged remaining lines")
func tuiRenderShrinkingContent() async {
    let terminal = VirtualTerminal(columns: 40, rows: 10)
    let tui = TUI(terminal: terminal)
    let component = TestComponent()
    tui.addChild(component)

    component.lines = ["Line 0", "Line 1", "Line 2", "Line 3", "Line 4"]
    tui.start()
    await renderAndFlush(tui, terminal, force: true)

    component.lines = ["Line 0", "Line 1", "Line 2"]
    await renderAndFlush(tui, terminal)

    component.lines = ["Line 0", "CHANGED", "Line 2"]
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[1].contains("CHANGED"))
    tui.stop()
}

@MainActor
@Test("renders correctly when only a middle line changes")
func tuiRenderSpinner() async {
    let terminal = VirtualTerminal(columns: 40, rows: 10)
    let tui = TUI(terminal: terminal)
    let component = TestComponent()
    tui.addChild(component)

    component.lines = ["Header", "Working...", "Footer"]
    tui.start()
    await renderAndFlush(tui, terminal, force: true)

    let spinnerFrames = ["|", "/", "-", "\\"]
    for frame in spinnerFrames {
        component.lines = ["Header", "Working \(frame)", "Footer"]
        await renderAndFlush(tui, terminal)

        let viewport = terminal.getViewport()
        #expect(viewport[0].contains("Header"))
        #expect(viewport[1].contains("Working \(frame)"))
        #expect(viewport[2].contains("Footer"))
    }

    tui.stop()
}

@MainActor
@Test("resets styles after each rendered line")
func tuiRenderLineResets() async {
    let terminal = VirtualTerminal(columns: 20, rows: 6)
    let tui = TUI(terminal: terminal)
    let component = TestComponent()
    tui.addChild(component)

    component.lines = ["\u{001B}[3mItalic", "Plain"]
    tui.start()
    await renderAndFlush(tui, terminal, force: true)

    #expect(!terminal.isItalic(row: 1, col: 0))
    tui.stop()
}

@MainActor
@Test("renders correctly when first line changes but rest stays same")
func tuiRenderFirstLineChange() async {
    let terminal = VirtualTerminal(columns: 40, rows: 10)
    let tui = TUI(terminal: terminal)
    let component = TestComponent()
    tui.addChild(component)

    component.lines = ["Line 0", "Line 1", "Line 2", "Line 3"]
    tui.start()
    await renderAndFlush(tui, terminal, force: true)

    component.lines = ["CHANGED", "Line 1", "Line 2", "Line 3"]
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].contains("CHANGED"))
    #expect(viewport[1].contains("Line 1"))
    #expect(viewport[2].contains("Line 2"))
    #expect(viewport[3].contains("Line 3"))

    tui.stop()
}

@MainActor
@Test("renders correctly when last line changes but rest stays same")
func tuiRenderLastLineChange() async {
    let terminal = VirtualTerminal(columns: 40, rows: 10)
    let tui = TUI(terminal: terminal)
    let component = TestComponent()
    tui.addChild(component)

    component.lines = ["Line 0", "Line 1", "Line 2", "Line 3"]
    tui.start()
    await renderAndFlush(tui, terminal, force: true)

    component.lines = ["Line 0", "Line 1", "Line 2", "CHANGED"]
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].contains("Line 0"))
    #expect(viewport[1].contains("Line 1"))
    #expect(viewport[2].contains("Line 2"))
    #expect(viewport[3].contains("CHANGED"))

    tui.stop()
}

@MainActor
@Test("renders correctly when multiple non-adjacent lines change")
func tuiRenderNonAdjacentChanges() async {
    let terminal = VirtualTerminal(columns: 40, rows: 10)
    let tui = TUI(terminal: terminal)
    let component = TestComponent()
    tui.addChild(component)

    component.lines = ["Line 0", "Line 1", "Line 2", "Line 3", "Line 4"]
    tui.start()
    await renderAndFlush(tui, terminal, force: true)

    component.lines = ["Line 0", "CHANGED 1", "Line 2", "CHANGED 3", "Line 4"]
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].contains("Line 0"))
    #expect(viewport[1].contains("CHANGED 1"))
    #expect(viewport[2].contains("Line 2"))
    #expect(viewport[3].contains("CHANGED 3"))
    #expect(viewport[4].contains("Line 4"))

    tui.stop()
}

@MainActor
@Test("handles transition from content to empty and back to content")
func tuiRenderContentToEmptyToContent() async {
    let terminal = VirtualTerminal(columns: 40, rows: 10)
    let tui = TUI(terminal: terminal)
    let component = TestComponent()
    tui.addChild(component)

    component.lines = ["Line 0", "Line 1", "Line 2"]
    tui.start()
    await renderAndFlush(tui, terminal, force: true)

    var viewport = terminal.getViewport()
    #expect(viewport[0].contains("Line 0"))

    component.lines = []
    await renderAndFlush(tui, terminal)

    component.lines = ["New Line 0", "New Line 1"]
    await renderAndFlush(tui, terminal)

    viewport = terminal.getViewport()
    #expect(viewport[0].contains("New Line 0"))
    #expect(viewport[1].contains("New Line 1"))

    tui.stop()
}
