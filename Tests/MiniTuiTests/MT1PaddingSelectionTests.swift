import Testing
@testable import MiniTui

private final class MT1SelectionTerminal: Terminal {
    let columns = 20
    let rows = 4
    let kittyProtocolActive = false
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {}
    func stop() {}
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) {}
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}
}

@MainActor
private final class MT1FixedLines: Component {
    var invalidations = 0
    func render(width: Int) -> [String] { ["alpha beta"] }
    func invalidate() { invalidations += 1 }
}

@Suite("MT1 padding and selection")
@MainActor
struct MT1PaddingSelectionTests {
    @Test("Box horizontal padding clears its cache without invalidating children")
    func boxPadding() {
        var backgroundCalls = 0
        let box = Box(paddingX: 1, paddingY: 0, bgFn: { line in
            if line != "test" { backgroundCalls += 1 }
            return line
        })
        let child = MT1FixedLines()
        box.addChild(child)
        #expect(box.render(width: 20) == [" alpha beta         "])
        #expect(box.render(width: 20) == [" alpha beta         "])
        #expect(backgroundCalls == 1)

        box.setPaddingX(3)
        #expect(box.render(width: 20) == ["   alpha beta       "])
        #expect(backgroundCalls == 2)
        #expect(child.invalidations == 0)

        box.setPaddingX(3)
        #expect(box.render(width: 20) == ["   alpha beta       "])
        #expect(backgroundCalls == 3)
    }

    @Test("Text horizontal padding clears cached lines even when the value is unchanged")
    func textPadding() {
        var backgroundCalls = 0
        let text = Text("alpha", paddingX: 1, paddingY: 0, customBgFn: { line in
            backgroundCalls += 1
            return line
        })
        #expect(text.render(width: 12) == [" alpha      "])
        #expect(text.render(width: 12) == [" alpha      "])
        #expect(backgroundCalls == 1)

        text.setPaddingX(3)
        #expect(text.render(width: 12) == ["   alpha    "])
        #expect(backgroundCalls == 2)

        text.setPaddingX(3)
        #expect(text.render(width: 12) == ["   alpha    "])
        #expect(backgroundCalls == 3)
    }

    private func renderer() -> AltScreenRenderer {
        let renderer = AltScreenRenderer(terminal: MT1SelectionTerminal(),
            options: .init(copyOnSelect: false))
        renderer.start()
        renderer.present(.init(lines: ["alpha beta"], cursor: nil, width: 20, height: 4,
            clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false,
            useSystemCursor: false))
        return renderer
    }

    private func click(_ renderer: AltScreenRenderer) {
        #expect(renderer.handleInput("\u{1B}[<0;1;1M"))
        #expect(renderer.handleInput("\u{1B}[<0;1;1m"))
    }

    @Test("Selection reset clears a selection and prevents the next click from continuing a multi-click")
    func resetSelectionAndClickHistory() async {
        let renderer = renderer()
        defer { renderer.stop(preserveScreen: true) }
        click(renderer)
        #expect(!renderer.hasActiveSelection())
        click(renderer)
        #expect(renderer.hasActiveSelection())

        renderer.resetTextSelection()
        #expect(!renderer.hasActiveSelection())
        #expect(await !renderer.copyActiveSelectionToClipboard())
        click(renderer)
        #expect(!renderer.hasActiveSelection())
        click(renderer)
        #expect(renderer.hasActiveSelection())
    }

    @Test("Selection reset cancels a selection drag before its release")
    func resetSelectionDuringDrag() {
        let renderer = renderer()
        defer { renderer.stop(preserveScreen: true) }
        #expect(renderer.handleInput("\u{1B}[<0;1;1M"))
        #expect(renderer.handleInput("\u{1B}[<32;4;1M"))
        #expect(renderer.hasActiveSelection())
        renderer.resetTextSelection()
        #expect(!renderer.hasActiveSelection())
        #expect(renderer.handleInput("\u{1B}[<0;4;1m"))
        #expect(!renderer.hasActiveSelection())
    }
}
