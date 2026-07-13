import Testing
@testable import MiniTui

private final class ColorSchemeTestTerminal: Terminal {
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

@Suite("Terminal color parsing")
struct TerminalColorsTests {
    @Test("parses OSC 11 RGB responses")
    func parsesOsc11BackgroundColor() {
        #expect(parseOsc11BackgroundColor("\u{001B}]11;rgb:0000/8000/ffff\u{0007}") == RgbColor(r: 0, g: 128, b: 255))
        #expect(parseOsc11BackgroundColor("\u{001B}]11;#ffffff\u{001B}\\") == RgbColor(r: 255, g: 255, b: 255))
        #expect(parseOsc11BackgroundColor("\u{001B}]11;#000000\u{0007}") == RgbColor(r: 0, g: 0, b: 0))
    }

    @Test("rejects non-strict OSC 11 responses")
    func rejectsInvalidOsc11BackgroundColor() {
        #expect(!isOsc11BackgroundColorResponse("x\u{001B}]11;#ffffff\u{0007}"))
        #expect(parseOsc11BackgroundColor("\u{001B}]10;#ffffff\u{0007}") == nil)
        #expect(parseOsc11BackgroundColor("\u{001B}]11;#ffffff\u{0007}x") == nil)
    }

    @Test("parses color-scheme reports")
    func parsesTerminalColorSchemeReports() {
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;1n") == .dark)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;2n") == .light)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;3n") == nil)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?996n") == nil)
    }

    @MainActor
    @Test("queries and subscribes to terminal color-scheme reports")
    func queriesAndSubscribesToTerminalColorScheme() async {
        let terminal = ColorSchemeTestTerminal()
        let tui = TUI(terminal: terminal)
        var reports: [TerminalColorScheme] = []
        let unsubscribe = tui.onTerminalColorSchemeChange { reports.append($0) }
        tui.start()
        tui.setTerminalColorSchemeNotifications(true)

        let query = Task { @MainActor in
            await tui.queryTerminalColorScheme(timeoutMs: 1_000)
        }
        await Task.yield()
        #expect(terminal.writes.contains("\u{001B}[?996n"))

        terminal.sendInput("\u{001B}[?997;2n")
        #expect(await query.value == .light)
        #expect(reports == [.light])
        #expect(terminal.writes.contains("\u{001B}[?2031h"))

        unsubscribe()
        tui.stop()
        #expect(terminal.writes.contains("\u{001B}[?2031l"))
    }
}
