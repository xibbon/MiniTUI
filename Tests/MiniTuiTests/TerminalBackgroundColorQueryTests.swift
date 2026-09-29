import Testing
@testable import MiniTui

private final class BackgroundColorTestTerminal: Terminal {
    private var inputHandler: ((String) -> Void)?
    var writes: [String] = []

    let columns = 80
    let rows = 24
    let kittyProtocolActive = false

    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        inputHandler = onInput
    }

    func stop() { inputHandler = nil }
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) { writes.append(data) }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}

    func sendInput(_ data: String) { inputHandler?(data) }
}

private final class BackgroundColorInputComponent: Component {
    var inputs: [String] = []

    func render(width: Int) -> [String] { [] }
    func handleInput(_ data: String) { inputs.append(data) }
}

@Suite("Terminal color queries")
struct TerminalBackgroundColorQueryTests {
    private let da1 = "\u{001B}[?62;22c"
    private let background = "\u{001B}]11;rgb:0000/8000/ffff\u{0007}"
    private let expectedBackground = RgbColor(r: 0, g: 128, b: 255)

    @MainActor
    @Test("writes one combined request and returns default colors")
    func writesOneRequestAndReturnsColors() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        tui.start()

        let query = Task { @MainActor in
            await tui.queryTerminalColors(timeoutMs: 1_000)
        }
        await Task.yield()

        let request = terminal.writes.last ?? ""
        #expect(request.hasPrefix("\u{001B}]10;?\u{0007}\u{001B}]11;?\u{0007}\u{001B}]4;0;?\u{0007}"))
        #expect(request.hasSuffix("\u{001B}[c"))
        #expect(request.components(separatedBy: "\u{001B}]4;").count - 1 == 16)

        terminal.sendInput("\u{001B}]10;#ffffff\u{0007}" + background + da1)
        #expect(await query.value == TerminalColors(
            foreground: RgbColor(r: 255, g: 255, b: 255),
            background: expectedBackground
        ))
        tui.stop()
    }

    @MainActor
    @Test("counts malformed and duplicate replies, and keeps an incomplete palette unset")
    func malformedAndDuplicateReplies() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        tui.start()

        let query = Task { @MainActor in
            await tui.queryTerminalColors(timeoutMs: 1_000)
        }
        await Task.yield()
        terminal.sendInput("\u{001B}]11;not-a-color\u{0007}")
        terminal.sendInput(background)
        terminal.sendInput("\u{001B}]4;2;#ff0000\u{0007}")
        terminal.sendInput(da1)
        #expect(await query.value == TerminalColors())
        tui.stop()
    }

    @MainActor
    @Test("uses FIFO order and forwards input after the replies")
    func fifoAndTrailingInput() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        let component = BackgroundColorInputComponent()
        tui.addChild(component)
        tui.setFocus(component)
        tui.start()

        let firstQuery = Task { @MainActor in
            await tui.queryTerminalColors(timeoutMs: 1_000)
        }
        await Task.yield()
        let secondQuery = Task { @MainActor in
            await tui.queryTerminalColors(timeoutMs: 1_000)
        }
        await Task.yield()

        terminal.sendInput(background + da1 + da1 + "x")
        #expect(await firstQuery.value.background == expectedBackground)
        #expect(await secondQuery.value == TerminalColors())
        #expect(component.inputs == ["x"])
        tui.stop()
    }

    @MainActor
    @Test("delivers a completed late reply after a timeout")
    func lateReply() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        var late: [TerminalColors] = []
        tui.start()

        let query = Task { @MainActor in
            await tui.queryTerminalColors(timeoutMs: 1, onLateReply: { late.append($0) })
        }
        #expect(await query.value == TerminalColors())
        terminal.sendInput(background + da1)
        await Task.yield()
        #expect(late == [TerminalColors(background: expectedBackground)])
        tui.stop()
    }

    @MainActor
    @Test("completes after 18 distinct replies without waiting for DA1")
    func allRepliesComplete() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        tui.start()
        let query = Task { @MainActor in await tui.queryTerminalColors(timeoutMs: 1_000) }
        await Task.yield()
        let palette = (0..<16).map { "\u{001B}]4;\($0);#000000\u{0007}" }.joined()
        terminal.sendInput("\u{001B}]10;#ffffff\u{0007}" + background + palette)
        let colors = await query.value
        #expect(colors.foreground == RgbColor(r: 255, g: 255, b: 255))
        #expect(colors.background == expectedBackground)
        #expect(colors.palette == Array(repeating: RgbColor(r: 0, g: 0, b: 0), count: 16))
        terminal.sendInput(da1)
        tui.stop()
    }

    @MainActor
    @Test("DA1 after a Kitty reply reaches TUI input")
    func da1AfterKittyReply() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        let component = BackgroundColorInputComponent()
        tui.addChild(component)
        tui.setFocus(component)
        tui.start()
        let query = Task { @MainActor in await tui.queryTerminalColors(timeoutMs: 1_000) }
        await Task.yield()
        terminal.sendInput("\u{001B}[?1u")
        terminal.sendInput(da1)
        #expect(await query.value == TerminalColors())
        #expect(component.inputs == ["\u{001B}[?1u"])
        tui.stop()
    }
}
