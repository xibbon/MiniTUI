import Foundation
import Testing
#if canImport(os)
import os
#else
import Synchronization
#endif
#if os(Linux)
import Glibc
#else
import Darwin
#endif
@testable import MiniTui

private let mt1Escape = "\u{001B}"

private struct MT1ExitResult {
    let output: String
    let status: Int32
    let saved: termios
    let final: termios
}

private func mt1CloseOnExec(_ descriptor: Int32) throws {
    let flags = fcntl(descriptor, F_GETFD)
    let getErrno = errno
    try #require(flags != -1,
                 "F_GETFD(\(descriptor)) failed: errno=\(getErrno) (\(String(cString: strerror(getErrno))))")
    let result = fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC)
    let setErrno = errno
    try #require(result == 0,
                 "F_SETFD(\(descriptor)) failed: errno=\(setErrno) (\(String(cString: strerror(setErrno))))")
}

private func mt1RunExitFixture(_ mode: String) async throws -> MT1ExitResult {
    var master: Int32 = -1
    var slave: Int32 = -1
    var ptyResult: Int32
    var ptyErrno: Int32
    var attempts = 0
    while true {
        ptyResult = openpty(&master, &slave, nil, nil, nil)
        ptyErrno = errno
        attempts += 1
        #if canImport(Darwin)
        // XNU ptmx_get_ioctl requests EREDRIVEOPEN (-6) after an allocation race.
        // Redrive only that kernel request. All other errors fail immediately.
        // https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/tty_ptmx.c
        if ptyResult == -1, ptyErrno == -6, attempts < 8 {
            print("MT1 openpty(\(mode)): errno=\(ptyErrno) (\(String(cString: strerror(ptyErrno)))); redrive \(attempts)/8")
            continue
        }
        #endif
        break
    }
    try #require(ptyResult == 0,
                 "openpty(\(mode)) failed after \(attempts) attempt(s): errno=\(ptyErrno) (\(String(cString: strerror(ptyErrno))))")
    defer { if master >= 0 { close(master) }; close(slave) }
    try mt1CloseOnExec(master)
    try mt1CloseOnExec(slave)
    var saved = termios()
    try #require(tcgetattr(slave, &saved) == 0)
    var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    while !FileManager.default.isExecutableFile(atPath: directory.appendingPathComponent("MiniTuiExitRestoreFixture").path),
          directory.path != "/" {
        directory.deleteLastPathComponent()
    }
    let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let executable = directory.path == "/"
        ? package.appendingPathComponent(".build/debug/MiniTuiExitRestoreFixture")
        : directory.appendingPathComponent("MiniTuiExitRestoreFixture")
    try #require(FileManager.default.isExecutableFile(atPath: executable.path))
    let process = Process()
    let output = Pipe()
    let errors = Pipe()
    for descriptor in [output.fileHandleForReading.fileDescriptor, output.fileHandleForWriting.fileDescriptor,
                       errors.fileHandleForReading.fileDescriptor, errors.fileHandleForWriting.fileDescriptor] {
        try mt1CloseOnExec(descriptor)
    }
    process.executableURL = executable
    process.arguments = [mode]
    var environment = ProcessInfo.processInfo.environment
    for key in ["TMUX", "STY", "ZELLIJ", "PI_TUI_WRITE_LOG", "PI_PROGRAM_STATUS"] { environment.removeValue(forKey: key) }
    environment["TERM"] = "xterm-256color"
    process.environment = environment
    process.standardInput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    defer { if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() } }
    var prefix = Data()
    let deadline = Date().addingTimeInterval(10)
    if mode == "loss" {
        let descriptor = output.fileHandleForReading.fileDescriptor
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
        while !String(decoding: prefix, as: UTF8.self).contains("MT1-READY\n"), process.isRunning, Date() < deadline {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 { prefix.append(contentsOf: buffer.prefix(count)) }
            else { try await Task.sleep(for: .milliseconds(5)) }
        }
        try #require(String(decoding: prefix, as: UTF8.self).hasSuffix("MT1-READY\n"))
        close(master)
        master = -1
        _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) & ~O_NONBLOCK)
    }
    while process.isRunning, Date() < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(!process.isRunning, "The exit fixture must finish within ten seconds")
    // isRunning is already false. A second Foundation run-loop wait can stall
    // here even after the child is gone (MT1 resume diagnostic process sample).
    prefix.append(output.fileHandleForReading.readDataToEndOfFile())
    let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    #expect(errorText.isEmpty)
    var final = termios()
    if mode != "loss" { try #require(tcgetattr(slave, &final) == 0) }
    return MT1ExitResult(output: String(decoding: prefix, as: UTF8.self), status: process.terminationStatus,
                         saved: saved, final: final)
}

