import Foundation
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

/// A synchronous restore operation that can run without an actor.
public typealias TerminalExitRestoreHandler = @Sendable (_ before: String, _ after: String) -> Void

/// This lock protects snapshots only. No system call or user callback runs under it.
final class TerminalExitState: Sendable {
    private struct State {
        var armed = false
        var lost = false
        var generation: UInt64 = 0
        var originalTermios: termios?
        var progress = false
        var kitty = false
        var modifyOtherKeys = false
    }

    #if canImport(os)
    private let state = OSAllocatedUnfairLock(initialState: State())
    #else
    private let state = Mutex(State())
    #endif
    private let inputDescriptor: Int32
    private let outputDescriptor: Int32
    private let calls: TerminalIOCalls

    init(inputDescriptor: Int32, outputDescriptor: Int32, calls: TerminalIOCalls) {
        self.inputDescriptor = inputDescriptor
        self.outputDescriptor = outputDescriptor
        self.calls = calls
    }

    func arm() {
        state.withLock {
            if !$0.lost, !$0.armed { $0.generation &+= 1; $0.armed = true }
        }
    }
    func disarm() { state.withLock { $0.generation &+= 1; $0.armed = false; $0.originalTermios = nil } }
    func invalidate() { state.withLock { $0.generation &+= 1; $0.lost = true; $0.armed = false; $0.originalTermios = nil } }
    func save(_ attributes: termios) { state.withLock { $0.originalTermios = attributes } }
    var kitty: Bool { state.withLock { $0.kitty } }
    var modifyOtherKeys: Bool { state.withLock { $0.modifyOtherKeys } }

    /// Track modes sent through the public raw-write API as well as negotiated modes.
    func recordOutput(_ output: String) {
        guard output.contains("\u{001B}[>") || output.contains("\u{001B}[<u")
                || output.contains("\u{001B}]9;4;") else { return }
        let pattern = #"\x1B\[>(\d+)(?:;(\d+))?([um])|\x1B\[<u|\x1B\]9;4;(\d+)\x07"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..., in: output))
        enum Change: Sendable { case progress(Bool), kitty(Bool), modifyOtherKeys(Bool) }
        let changes: [Change] = matches.compactMap { match in
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: output).map { String(output[$0]) }
            }
            if let progress = group(4) { return .progress(progress != "0") }
            if group(3) == "u" { return .kitty(true) }
            if group(1) == "4", group(3) == "m", let mode = group(2) {
                return .modifyOtherKeys(mode != "0")
            }
            if group(1) == nil { return .kitty(false) }
            return nil
        }
        state.withLock { state in
            for change in changes {
                switch change {
                case .progress(let active): state.progress = active
                case .kitty(let active): state.kitty = active
                case .modifyOtherKeys(let active): state.modifyOtherKeys = active
                }
            }
        }
    }

    func restore(before: String, after: String) {
        let snapshot = state.withLock { state -> State? in
            guard state.armed, !state.lost else { return nil }
            let snapshot = state
            state.armed = false
            state.originalTermios = nil
            return snapshot
        }
        guard let snapshot else { return }
        func isCurrent() -> Bool { state.withLock { !$0.lost && $0.generation == snapshot.generation } }
        var sequence = before
        if snapshot.progress { sequence += terminalProgressClearSequence }
        sequence += "\u{001B}[?2004l"
        if snapshot.kitty { sequence += "\u{001B}[<u" }
        if snapshot.modifyOtherKeys { sequence += "\u{001B}[>4;0m" }
        sequence += after
        // Bypass CheckedTerminalIO: no I/O lock, error delivery, flush, or logging.
        let bytes = Array(sequence.utf8)
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                guard isCurrent() else { return }
                let count = calls.write(outputDescriptor, base.advanced(by: offset), buffer.count - offset)
                if count > 0 { offset += count }
                else if count < 0, errno == EINTR { continue }
                else { break }
            }
        }
        if isCurrent(), var attributes = snapshot.originalTermios {
            _ = calls.setAttributes(inputDescriptor, TCSANOW, &attributes)
        }
    }
}

/// Each TUI owns one entry. The exit callback consumes all entries before calling them.
final class TerminalExitRegistration: Sendable {
    private struct Entry: Sendable {
        let restore: TerminalExitRestoreHandler
        let before: String
        let after: String
    }
    #if canImport(os)
    private static let entries = OSAllocatedUnfairLock(initialState: [UUID: Entry]())
    #else
    private static let entries = Mutex([UUID: Entry]())
    #endif
    private static let install: Void = { atexit { restoreAll() } }()
    private let id = UUID()

    func arm(restore: @escaping TerminalExitRestoreHandler, before: String, after: String) {
        _ = Self.install
        Self.entries.withLock { $0[id] = Entry(restore: restore, before: before, after: after) }
    }

    func disarm() { _ = Self.entries.withLock { $0.removeValue(forKey: id) } }

    private static func restoreAll() {
        let snapshot = entries.withLock { entries in
            let snapshot = Array(entries.values)
            entries.removeAll()
            return snapshot
        }
        for entry in snapshot { entry.restore(entry.before, entry.after) }
    }
}
