import Foundation
import Testing
import Darwin
import os
@testable import MiniTui

private class StatusTestTerminal {
    var inputHandler: ((String) -> Void)?
    var writes: [String] = []
    var events: [String] = []
    let columns = 80
    let rows = 24
    let kittyProtocolActive = false

    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        inputHandler = onInput
    }
    // Keep the handler so tests can send a late reply after stop.
    func stop() { events.append("stop") }
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) { writes.append(data); events.append(data) }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}

    var statusWrites: [String] { writes.filter { $0.contains("\u{001B}]7501;") } }
}

private final class DefaultStatusTestTerminal: StatusTestTerminal, Terminal {}

private final class QueryStatusTestTerminal: StatusTestTerminal, Terminal {
    var supportsTerminalQueries: Bool { true }
}

private final class StatusInputComponent: Component {
    var inputs: [String] = []
    func render(width: Int) -> [String] { [] }
    func handleInput(_ data: String) { inputs.append(data) }
}

@Suite("Program status TUI")
@MainActor
struct ProgramStatusTUITests {
    private let da1 = "\u{001B}[?62;22c"
    private let idle = ProgramStatus(state: .idle, app: "pi")
    private let working = ProgramStatus(state: .working, app: "pi", message: "Task")
    private let clear = formatProgramStatus(ProgramStatus(state: .clear))

    private func setup(environment: String? = nil) -> (QueryStatusTestTerminal, TUI, StatusInputComponent) {
        let terminal = QueryStatusTestTerminal()
        let tui = TUI(terminal: terminal)
        tui.programStatusEnvironment = { environment }
        let component = StatusInputComponent()
        tui.addChild(component)
        tui.setFocus(component)
        return (terminal, tui, component)
    }

    private func send(_ bytes: String, to terminal: StatusTestTerminal) async {
        terminal.inputHandler?(bytes)
        // The input callback posts a main-actor task. This task follows it on the actor.
        await Task { @MainActor in }.value
    }

    @Test("reports the latest status when support arrives before DA1")
    func replyBeforeDA1() async {
        let (terminal, tui, component) = setup()
        tui.setProgramStatus(idle)
        tui.start()
        defer { tui.stop() }
        #expect(terminal.statusWrites == [programStatusQuery + "\u{001B}[c"])
        tui.setProgramStatus(working)
        #expect(terminal.statusWrites.count == 1)
        await send(programStatusQuery + da1, to: terminal)
        #expect(terminal.statusWrites == [programStatusQuery + "\u{001B}[c", formatProgramStatus(working)])
        #expect(component.inputs.isEmpty)
        tui.setProgramStatus(idle)
        #expect(terminal.statusWrites.last == formatProgramStatus(idle))
    }

    @Test("DA1 before support prevents reports and consumes the late reply")
    func da1BeforeReply() async {
        let (terminal, tui, component) = setup()
        tui.setProgramStatus(idle)
        tui.start()
        await send(da1 + programStatusQuery, to: terminal)
        tui.setProgramStatus(working)
        tui.stop()
        #expect(terminal.statusWrites == [programStatusQuery + "\u{001B}[c"])
        #expect(component.inputs.isEmpty)
    }

    @Test("exact environment overrides skip the query and one reports at once")
    func environmentOverrides() async {
        for value in ["1", "0"] {
            let (terminal, tui, component) = setup(environment: value)
            tui.setProgramStatus(idle)
            tui.start()
            #expect(terminal.statusWrites == (value == "1" ? [formatProgramStatus(idle)] : []))
            tui.setProgramStatus(working)
            #expect(terminal.statusWrites == (value == "1" ? [formatProgramStatus(idle), formatProgramStatus(working)] : []))
            await send(programStatusQuery, to: terminal)
            #expect(component.inputs.isEmpty)
            tui.stop()
            #expect(terminal.statusWrites.last == (value == "1" ? clear : nil))
        }
        for value in ["", "true", "2"] {
            let (terminal, tui, _) = setup(environment: value)
            tui.start()
            #expect(terminal.statusWrites == [programStatusQuery + "\u{001B}[c"])
            tui.stop()
        }
    }