private func mt1Count(_ output: String, _ sequence: String) -> Int {
    output.components(separatedBy: sequence).count - 1
}

@Suite("MT1 synchronous exit restore")
struct MT1ExitRestoreTests {
    @Test("direct exit restores each mode once in order", arguments: ["exit-alt", "exit-main"])
    func directExit(_ mode: String) async throws {
        let result = try await mt1RunExitFixture(mode)
        #expect(result.status == 0)
        let output = result.output
        let terminalResets = terminalProgressClearSequence + mt1Escape + "[?2004l" + mt1Escape + "[<u" + mt1Escape + "[>4;0m"
        let common = mt1Escape + "[?2031l" + mt1Escape + "[?25h"
        if mode == "exit-alt" {
            let mouse = [1006, 1004, 1003, 1002, 1000].map { mt1Escape + "[?\($0)l" }.joined()
            let prefix = mt1Escape + "[?2026l" + mouse + mt1Escape + "[?7h" + common
            #expect(output.hasSuffix("MT1-EXIT\n" + prefix + terminalResets + mt1Escape + "[?1049l" + mt1Escape + "[?25h"))
            for mode in [1006, 1004, 1003, 1002, 1000, 1049] {
                #expect(mt1Count(output, mt1Escape + "[?\(mode)l") == 1)
            }
            let pop = try #require(output.range(of: mt1Escape + "[<u"))
            let leave = try #require(output.range(of: mt1Escape + "[?1049l"))
            #expect(pop.lowerBound < leave.lowerBound)
        } else {
            #expect(output.hasSuffix("MT1-EXIT\n" + common + terminalResets))
            #expect(!output.contains(mt1Escape + "[?1049l"))
        }
        for sequence in [terminalProgressClearSequence, mt1Escape + "[?2031l", mt1Escape + "[?2004l", mt1Escape + "[<u", mt1Escape + "[>4;0m"] {
            #expect(mt1Count(output, sequence) == 1)
        }
        // Darwin can set PENDIN when cooked input is restored.
        #expect(result.final.c_lflag & ~tcflag_t(PENDIN) == result.saved.c_lflag & ~tcflag_t(PENDIN))
        #expect(result.final.c_iflag == result.saved.c_iflag)
        #expect(result.final.c_oflag == result.saved.c_oflag)
        #expect(result.final.c_cflag == result.saved.c_cflag)
    }

    @Test("normal stop and suspension disarm exit restore", arguments: ["stop-alt", "stop-main"])
    func normalStop(_ mode: String) async throws {
        let result = try await mt1RunExitFixture(mode)
        #expect(result.status == 0)
        #expect(result.output.hasSuffix("MT1-EXIT\n"))
        for sequence in [mt1Escape + "[?2031l", mt1Escape + "[?2004l", mt1Escape + "[<u", mt1Escape + "[>4;0m"] {
            #expect(mt1Count(result.output, sequence) == 1)
        }
        if mode == "stop-alt" {
            for mode in [1006, 1004, 1003, 1000, 1049] {
                #expect(mt1Count(result.output, mt1Escape + "[?\(mode)l") == 1)
            }
        }
        #expect(result.final.c_lflag & ~tcflag_t(PENDIN) == result.saved.c_lflag & ~tcflag_t(PENDIN))
    }

