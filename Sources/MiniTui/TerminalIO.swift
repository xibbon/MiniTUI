import Foundation
import Dispatch
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

/// A terminal system call failure, or the end of terminal input.
public enum TerminalIOError: Error, Sendable, Equatable {
    public enum Operation: Sendable, Equatable {
        case read, write, getAttributes, setAttributes
    }

    case systemCall(operation: Operation, descriptor: Int32, errno: Int32)
    case endOfFile(descriptor: Int32, isTerminalInput: Bool)

    public var operation: Operation {
        switch self {
        case .systemCall(let operation, _, _): operation
        case .endOfFile: .read
        }
    }

    public var descriptor: Int32 {
        switch self {
        case .systemCall(_, let descriptor, _), .endOfFile(let descriptor, _): descriptor
        }
    }

    /// The errno saved immediately after the failed call. EOF has no errno.
    public var errno: Int32? {
        switch self {
        case .systemCall(_, _, let code): code
        case .endOfFile: nil
        }
    }

    public var isTerminalLoss: Bool {
        switch self {
        case .systemCall(_, _, let code):
            code == EIO || code == EPIPE || code == ENOTCONN || code == ENOTTY
        case .endOfFile(_, let isTerminalInput): isTerminalInput
        }
    }
}

/// Internal call seams for descriptor tests. Descriptors remain owned by the caller.
struct TerminalIOCalls: Sendable {
    var read: @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int = { fd, buffer, count in
        #if os(Linux)
        Glibc.read(fd, buffer, count)
        #else
        Darwin.read(fd, buffer, count)
        #endif
    }
    var write: @Sendable (Int32, UnsafeRawPointer, Int) -> Int = { fd, buffer, count in
        #if os(Linux)
        Glibc.write(fd, buffer, count)
        #else
        Darwin.write(fd, buffer, count)
        #endif
    }
    var getAttributes: @Sendable (Int32, UnsafeMutablePointer<termios>) -> Int32 = { tcgetattr($0, $1) }
    var setAttributes: @Sendable (Int32, Int32, UnsafePointer<termios>) -> Int32 = { tcsetattr($0, $1, $2) }
    var flush: @Sendable (Int32, Int32) -> Int32 = { tcflush($0, $1) }
}

/// All I/O state and system calls use this lock. Callbacks run outside the lock.
final class CheckedTerminalIO: Sendable {
    private struct State {
        var handler: (@Sendable (TerminalIOError) -> Void)?
        var lost = false
        var inputStopped = false
        var outputStopped = false
        var readSource: DispatchSourceRead?
        var originalTermios: termios?
        var readAttempts = 0
        var draining = false
        var lastInput = Date()
        var pending: [TerminalIOError] = []
        var delivering = false
        var outputSetupError: Int32?

        mutating func record(_ error: TerminalIOError) {
            guard !lost else { return }
            if error.isTerminalLoss {
                lost = true
                inputStopped = true
                outputStopped = true
                readSource?.cancel()
                readSource = nil
            }
            pending.append(error)
        }
    }

    #if canImport(os)
    private let state: OSAllocatedUnfairLock<State>
    #else
    private let state: Mutex<State>
    #endif
    let inputDescriptor: Int32
    let outputDescriptor: Int32
    private let isTerminalInput: Bool
    private let calls: TerminalIOCalls

    init(inputDescriptor: Int32, outputDescriptor: Int32, calls: TerminalIOCalls) {
        self.inputDescriptor = inputDescriptor
        self.outputDescriptor = outputDescriptor
        self.calls = calls
        isTerminalInput = isatty(inputDescriptor) == 1
        var initial = State()
        #if canImport(Darwin)
        if fcntl(outputDescriptor, F_SETNOSIGPIPE, 1) == -1 {
            let savedErrno = errno
            initial.outputSetupError = savedErrno
        }
        #endif
        #if canImport(os)
        state = OSAllocatedUnfairLock(initialState: initial)
        #else
        state = Mutex(initial)
        #endif
    }

    var isLost: Bool { state.withLock { $0.lost } }
    var acceptsInput: Bool { state.withLock { !$0.inputStopped && !$0.draining } }
    var readAttempts: Int { state.withLock { $0.readAttempts } }

    func setHandler(_ handler: (@Sendable (TerminalIOError) -> Void)?) {
        state.withLock { $0.handler = handler }
    }

