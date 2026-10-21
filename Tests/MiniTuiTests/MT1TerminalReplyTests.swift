import Foundation
import Testing
@testable import MiniTui

private final class MT1ReplyEvents {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class MT1ReplyTerminal: Terminal {
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

@MainActor
private final class MT1ReplyInput: Component {
    var inputs: [String] = []
    func render(width: Int) -> [String] { [] }
    func handleInput(_ data: String) { inputs.append(data) }
}

@Suite("MT1 terminal reply strings")
@MainActor
struct MT1TerminalReplyTests {
    private static let replies: [(header: String, reply: String)] = [
        ("\u{001B}]4;1;", "\u{001B}]4;1;rgb:eaea/6c6c/6d6d\u{0007}"),
        ("\u{001B}]10;", "\u{001B}]10;rgb:ffff/ffff/ffff\u{001B}\\"),
        ("\u{001B}]11;", "\u{001B}]11;rgb:0000/0000/0000\u{0007}"),
        ("\u{001B}]4;1;", "\u{001B}]4;1;rgb:6464/6464/4d4d\u{0007}"),
        ("\u{001B}P>|", "\u{001B}P>|Ghostty 1.3.1\u{001B}\\"),
        ("\u{001B}_Gi=1;", "\u{001B}_Gi=1;OK\u{001B}\\"),
        ("\u{001B}]7501;?", "\u{001B}]7501;?\u{001B}\\"),
    ]

    private func makeBuffer(timeout: TimeInterval = 0.05) -> (StdinBuffer, MT1ReplyEvents) {
        let buffer = StdinBuffer(options: StdinBufferOptions(timeout: timeout))
        let events = MT1ReplyEvents()
        buffer.onData = { events.append($0) }
        return (buffer, events)
    }

    @Test("keeps all seven replies intact at every split after the header for five seconds")
    func everyReplySplit() async throws {
        var pending: [(StdinBuffer, MT1ReplyEvents, String, String)] = []
        for (header, reply) in Self.replies {
            for split in header.count..<reply.count {
                let (buffer, events) = makeBuffer()
                let prefix = String(reply.prefix(split))
                buffer.process(prefix)
                #expect(buffer.getBuffer() == prefix)
                pending.append((buffer, events, reply, String(reply.dropFirst(split))))
            }
        }
        defer { pending.forEach { $0.0.destroy() } }

        // All split cases use the same five-second delay.
        try await Task.sleep(for: .seconds(5))
        for (buffer, events, reply, tail) in pending {
            #expect(events.values.isEmpty)
            buffer.process(tail + "x")
            #expect(events.values == [reply, "x"])
            #expect(!events.values.contains { matchesKey($0, "ctrl+g") })
            #expect(buffer.getBuffer().isEmpty)
        }
    }

    @Test("keeps an OSC reply across repeated expired timeouts")
    func repeatedTimeouts() async throws {
        let (buffer, events) = makeBuffer()
        defer { buffer.destroy() }
        buffer.process("\u{001B}]4;1;rgb:eaea/6c")
        try await Task.sleep(for: .milliseconds(100))
        #expect(events.values.isEmpty)
        buffer.process("6c/6d6d")
        try await Task.sleep(for: .milliseconds(100))
        #expect(events.values.isEmpty)
        buffer.process("\u{0007}")
        #expect(events.values == [Self.replies[0].reply])
    }

    @Test("times out all three bare string introducers")
    func bareIntroducers() async throws {
        var pending: [(StdinBuffer, MT1ReplyEvents, String)] = []
        for prefix in ["\u{001B}]", "\u{001B}P", "\u{001B}_"] {
            let (buffer, events) = makeBuffer(timeout: 0.01)
            buffer.process(prefix)
            pending.append((buffer, events, prefix))
        }
        defer { pending.forEach { $0.0.destroy() } }
        try await Task.sleep(for: .milliseconds(60))
        for (buffer, events, prefix) in pending {
            #expect(events.values == [prefix])
            #expect(buffer.getBuffer().isEmpty)
        }
    }

    @Test("recovers every ambiguous vector as Alt, text, and separate control keys")
    func ambiguousInput() async throws {
        let ambiguous = [
            "\u{001B}]a", "\u{001B}]1", "\u{001B}]10", "\u{001B}]0;title",
            "\u{001B}]4;", "\u{001B}]4;a;", "\u{001B}Pa", "\u{001B}P>",
            "\u{001B}_a", "\u{001B}_G", "\u{001B}_Gi=1",
        ]
        var pending: [(StdinBuffer, MT1ReplyEvents, String)] = []
        for value in ambiguous {
            let (buffer, events) = makeBuffer(timeout: 0.2)
            buffer.process(value)
            #expect(events.values.isEmpty)
            buffer.process("x\r\u{0003}\u{0004}")
            #expect(events.values.isEmpty)
            pending.append((buffer, events, value))
        }
        defer { pending.forEach { $0.0.destroy() } }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while pending.contains(where: { $0.1.values.count != $0.2.count + 3 }), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        for (buffer, events, value) in pending {
            let expected = [String(value.prefix(2))] + value.dropFirst(2).map(String.init)
                + ["x", "\r", "\u{0003}", "\u{0004}"]
            #expect(events.values == expected)
            #expect(buffer.getBuffer().isEmpty)
            buffer.process("y\r\u{0003}\u{0004}")
            #expect(Array(events.values.suffix(4)) == ["y", "\r", "\u{0003}", "\u{0004}"])
        }
    }