    @Test("start stop start rearms one exit restore", arguments: ["restart-alt", "restart-main"])
    func restart(_ mode: String) async throws {
        let result = try await mt1RunExitFixture(mode)
        #expect(result.status == 0)
        for sequence in [mt1Escape + "[?2031l", mt1Escape + "[?2004l", mt1Escape + "[<u", mt1Escape + "[>4;0m"] {
            #expect(mt1Count(result.output, sequence) == 2)
        }
        let afterRestart = try #require(result.output.components(separatedBy: "MT1-RESTART\n").last)
        #expect(mt1Count(afterRestart, mt1Escape + "[?2004l") == 1)
        if mode == "restart-alt" { #expect(result.output.hasSuffix(mt1Escape + "[?1049l" + mt1Escape + "[?25h")) }
        #expect(result.final.c_lflag & ~tcflag_t(PENDIN) == result.saved.c_lflag & ~tcflag_t(PENDIN))
    }

    @Test("inactive modes add no resets", arguments: ["exit-main-minimal", "exit-alt-minimal-no-mouse"])
    func inactiveModes(_ mode: String) async throws {
        let result = try await mt1RunExitFixture(mode)
        #expect(result.status == 0)
        for sequence in [terminalProgressClearSequence, mt1Escape + "[?2031l", mt1Escape + "[<u", mt1Escape + "[>4;0m", mt1Escape + "[?1004l"] {
            #expect(!result.output.contains(sequence))
        }
        #expect(mt1Count(result.output, mt1Escape + "[?2004l") == 1)
    }

    @Test("renderer switch updates the exit snapshot")
    func rendererSwitch() async throws {
        let result = try await mt1RunExitFixture("exit-alt-switch")
        #expect(result.status == 0)
        #expect(mt1Count(result.output, mt1Escape + "[?1049l") == 1)
        let suffix = try #require(result.output.components(separatedBy: "MT1-EXIT\n").last)
        #expect(!suffix.contains(mt1Escape + "[?1049l"))
        #expect(!suffix.contains(mt1Escape + "[?1004l"))
    }

    @Test("terminal loss exits 129 with no exit output")
    func terminalLoss() async throws {
        let result = try await mt1RunExitFixture("loss")
        #expect(result.status == 129)
        #expect(result.output.hasSuffix("MT1-READY\n"))
        for sequence in [terminalProgressClearSequence, mt1Escape + "[?2031l", mt1Escape + "[?2004l", mt1Escape + "[<u", mt1Escape + "[>4;0m", mt1Escape + "[?1049l"] {
            #expect(!result.output.contains(sequence))
        }
    }

    @Test("old Terminal conformers keep the default hook")
    func defaultHook() {
        let terminal: any Terminal = VirtualTerminal()
        terminal.restoreOnExit("before", "after")
    }

    @Test("custom hooks run at exit and during terminal or renderer start", arguments: ["custom", "custom-start", "custom-alt-start"])
    func customHook(_ mode: String) async throws {
        let result = try await mt1RunExitFixture(mode)
        #expect(result.status == 0)
        let common = mt1Escape + "[?2031l" + mt1Escape + "[?25h"
        if mode == "custom-alt-start" {
            let mouse = [1006, 1004, 1003, 1002, 1000].map { mt1Escape + "[?\($0)l" }.joined()
            #expect(result.output == "MT1-CUSTOM:" + mt1Escape + "[?2026l" + mouse + mt1Escape + "[?7h" + common
                    + "|" + mt1Escape + "[?1049l" + mt1Escape + "[?25h")
        } else {
            #expect(result.output == "MT1-CUSTOM:" + common + "|")
        }
    }

    @Test("notification changes update the exit snapshot", arguments: ["exit-main-color-late", "exit-alt-color-off"])
    func colorNotifications(_ mode: String) async throws {
        let result = try await mt1RunExitFixture(mode)
        #expect(result.status == 0)
        #expect(mt1Count(result.output, mt1Escape + "[?2031l") == 1)
        let suffix = try #require(result.output.components(separatedBy: "MT1-EXIT\n").last)
        #expect(suffix.contains(mt1Escape + "[?2031l") == mode.contains("color-late"))
    }