    @Test("DA1 from a stopped query does not end a new query")
    func staleDA1AcrossRestart() async {
        let (terminal, tui, component) = setup()
        tui.setProgramStatus(idle)
        tui.start()
        tui.stop()
        tui.start()
        await send(da1, to: terminal)
        #expect(terminal.statusWrites.count == 2)
        await send(programStatusQuery + da1, to: terminal)
        #expect(terminal.statusWrites.last == formatProgramStatus(idle))
        #expect(component.inputs.isEmpty)
        tui.stop()
    }

    @Test("stop clears a status before terminal stop and restart needs a new confirmation")
    func clearAndRestart() async throws {
        let (terminal, tui, _) = setup()
        tui.setProgramStatus(working)
        tui.start()
        await send(programStatusQuery + da1, to: terminal)
        tui.stop()
        #expect(terminal.statusWrites.last == clear)
        let clearIndex = try #require(terminal.events.firstIndex(of: clear))
        let stopIndex = try #require(terminal.events.firstIndex(of: "stop"))
        #expect(clearIndex < stopIndex)
        let count = terminal.statusWrites.count
        tui.setProgramStatus(idle)
        await send(programStatusQuery, to: terminal)
        #expect(terminal.statusWrites.count == count)
        tui.start()
        #expect(terminal.statusWrites.last == programStatusQuery + "\u{001B}[c")
        await send(programStatusQuery + da1, to: terminal)
        #expect(terminal.statusWrites.last == formatProgramStatus(idle))
        tui.stop()
    }

    @Test("clear removes the stored report and an unconfirmed terminal gets no clear")
    func explicitClearAndUnconfirmedStop() async {
        let (terminal, tui, _) = setup()
        tui.setProgramStatus(idle)
        tui.start()
        await send(programStatusQuery + da1, to: terminal)
        tui.setProgramStatus(ProgramStatus(state: .clear))
        let count = terminal.statusWrites.count
        tui.stop()
        #expect(terminal.statusWrites.count == count)
        tui.start()
        await send(programStatusQuery + da1, to: terminal)
        #expect(terminal.statusWrites.last == programStatusQuery + "\u{001B}[c")
        tui.stop()
        let (unconfirmed, other, _) = setup()
        other.setProgramStatus(idle)
        other.start()
        other.stop()
        #expect(unconfirmed.statusWrites == [programStatusQuery + "\u{001B}[c"])
    }

    @Test("program and color queries each consume their DA1 in write order")
    func programThenColor() async {
        let (terminal, tui, component) = setup()
        tui.start()
        let color = Task { @MainActor in await tui.queryTerminalColors(timeoutMs: 1_000) }
        await Task.yield()
        await send(da1, to: terminal)
        // If the first DA1 ended the color query, this late color would not be stored.
        await send("\u{001B}]11;#123456\u{0007}" + da1 + "x", to: terminal)
        #expect(await color.value.background == RgbColor(r: 0x12, g: 0x34, b: 0x56))
        #expect(component.inputs == ["x"])
        tui.stop()
    }

    @Test("a color query before start keeps its DA1 ahead of the program query")
    func colorThenProgram() async {
        let (terminal, tui, component) = setup()
        let color = Task { @MainActor in await tui.queryTerminalColors(timeoutMs: 1_000) }
        await Task.yield()
        tui.setProgramStatus(idle)
        tui.start()
        await send("\u{001B}]11;#123456\u{0007}" + da1, to: terminal)
        #expect(await color.value.background == RgbColor(r: 0x12, g: 0x34, b: 0x56))
        await send(programStatusQuery + da1, to: terminal)
        #expect(terminal.statusWrites.last == formatProgramStatus(idle))
        #expect(component.inputs.isEmpty)
        tui.stop()
    }

    @Test("every support reply is consumed and an unowned DA1 is forwarded")
    func repliesNeverReachFocus() async {
        let (terminal, tui, component) = setup(environment: "0")
        tui.start()
        defer { tui.stop() }
        await send(programStatusQuery + "\u{001B}]7501;?\u{0007}" + "\u{001B}]7501;?version=2\u{001B}\\" + "x", to: terminal)
        #expect(component.inputs == ["x"])
        await send(da1, to: terminal)
        #expect(component.inputs == ["x", da1])
        await send("\u{001B}]7501;state=idle\u{001B}\\", to: terminal)
        #expect(component.inputs.last == "\u{001B}]7501;state=idle\u{001B}\\")
    }