    @Test("recognizes a header assembled before the ambiguous-input timeout")
    func assembledHeader() async throws {
        let (buffer, events) = makeBuffer()
        defer { buffer.destroy() }
        buffer.process("\u{001B}]1")
        #expect(events.values.isEmpty)
        buffer.process("0;")
        try await Task.sleep(for: .seconds(5))
        #expect(events.values.isEmpty)
        buffer.process("rgb:ffff/ffff/ffff\u{001B}\\")
        #expect(events.values == [Self.replies[1].reply])
    }

    @Test("holds a trailing ESC and recovers the next escape sequence")
    func newEscapeAbortsReply() async throws {
        let (buffer, events) = makeBuffer()
        defer { buffer.destroy() }
        buffer.process("\u{001B}]4;1;rgb:eaea/6c")
        try await Task.sleep(for: .milliseconds(100))
        buffer.process("\u{001B}")
        try await Task.sleep(for: .milliseconds(100))
        #expect(events.values.isEmpty)
        #expect(buffer.getBuffer() == "\u{001B}]4;1;rgb:eaea/6c\u{001B}")
        buffer.process("[Ahello")
        #expect(events.values == ["\u{001B}[A", "h", "e", "l", "l", "o"])
    }

    @Test("CAN and SUB cancel each reply type and keep later input")
    func cancellation() {
        for cancel in ["\u{0018}", "\u{001A}"] {
            for (header, _) in Self.replies {
                let (buffer, events) = makeBuffer()
                defer { buffer.destroy() }
                buffer.process(header + "unfinished" + cancel + "x")
                #expect(events.values == ["x"])
                #expect(buffer.getBuffer().isEmpty)
            }
        }
    }

    @Test("keeps the exact reply-header recognition boundaries")
    func headerBoundaries() async throws {
        let recognized = [
            "\u{001B}]4;0;", "\u{001B}]4;999;", "\u{001B}]4;000;",
            "\u{001B}_Gm=123,i=2;",
        ]
        let ambiguous = [
            "\u{001B}]12;", "\u{001B}]4;1000;", "\u{001B}]4;١;",
            "\u{001B}]7501;", "\u{001B}]7501;x", "\u{001B}P>",
            "\u{001B}_GI=1;", "\u{001B}_Gi=-1;", "\u{001B}_Gi=١;",
            "\u{001B}_Gi=1,;",
        ]
        var pending: [(StdinBuffer, MT1ReplyEvents, String, Bool)] = []
        for value in recognized + ambiguous {
            let (buffer, events) = makeBuffer(timeout: 0.01)
            buffer.process(value)
            pending.append((buffer, events, value, recognized.contains(value)))
        }
        defer { pending.forEach { $0.0.destroy() } }
        try await Task.sleep(for: .milliseconds(70))
        for (buffer, events, value, held) in pending {
            if held {
                #expect(events.values.isEmpty)
                #expect(buffer.getBuffer() == value)
                buffer.process("\u{001B}\\")
                #expect(events.values == [value + "\u{001B}\\"])
            } else {
                #expect(events.values == [String(value.prefix(2))] + value.dropFirst(2).map(String.init))
                #expect(buffer.getBuffer().isEmpty)
            }
        }
    }

    @Test("keeps replies inside bracketed paste separate from data")
    func pasteRemainsSeparate() async throws {
        let (buffer, events) = makeBuffer(timeout: 0.01)
        let paste = MT1ReplyEvents()
        buffer.onPaste = { paste.append($0) }
        defer { buffer.destroy() }
        buffer.process("\u{001B}[200~\u{001B}]4;1;rgb:eaea/6c")
        try await Task.sleep(for: .milliseconds(60))
        buffer.process("6c/6d6d\u{0007}\u{001B}[201~x")
        #expect(paste.values == [Self.replies[0].reply])
        #expect(events.values == ["x"])
    }

    @Test("TUI consumes delayed Ghostty color fragments and passes a later BEL")
    func delayedGhosttyThroughTUI() async throws {
        let terminal = MT1ReplyTerminal()
        let tui = TUI(terminal: terminal)
        let component = MT1ReplyInput()
        let buffer = StdinBuffer()
        buffer.onData = { terminal.sendInput($0) }
        tui.addChild(component)
        tui.setFocus(component)
        tui.start()
        defer {
            buffer.destroy()
            tui.stop()
        }
        let query = Task { @MainActor in await tui.queryTerminalColors(timeoutMs: 1_000) }
        await Task.yield()
        buffer.process("\u{001B}]4;1;rgb:eaea/6c")
        try await Task.sleep(for: .milliseconds(100))
        #expect(component.inputs.isEmpty)
        buffer.process("6c/6d6d\u{0007}\u{001B}[?62;22c")
        #expect(await query.value == TerminalColors())
        #expect(component.inputs.isEmpty)
        buffer.process("\u{0007}")
        await Task.yield()
        #expect(component.inputs == ["\u{0007}"])
    }
}