    @Test("exit restore can run while checked I/O holds its lock")
    func independentLock() {
        #if canImport(os)
        let handler = OSAllocatedUnfairLock(initialState: Optional<TerminalExitRestoreHandler>.none)
        let count = OSAllocatedUnfairLock(initialState: 0)
        #else
        let handler = Mutex(Optional<TerminalExitRestoreHandler>.none)
        let count = Mutex(0)
        #endif
        var calls = TerminalIOCalls()
        calls.write = { _, _, length in
            let attempt = count.withLock { $0 += 1; return $0 }
            if attempt == 1 { handler.withLock { $0 }?("before", "after") }
            return length
        }
        let terminal = ProcessTerminal(inputDescriptor: -1, outputDescriptor: STDOUT_FILENO, calls: calls)
        terminal.prepareExitRestore()
        let restore = terminal.restoreOnExit
        handler.withLock { $0 = restore }
        terminal.write("trigger")
        #expect(count.withLock { $0 } == 2)
        terminal.restoreOnExit("duplicate", "duplicate")
        #expect(count.withLock { $0 } == 2)
    }

    @Test("loss or stop during a short write cancels remaining restore calls", arguments: [true, false])
    func invalidationDuringRestore(_ loss: Bool) {
        #if canImport(os)
        let reference = OSAllocatedUnfairLock(initialState: Optional<TerminalExitState>.none)
        let counts = OSAllocatedUnfairLock(initialState: (writes: 0, restores: 0))
        #else
        let reference = Mutex(Optional<TerminalExitState>.none)
        let counts = Mutex((writes: 0, restores: 0))
        #endif
        var calls = TerminalIOCalls()
        calls.write = { _, _, _ in
            counts.withLock { $0.writes += 1 }
            let state = reference.withLock { $0 }
            if loss { state?.invalidate() } else { state?.disarm() }
            return 1
        }
        calls.setAttributes = { _, _, _ in counts.withLock { $0.restores += 1 }; return 0 }
        let state = TerminalExitState(inputDescriptor: 10, outputDescriptor: 11, calls: calls)
        reference.withLock { $0 = state }
        state.arm()
        state.save(termios())
        state.restore(before: "before", after: "after")
        #expect(counts.withLock { $0.writes == 1 && $0.restores == 0 })
    }

    @Test("exit writes retry EINTR and short writes")
    func interruptedWrite() {
        #if canImport(os)
        let result = OSAllocatedUnfairLock(initialState: (attempts: 0, bytes: [UInt8]()))
        #else
        let result = Mutex((attempts: 0, bytes: [UInt8]()))
        #endif
        var calls = TerminalIOCalls()
        calls.write = { _, pointer, length in
            let bytes = Array(UnsafeRawBufferPointer(start: pointer, count: min(2, length)))
            let count = result.withLock { result in
                result.attempts += 1
                if result.attempts == 1 { return -1 }
                result.bytes.append(contentsOf: bytes)
                return bytes.count
            }
            if count == -1 { errno = EINTR }
            return count
        }
        let state = TerminalExitState(inputDescriptor: 10, outputDescriptor: 11, calls: calls)
        state.arm()
        state.restore(before: "before", after: "after")
        #expect(result.withLock { String(decoding: $0.bytes, as: UTF8.self) } == "before" + mt1Escape + "[?2004lafter")
    }

    @Test("emergency restore is one shot and ignores system call errors")
    func oneShot() {
        #if canImport(os)
        let counts = OSAllocatedUnfairLock(initialState: (writes: 0, restores: 0))
        #else
        let counts = Mutex((writes: 0, restores: 0))
        #endif
        var calls = TerminalIOCalls()
        calls.write = { _, _, _ in counts.withLock { $0.writes += 1 }; errno = EIO; return -1 }
        calls.setAttributes = { _, _, _ in counts.withLock { $0.restores += 1 }; errno = EIO; return -1 }
        let state = TerminalExitState(inputDescriptor: 10, outputDescriptor: 11, calls: calls)
        state.arm()
        state.save(termios())
        state.restore(before: "before", after: "after")
        state.restore(before: "duplicate", after: "duplicate")
        #expect(counts.withLock { $0.writes == 1 && $0.restores == 1 })
    }
}
