import Testing
@testable import MiniTui

private final class ColorSchemeTestTerminal: Terminal {
    private var inputHandler: ((String) -> Void)?
    var writes: [String] = []
    var hideCount = 0

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
    func hideCursor() { hideCount += 1 }
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}

    func sendInput(_ data: String) { inputHandler?(data) }
}

private final class ColorSchemeInputComponent: Component {
    var inputs: [String] = []

    func render(width: Int) -> [String] { [] }
    func handleInput(_ data: String) { inputs.append(data) }
}

@Suite("Terminal color parsing")
struct TerminalColorsTests {
    @Test("parses OSC 10, 11, and palette RGB responses")
    func parsesOscColorResponses() {
        let foreground = parseOscColorResponse("\u{001B}]10;rgb:ffff/ffff/ffff\u{0007}")
        #expect(foreground?.target == .foreground)
        #expect(foreground?.rgb == RgbColor(r: 255, g: 255, b: 255))
        let background = parseOscColorResponse("\u{001B}]11;rgb:0000/8000/ffff\u{0007}")
        #expect(background?.target == .background)
        #expect(background?.rgb == RgbColor(r: 0, g: 128, b: 255))
        let palette = parseOscColorResponse("\u{001B}]4;13;#ff0080\u{001B}\\")
        #expect(palette?.target == .palette(13))
        #expect(palette?.rgb == RgbColor(r: 255, g: 0, b: 128))
        let malformed = parseOscColorResponse("\u{001B}]4;1;bogus\u{0007}")
        #expect(malformed?.target == .palette(1))
        #expect(malformed?.rgb == nil)
    }

    @Test("rejects non-color and incomplete responses")
    func rejectsInvalidOscColorResponse() {
        #expect(parseOscColorResponse("x\u{001B}]11;#ffffff\u{0007}") == nil)
        #expect(parseOscColorResponse("\u{001B}]12;#ffffff\u{0007}") == nil)
        #expect(parseOscColorResponse("\u{001B}]11;#ffffff\u{0007}x") == nil)
        #expect(parseOscColorResponse("\u{001B}]11;#ffffff") == nil)
    }

    @Test("parses color-scheme reports")
    func parsesTerminalColorSchemeReports() {
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;1n") == .dark)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;2n") == .light)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;1n\u{001B}[?997;2n") == .light)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;2n\u{001B}[?997;1n") == .dark)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;3n") == nil)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?996n") == nil)
        #expect(parseTerminalColorSchemeReport("\u{001B}[?997;2na") == nil)
    }

    @MainActor
    @Test("consumes batched reports and forwards trailing input")
    func consumesReportPrefixes() async {
        let terminal = ColorSchemeTestTerminal()
        let tui = TUI(terminal: terminal)
        let component = ColorSchemeInputComponent()
        var reports: [TerminalColorScheme] = []
        _ = tui.onTerminalColorSchemeChange { reports.append($0) }
        tui.addChild(component)
        tui.setFocus(component)
        tui.start()

        terminal.sendInput("\u{001B}[?997;1n\u{001B}[?997;2n")
        await Task.yield()
        #expect(reports == [.light])
        #expect(component.inputs.isEmpty)

        terminal.sendInput("\u{001B}[?997;2na")
        await Task.yield()
        #expect(reports == [.light, .light])
        #expect(component.inputs == ["a"])
        tui.stop()
    }

    @Test("uses the upstream OSC 9;4 progress sequences")
    func progressSequences() {
        #expect(terminalProgressActiveSequence == "\u{001B}]9;4;3\u{0007}")
        #expect(terminalProgressClearSequence == "\u{001B}]9;4;0\u{0007}")
    }

    @Test("uses TERM direct suffix for true color")
    func directTermColorMode() {
        let capabilities = detectCapabilities(environment: ["TERM": "xterm-direct"])
        #expect(capabilities.trueColor)
        #expect(getTerminalColorMode(capabilities) == .truecolor)
        #expect(getTerminalColorMode(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: false)) == .color256)
    }

    @MainActor
    @Test("does not hide the cursor after stop")
    func stoppedCursorMode() {
        let terminal = ColorSchemeTestTerminal()
        let tui = TUI(terminal: terminal)
        tui.start()
        tui.stop()
        let count = terminal.hideCount
        tui.useSystemCursor = true
        tui.useSystemCursor = false
        #expect(terminal.hideCount == count)
    }

    @MainActor
    @Test("subscribes to terminal color-scheme notifications")
    func subscribesToTerminalColorScheme() async {
        let terminal = ColorSchemeTestTerminal()
        let tui = TUI(terminal: terminal)
        var reports: [TerminalColorScheme] = []
        let unsubscribe = tui.onTerminalColorSchemeChange { reports.append($0) }
        tui.start()
        tui.setTerminalColorSchemeNotifications(true)

        terminal.sendInput("\u{001B}[?997;2n")
        await Task.yield()
        #expect(reports == [.light])
        #expect(terminal.writes.contains("\u{001B}[?2031h"))

        unsubscribe()
        tui.stop()
        #expect(terminal.writes.contains("\u{001B}[?2031l"))
    }
}
