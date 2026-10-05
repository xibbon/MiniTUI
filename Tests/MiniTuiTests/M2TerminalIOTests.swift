import Darwin
import Foundation
import Dispatch
import Testing
import os
@testable import MiniTui

private struct M2Pty {
    let master: Int32
    let slave: Int32

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        try #require(openpty(&master, &slave, nil, nil, nil) == 0)
        self.master = master
        self.slave = slave
    }
}

private func m2Wait(_ condition: () -> Bool) async throws {
    for _ in 0..<100 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

@Suite("M2 checked terminal I/O", .serialized)
struct M2TerminalIOTests {
    @Test("typed errors use exactly the upstream codes and terminal EOF")
    func classification() {
        for operation in [TerminalIOError.Operation.read, .write, .getAttributes, .setAttributes] {
            for code in [EIO, EPIPE, ENOTCONN, ENOTTY, EINTR, EAGAIN, EBADF, ECONNREFUSED] {
                let error = TerminalIOError.systemCall(operation: operation, descriptor: 42, errno: code)
                #expect(error.operation == operation && error.descriptor == 42 && error.errno == code)
                #expect(error.isTerminalLoss == [EIO, EPIPE, ENOTCONN, ENOTTY].contains(code))
            }
        }
        let eof = TerminalIOError.endOfFile(descriptor: 3, isTerminalInput: true)
        #expect(eof.operation == .read && eof.descriptor == 3 && eof.errno == nil && eof.isTerminalLoss)
        #expect(!TerminalIOError.endOfFile(descriptor: 3, isTerminalInput: false).isTerminalLoss)
    }

    @Test("closed pty master stops reads and reports one loss")
    func readLoss() async throws {
        let pty = try M2Pty()
        var masterOpen = true
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let input = OSAllocatedUnfairLock(initialState: [String]())
        let counts = OSAllocatedUnfairLock(initialState: (writes: 0, sets: 0, flushes: 0))
        var calls = TerminalIOCalls()
        calls.write = { fd, bytes, count in
            counts.withLock { $0.writes += 1 }
            return Darwin.write(fd, bytes, count)
        }
        calls.setAttributes = { fd, action, attributes in
            counts.withLock { $0.sets += 1 }
            return tcsetattr(fd, action, attributes)
        }
        calls.flush = { fd, action in
            counts.withLock { $0.flushes += 1 }
            return tcflush(fd, action)
        }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        defer {
            terminal.stop()
            if masterOpen { close(pty.master) }
            close(pty.slave)
        }
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.start(onInput: { value in input.withLock { $0.append(value) } }, onResize: {})
        let text = "before"
        _ = text.withCString { Darwin.write(pty.master, $0, text.utf8.count) }
        try await m2Wait { input.withLock { $0.joined() == text } }
        #expect(close(pty.master) == 0)
        masterOpen = false
        try await m2Wait { events.withLock { !$0.isEmpty } }
        let error = try #require(events.withLock { $0.first })
        #expect(error.operation == .read && error.descriptor == pty.slave && error.isTerminalLoss)
        #expect(error.errno == EIO || error == .endOfFile(descriptor: pty.slave, isTerminalInput: true))
        print("M2 Darwin closed pty read: \(error)")
        let attempts = terminal.readAttempts
        let before = counts.withLock { $0 }
        let inputBefore = input.withLock { $0 }
        terminal.write("after loss")
        let start = Date()
        terminal.drainInput(maxMs: 1000, idleMs: 1000)
        terminal.stop()
        #expect(Date().timeIntervalSince(start) < 0.1)
        try await Task.sleep(for: .milliseconds(300))
        #expect(terminal.readAttempts == attempts && attempts <= 4)
        #expect(events.withLock { $0.count } == 1)
        #expect(input.withLock { $0 } == inputBefore)
        #expect(counts.withLock { $0.writes == before.writes && $0.sets == before.sets && $0.flushes == before.flushes })
        print("M2 read attempts: \(attempts), after 300 ms: \(terminal.readAttempts)")
    }

    @Test("a write to a closed pty reports the platform error once")
    func writeLoss() throws {
        let pty = try M2Pty()
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave)
        defer { terminal.stop(); close(pty.slave) }
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        #expect(close(pty.master) == 0)
        terminal.write("first")
        terminal.write("second")
        let error = try #require(events.withLock { $0.first })
        print("M2 Darwin closed pty write: \(error)")
        #expect(error.operation == .write && error.descriptor == pty.slave && error.isTerminalLoss)
        #expect(events.withLock { $0.count } == 1)
    }

    @Test("descriptor SIGPIPE suppression returns EPIPE from a closed pipe")
    func pipeLoss() throws {
        let pty = try M2Pty()
        var pipeFDs: [Int32] = [-1, -1]
        try #require(pipe(&pipeFDs) == 0)
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pipeFDs[1])
        defer { terminal.stop(); close(pipeFDs[1]); close(pty.master); close(pty.slave) }
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        #expect(close(pipeFDs[0]) == 0)
        terminal.write("first")
        terminal.write("second")
        #expect(events.withLock { $0 } == [.systemCall(operation: .write, descriptor: pipeFDs[1], errno: EPIPE)])
        #expect(fcntl(pipeFDs[1], F_GETNOSIGPIPE) == 1)
    }

    @Test("partial writes and EINTR preserve all bytes in order")
    func partialWrite() throws {
        let pty = try M2Pty()
        defer { close(pty.master); close(pty.slave) }
        let output = OSAllocatedUnfairLock(initialState: (attempts: 0, bytes: [UInt8]()))
        var calls = TerminalIOCalls()
        calls.write = { _, pointer, count in
            let bytes = Array(UnsafeRawBufferPointer(start: pointer, count: min(2, count)))
            return output.withLock { state in
                state.attempts += 1
                if state.attempts == 2 { errno = EINTR; return -1 }
                let written = min(2, count)
                state.bytes.append(contentsOf: bytes)
                return written
            }
        }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.write("aébcde")
        #expect(output.withLock { $0.bytes } == Array("aébcde".utf8))
        #expect(output.withLock { $0.attempts } == 5)
        #expect(events.withLock { $0.isEmpty })
    }

    @Test("non-loss read errors cancel readiness without stopping output")
    func nonLossRead() async throws {
        let pty = try M2Pty()
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        var calls = TerminalIOCalls()
        calls.read = { _, _, _ in errno = ECONNREFUSED; return -1 }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        defer { terminal.stop(); close(pty.master); close(pty.slave) }
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.start(onInput: { _ in Issue.record("Input must stop after a read error") }, onResize: {})
        _ = "x".withCString { Darwin.write(pty.master, $0, 1) }
        try await m2Wait { events.withLock { !$0.isEmpty } }
        #expect(events.withLock { $0 } == [.systemCall(operation: .read, descriptor: pty.slave, errno: ECONNREFUSED)])
        #expect(events.withLock { !$0[0].isTerminalLoss })
        let attempts = terminal.readAttempts
        terminal.write("output remains available")
        try await Task.sleep(for: .milliseconds(300))
        #expect(attempts == 1 && terminal.readAttempts == attempts)
        #expect(events.withLock { $0.count } == 1)
    }

    @Test("transient read errors retry on the next readiness")
    func transientReads() async throws {
        let pty = try M2Pty()
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let input = OSAllocatedUnfairLock(initialState: [String]())
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        var calls = TerminalIOCalls()
        calls.read = { fd, bytes, count in
            let attempt = attempts.withLock { $0 += 1; return $0 }
            if attempt <= 3 { errno = [EINTR, EAGAIN, EWOULDBLOCK][attempt - 1]; return -1 }
            return Darwin.read(fd, bytes, count)
        }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        defer { terminal.stop(); close(pty.master); close(pty.slave) }
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.start(onInput: { value in input.withLock { $0.append(value) } }, onResize: {})
        _ = "ok".withCString { Darwin.write(pty.master, $0, 2) }
        try await m2Wait { input.withLock { $0.joined() == "ok" } }
        #expect(attempts.withLock { $0 } == 4)
        #expect(events.withLock { $0.isEmpty })
    }

    @Test("EOF on a pipe stops reads and is not terminal loss")
    func pipeEOF() throws {
        var fds: [Int32] = [-1, -1]
        try #require(pipe(&fds) == 0)
        defer { close(fds[0]) }
        close(fds[1])
        let pty = try M2Pty()
        defer { close(pty.master); close(pty.slave) }
        let io = CheckedTerminalIO(inputDescriptor: fds[0], outputDescriptor: pty.slave, calls: TerminalIOCalls())
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        io.setHandler { error in events.withLock { $0.append(error) } }
        #expect(io.readReady() == nil)
        #expect(io.readReady() == nil)
        #expect(events.withLock { $0 } == [.endOfFile(descriptor: fds[0], isTerminalInput: false)])
        #expect(!io.isLost && io.readAttempts == 1)
    }

    @Test("non-loss write errors stop all later output")
    func nonLossWrite() throws {
        let pty = try M2Pty()
        defer { close(pty.master); close(pty.slave) }
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        var calls = TerminalIOCalls()
        calls.write = { _, _, _ in attempts.withLock { $0 += 1 }; errno = EBADF; return -1 }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.write("first")
        terminal.write("second")
        terminal.stop()
        #expect(attempts.withLock { $0 } == 1)
        #expect(events.withLock { $0 } == [.systemCall(operation: .write, descriptor: pty.slave, errno: EBADF)])
        #expect(events.withLock { !$0[0].isTerminalLoss })
    }

    @Test("raw-mode get failure reports saved errno and continues for non-loss")
    func getAttributesFailure() async throws {
        let pty = try M2Pty()
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let input = OSAllocatedUnfairLock(initialState: [String]())
        var calls = TerminalIOCalls()
        calls.getAttributes = { _, _ in errno = EACCES; return -1 }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        defer { terminal.stop(); close(pty.master); close(pty.slave) }
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) }; errno = EIO }
        terminal.start(onInput: { value in input.withLock { $0.append(value) } }, onResize: {})
        _ = "ok\n".withCString { Darwin.write(pty.master, $0, 3) }
        try await m2Wait { input.withLock { $0.joined() == "ok\n" } }
        #expect(events.withLock { $0 } == [.systemCall(operation: .getAttributes, descriptor: pty.slave, errno: EACCES)])
    }

    @Test("raw-mode loss prevents reads, output, flush, and restore")
    func rawModeLoss() throws {
        for operation in [TerminalIOError.Operation.getAttributes, .setAttributes] {
            let pty = try M2Pty()
            defer { close(pty.master); close(pty.slave) }
            let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
            let counts = OSAllocatedUnfairLock(initialState: (writes: 0, sets: 0, flushes: 0))
            var calls = TerminalIOCalls()
            if operation == .getAttributes { calls.getAttributes = { _, _ in errno = ENOTTY; return -1 } }
            calls.setAttributes = { _, _, _ in counts.withLock { $0.sets += 1 }; errno = EIO; return -1 }
            calls.write = { _, _, count in counts.withLock { $0.writes += 1 }; return count }
            calls.flush = { _, _ in counts.withLock { $0.flushes += 1 }; return 0 }
            let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
            terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
            terminal.start(onInput: { _ in Issue.record("Unexpected input") }, onResize: {})
            terminal.write("after")
            terminal.stop()
            #expect(terminal.readAttempts == 0)
            #expect(events.withLock { $0 } == [.systemCall(operation: operation, descriptor: pty.slave, errno: operation == .getAttributes ? ENOTTY : EIO)])
            #expect(counts.withLock { $0.writes == 0 && $0.flushes == 0 && $0.sets == (operation == .getAttributes ? 0 : 1) })
        }
    }

    @Test("raw-mode restore failure is checked once")
    func restoreFailure() throws {
        let pty = try M2Pty()
        defer { close(pty.master); close(pty.slave) }
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let sets = OSAllocatedUnfairLock(initialState: 0)
        var calls = TerminalIOCalls()
        calls.setAttributes = { _, _, _ in
            let attempt = sets.withLock { $0 += 1; return $0 }
            if attempt == 1 { return 0 }
            errno = EIO
            return -1
        }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.start(onInput: { _ in }, onResize: {})
        terminal.stop()
        terminal.stop()
        #expect(sets.withLock { $0 } == 2)
        #expect(events.withLock { $0 } == [.systemCall(operation: .setAttributes, descriptor: pty.slave, errno: EIO)])
    }

    @Test("non-loss raw-mode set failure continues and restore is checked")
    func nonLossSetAttributes() async throws {
        let pty = try M2Pty()
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let input = OSAllocatedUnfairLock(initialState: [String]())
        var calls = TerminalIOCalls()
        calls.setAttributes = { _, _, _ in errno = EACCES; return -1 }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        defer { terminal.stop(); close(pty.master); close(pty.slave) }
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.start(onInput: { value in input.withLock { $0.append(value) } }, onResize: {})
        _ = "ok\n".withCString { Darwin.write(pty.master, $0, 3) }
        try await m2Wait { input.withLock { $0.joined() == "ok\n" } }
        terminal.stop()
        #expect(events.withLock { $0 } == Array(repeating: .systemCall(operation: .setAttributes, descriptor: pty.slave, errno: EACCES), count: 2))
    }

    @Test("input can restart after a normal stop")
    func restart() async throws {
        let pty = try M2Pty()
        let input = OSAllocatedUnfairLock(initialState: [String]())
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave)
        defer { terminal.stop(); close(pty.master); close(pty.slave) }
        terminal.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        for value in ["a", "b"] {
            terminal.start(onInput: { text in input.withLock { $0.append(text) } }, onResize: {})
            _ = value.withCString { Darwin.write(pty.master, $0, 1) }
            try await m2Wait { input.withLock { $0.last == value } }
            terminal.stop()
        }
        #expect(input.withLock { $0 } == ["a", "b"])
        #expect(events.withLock { $0.isEmpty })
    }

    @Test("handler removal suppresses delivery and callbacks can stop I/O")
    func handlerRemoval() throws {
        let pty = try M2Pty()
        defer { close(pty.master); close(pty.slave) }
        var calls = TerminalIOCalls()
        calls.write = { _, _, _ in errno = EIO; return -1 }
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let io = CheckedTerminalIO(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        io.setHandler { error in
            events.withLock { $0.append(error) }
            io.stop()
            io.setHandler(nil)
        }
        #expect(!io.write(Data([1])))
        #expect(!io.write(Data([2])))
        #expect(events.withLock { $0.count } == 1)
        let other = CheckedTerminalIO(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        other.setHandler { error in events.withLock { $0.append(error) } }
        other.setHandler(nil)
        #expect(!other.write(Data([1])))
        #expect(events.withLock { $0.count } == 1)
    }

    @Test("concurrent loss paths deliver one event and no later calls")
    func concurrentLoss() throws {
        let pty = try M2Pty()
        defer { close(pty.master); close(pty.slave) }
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        let callsMade = OSAllocatedUnfairLock(initialState: 0)
        var calls = TerminalIOCalls()
        calls.read = { _, _, _ in callsMade.withLock { $0 += 1 }; errno = EIO; return -1 }
        calls.write = { _, _, _ in callsMade.withLock { $0 += 1 }; errno = EPIPE; return -1 }
        let io = CheckedTerminalIO(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        io.setHandler { error in events.withLock { $0.append(error) } }
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            if index % 2 == 0 { _ = io.readReady() }
            else { _ = io.write(Data([1])) }
        }
        #expect(events.withLock { $0.count } == 1)
        #expect(callsMade.withLock { $0 } == 1)
    }

    @MainActor
    @Test("default protocol hook works on an existing conformer and through TUI")
    func defaultHook() {
        let terminal = VirtualTerminal()
        terminal.setIOErrorHandler { _ in Issue.record("The default hook must do nothing") }
        terminal.setIOErrorHandler(nil)
        let tui = TUI(terminal: terminal)
        tui.setIOErrorHandler { _ in Issue.record("The default hook must do nothing") }
        tui.setIOErrorHandler(nil)
    }

    @MainActor
    @Test("TUI forwards the hook to ProcessTerminal")
    func tuiHook() throws {
        let pty = try M2Pty()
        defer { close(pty.master); close(pty.slave) }
        var calls = TerminalIOCalls()
        calls.write = { _, _, _ in errno = EIO; return -1 }
        let terminal = ProcessTerminal(inputDescriptor: pty.slave, outputDescriptor: pty.slave, calls: calls)
        let tui = TUI(terminal: terminal)
        let events = OSAllocatedUnfairLock(initialState: [TerminalIOError]())
        tui.setIOErrorHandler { error in events.withLock { $0.append(error) } }
        terminal.write("loss")
        #expect(events.withLock { $0 } == [.systemCall(operation: .write, descriptor: pty.slave, errno: EIO)])
        tui.setIOErrorHandler(nil)
    }
}
