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

@Suite("Terminal background-color queries")
struct TerminalBackgroundColorQueryTests {
    private let request = "\u{001B}]11;?\u{0007}"
    private let response = "\u{001B}]11;rgb:0000/8000/ffff\u{0007}"
    private let expectedColor = RgbColor(r: 0, g: 128, b: 255)

    @MainActor
    @Test("writes OSC 11 request and returns the parsed color")
    func writesRequestAndReturnsColor() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        tui.start()

        let query = Task { @MainActor in
            await tui.queryTerminalBackgroundColor(timeoutMs: 1_000)
        }
        await Task.yield()

        #expect(terminal.writes.contains(request))
        terminal.sendInput(response)
        #expect(await query.value == expectedColor)
        tui.stop()
    }

    @MainActor
    @Test("returns nil for malformed replies and timeouts")
    func malformedReplyAndTimeoutReturnNil() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        tui.start()

        let malformedQuery = Task { @MainActor in
            await tui.queryTerminalBackgroundColor(timeoutMs: 1_000)
        }
        await Task.yield()
        terminal.sendInput("\u{001B}]11;not-a-color\u{0007}")
        #expect(await malformedQuery.value == nil)

        #expect(await tui.queryTerminalBackgroundColor(timeoutMs: 1) == nil)
        tui.stop()
    }

    @MainActor
    @Test("consumes replies and forwards trailing input")
    func consumesRepliesAndForwardsTrailingInput() async {
        let terminal = BackgroundColorTestTerminal()
        let tui = TUI(terminal: terminal)
        let component = BackgroundColorInputComponent()
        tui.addChild(component)
        tui.setFocus(component)
        tui.start()

        let firstQuery = Task { @MainActor in
            await tui.queryTerminalBackgroundColor(timeoutMs: 1_000)
        }
        await Task.yield()
        terminal.sendInput(response)
        #expect(await firstQuery.value == expectedColor)
        #expect(component.inputs.isEmpty)

        let secondQuery = Task { @MainActor in
            await tui.queryTerminalBackgroundColor(timeoutMs: 1_000)
        }
        await Task.yield()
        terminal.sendInput(response + "x")
        #expect(await secondQuery.value == expectedColor)
        #expect(component.inputs == ["x"])
        tui.stop()
    }

    @MainActor
    @Test("routes color-scheme and background replies in either order")
    func routesCombinedRepliesInEitherOrder() async {
        let colorSchemeResponse = "\u{001B}[?997;1n"
        let combinedInputs = [
            colorSchemeResponse + response,
            response + colorSchemeResponse,
        ]

        for combinedInput in combinedInputs {
            let terminal = BackgroundColorTestTerminal()
            let tui = TUI(terminal: terminal)
            let component = BackgroundColorInputComponent()
            tui.addChild(component)
            tui.setFocus(component)
            tui.start()

            let colorSchemeQuery = Task { @MainActor in
                await tui.queryTerminalColorScheme(timeoutMs: 1_000)
            }
            let backgroundColorQuery = Task { @MainActor in
                await tui.queryTerminalBackgroundColor(timeoutMs: 1_000)
            }
            await Task.yield()
            await Task.yield()

            #expect(terminal.writes.contains("\u{001B}[?996n"))
            #expect(terminal.writes.contains(request))
            terminal.sendInput(combinedInput)

            #expect(await colorSchemeQuery.value == .dark)
            #expect(await backgroundColorQuery.value == expectedColor)
            #expect(component.inputs.isEmpty)
            tui.stop()
        }
    }
}