    // One caller drains the queue. A callback can call stop or remove itself.
    // Concurrent failures cannot deliver callbacks out of order after the loss event.
    private func deliverErrors() {
        let shouldDeliver = state.withLock { state in
            guard !state.delivering else { return false }
            state.delivering = true
            return true
        }
        guard shouldDeliver else { return }
        while true {
            let next = state.withLock { state -> (TerminalIOError, (@Sendable (TerminalIOError) -> Void)?)? in
                guard !state.pending.isEmpty else {
                    state.delivering = false
                    return nil
                }
                return (state.pending.removeFirst(), state.handler)
            }
            guard let (error, handler) = next else { return }
            handler?(error)
        }
    }

    func startRawMode() {
        state.withLock { state in
            guard !state.lost else { return }
            state.inputStopped = false
            var attributes = termios()
            if calls.getAttributes(inputDescriptor, &attributes) != 0 {
                let savedErrno = errno
                state.record(.systemCall(operation: .getAttributes, descriptor: inputDescriptor, errno: savedErrno))
                return
            }
            state.originalTermios = attributes
            cfmakeraw(&attributes)
            if calls.setAttributes(inputDescriptor, TCSANOW, &attributes) != 0 {
                let savedErrno = errno
                state.record(.systemCall(operation: .setAttributes, descriptor: inputDescriptor, errno: savedErrno))
            }
        }
        deliverErrors()
    }

    func installReadSource(_ source: DispatchSourceRead) {
        state.withLock { state in
            if state.lost || state.inputStopped { source.cancel() }
            else { state.readSource = source }
            source.resume()
        }
    }

    func readReady() -> Data? {
        let data = state.withLock { state -> Data? in
            guard !state.inputStopped else { return nil }
            var buffer = [UInt8](repeating: 0, count: 4096)
            state.readAttempts += 1
            let count = calls.read(inputDescriptor, &buffer, buffer.count)
            let savedErrno = errno
            if count > 0 {
                state.lastInput = Date()
                return state.draining ? nil : Data(buffer[0..<count])
            }
            if count < 0 && (savedErrno == EINTR || savedErrno == EAGAIN || savedErrno == EWOULDBLOCK) {
                return nil
            }
            state.inputStopped = true
            state.readSource?.cancel()
            state.readSource = nil
            state.record(count == 0
                ? .endOfFile(descriptor: inputDescriptor, isTerminalInput: isTerminalInput)
                : .systemCall(operation: .read, descriptor: inputDescriptor, errno: savedErrno))
            return nil
        }
        deliverErrors()
        return data
    }

    /// Return true only when all bytes were written.
    func write(_ data: Data) -> Bool {
        let written = state.withLock { state -> Bool in
            guard !state.outputStopped else { return false }
            if let code = state.outputSetupError {
                state.outputSetupError = nil
                state.outputStopped = true
                state.record(.systemCall(operation: .write, descriptor: outputDescriptor, errno: code))
                return false
            }
            return data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return true }
                var offset = 0
                while offset < bytes.count {
                    let count = calls.write(outputDescriptor, base.advanced(by: offset), bytes.count - offset)
                    let savedErrno = errno
                    if count > 0 { offset += count; continue }
                    if count < 0 && savedErrno == EINTR { continue }
                    state.outputStopped = true
                    // A zero-byte write cannot advance the loop. Treat it as EIO.
                    state.record(.systemCall(operation: .write, descriptor: outputDescriptor, errno: count == 0 ? EIO : savedErrno))
                    return false
                }
                return true
            }
        }
        deliverErrors()
        return written
    }

    func stop() {
        state.withLock { state in
            state.inputStopped = true
            state.readSource?.cancel()
            state.readSource = nil
            guard !state.lost else { state.originalTermios = nil; return }
            _ = calls.flush(inputDescriptor, TCIFLUSH)
            if var attributes = state.originalTermios {
                state.originalTermios = nil
                if calls.setAttributes(inputDescriptor, TCSANOW, &attributes) != 0 {
                    let savedErrno = errno
                    state.record(.systemCall(operation: .setAttributes, descriptor: inputDescriptor, errno: savedErrno))
                }
            }
        }
        deliverErrors()
    }

    func beginDrain() -> Bool {
        state.withLock { state in
            guard !state.lost && !state.inputStopped else { return false }
            state.draining = true
            state.lastInput = Date()
            return true
        }
    }

    var lastInput: Date { state.withLock { $0.lastInput } }
    func endDrain() { state.withLock { $0.draining = false } }
}