    @Test("support reply parsing uses scalars and preserves text after ST")
    func replyScalarBoundaries() async {
        let (terminal, tui, component) = setup()
        tui.setProgramStatus(idle)
        tui.start()
        defer { tui.stop() }
        await send("\u{001B}]7501;?\u{301}version=2\u{001B}\\\u{301}x", to: terminal)
        #expect(terminal.statusWrites.last == formatProgramStatus(idle))
        #expect(component.inputs == ["\u{301}x"])
    }

    @Test("default terminal capability receives no status bytes")
    func defaultCapability() async {
        for environment in ["1", "0", ""] {
            let terminal = DefaultStatusTestTerminal()
            #expect(!terminal.supportsTerminalQueries)
            let tui = TUI(terminal: terminal)
            tui.programStatusEnvironment = { environment }
            let component = StatusInputComponent()
            tui.setFocus(component)
            tui.setProgramStatus(idle)
            tui.start()
            tui.setProgramStatus(working)
            await send(programStatusQuery, to: terminal)
            tui.stop()
            #expect(terminal.statusWrites.isEmpty)
            #expect(component.inputs.isEmpty)
        }
    }

    @Test("status writes do not occur before start or after stop")
    func outsideTerminalLifetime() {
        let (terminal, tui, _) = setup(environment: "1")
        tui.setProgramStatus(idle)
        tui.stop()
        #expect(terminal.statusWrites.isEmpty)
        tui.start()
        tui.stop()
        let count = terminal.statusWrites.count
        tui.stop()
        tui.setProgramStatus(working)
        #expect(terminal.statusWrites.count == count)
    }
}

@Suite("Program status terminal loss", .serialized)
@MainActor
struct ProgramStatusTerminalLossTests {
    @Test("raw-mode terminal loss prevents the query and all later status bytes")
    func lossDuringStart() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        try #require(openpty(&master, &slave, nil, nil, nil) == 0)
        defer { close(master); close(slave) }
        let writes = OSAllocatedUnfairLock(initialState: 0)
        var calls = TerminalIOCalls()
        calls.getAttributes = { _, _ in errno = ENOTTY; return -1 }
        calls.write = { _, _, count in writes.withLock { $0 += 1 }; return count }
        let terminal = ProcessTerminal(inputDescriptor: slave, outputDescriptor: slave, calls: calls)
        #expect(terminal.supportsTerminalQueries)
        let tui = TUI(terminal: terminal)
        tui.programStatusEnvironment = { nil }
        tui.setProgramStatus(ProgramStatus(state: .idle))
        tui.start()
        tui.setProgramStatus(ProgramStatus(state: .working))
        tui.stop()
        #expect(terminal.isLost)
        #expect(writes.withLock { $0 } == 0)
    }

    @Test("terminal loss after confirmation prevents a status report and stop clear")
    func lossAfterSupport() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        try #require(openpty(&master, &slave, nil, nil, nil) == 0)
        defer { close(master); close(slave) }
        let output = OSAllocatedUnfairLock(initialState: [String]())
        var calls = TerminalIOCalls()
        calls.write = { _, bytes, count in
            let data = String(decoding: UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: count), as: UTF8.self)
            output.withLock { $0.append(data) }
            if data == "lose terminal" { errno = EIO; return -1 }
            return count
        }
        let terminal = ProcessTerminal(inputDescriptor: slave, outputDescriptor: slave, calls: calls)
        let tui = TUI(terminal: terminal)
        tui.programStatusEnvironment = { "1" }
        tui.setProgramStatus(ProgramStatus(state: .idle))
        tui.start()
        #expect(output.withLock { $0.contains(formatProgramStatus(ProgramStatus(state: .idle))) })
        terminal.write("lose terminal")
        #expect(terminal.isLost)
        let count = output.withLock { $0.count }
        tui.setProgramStatus(ProgramStatus(state: .working))
        tui.stop()
        tui.start()
        tui.stop()
        #expect(output.withLock { $0.count } == count)
    }
}
