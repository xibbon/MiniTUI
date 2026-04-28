import Foundation
import Dispatch

#if os(Linux)
import Glibc
#else
import Darwin
#endif

#if os(Windows)
import WinSDK
#endif

/// Minimal terminal interface used by the TUI renderer.
public protocol Terminal: AnyObject {
    /// Start the terminal and provide input/resize handlers.
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void)
    /// Stop the terminal and restore any modified state.
    func stop()
    /// Drain stdin before exiting to prevent Kitty key release events leaking to the parent shell.
    func drainInput(maxMs: Int, idleMs: Int)
    /// Write raw data to the terminal output.
    func write(_ data: String)
    /// Current terminal column count.
    var columns: Int { get }
    /// Current terminal row count.
    var rows: Int { get }
    /// Return true when Kitty keyboard protocol is active.
    var kittyProtocolActive: Bool { get }
    /// Move the cursor by a number of lines.
    func moveBy(lines: Int)
    /// Hide the terminal cursor.
    func hideCursor()
    /// Show the terminal cursor.
    func showCursor()
    /// Clear from cursor to end of line.
    func clearLine()
    /// Clear from cursor to end of screen.
    func clearFromCursor()
    /// Clear the full screen and move cursor to home.
    func clearScreen()
    /// Set the terminal window title.
    func setTitle(_ title: String)
    /// v0.69.0: turn the OSC 9;4 progress indicator on or off (e.g., iTerm2 / WezTerm /
    /// Windows Terminal / Kitty tab-bar activity indicators). Implementations that don't
    /// support OSC 9;4 should treat this as a no-op.
    func setProgress(_ active: Bool)
}

public extension Terminal {
    /// Default no-op so existing Terminal implementations don't break when callers invoke
    /// `setProgress`. Production terminals override.
    func setProgress(_ active: Bool) {}
}

/// Terminal backed by stdin/stdout with raw mode enabled.
public final class ProcessTerminal: Terminal {
    private var inputHandler: ((String) -> Void)?
    private var resizeHandler: (() -> Void)?
    private var readSource: DispatchSourceRead?
    private var resizeSource: DispatchSourceSignal?
    private var originalTermios = termios()
    private var hasOriginalTermios = false
    private var kittyProtocolActiveFlag = false
    private var kittyQueryResolved = false
    private var kittyQueryBuffer = ""
    private var kittyQueryWorkItem: DispatchWorkItem?
    private var stdinBuffer: StdinBuffer?

    /// Create a new process-backed terminal.
    public init() {}

    public var kittyProtocolActive: Bool {
        return kittyProtocolActiveFlag
    }

    /// Start raw input and hook resize notifications.
    public func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        inputHandler = onInput
        resizeHandler = onResize
        kittyProtocolActiveFlag = false
        setKittyProtocolActive(false)

        if tcgetattr(STDIN_FILENO, &originalTermios) == 0 {
            hasOriginalTermios = true
            var raw = originalTermios
            #if os(Linux)
            cfmakeraw(&raw)
            #else
            cfmakeraw(&raw)
            #endif
            tcsetattr(STDIN_FILENO, TCSANOW, &raw)
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: DispatchQueue.global())
        readSource.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            if count > 0 {
                let data = Data(buffer[0..<count])
                self.handleStdinData(data)
            }
        }
        readSource.resume()
        self.readSource = readSource

        signal(SIGWINCH, SIG_IGN)
        let resizeSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: DispatchQueue.global())
        resizeSource.setEventHandler { [weak self] in
            self?.resizeHandler?()
        }
        resizeSource.resume()
        self.resizeSource = resizeSource

        #if !os(Windows)
        kill(getpid(), SIGWINCH)
        #endif

        // On Windows, raw mode can reset console flags. Re-enable VT input so
        // modified keys (e.g. Shift+Tab) are emitted as escape sequences.
        enableWindowsVTInput()

        write("\u{001B}[?2004h")
        setupStdinBuffer()
        queryAndEnableKittyProtocol()
    }

    /// Stop raw input and restore the previous terminal state.
    public func stop() {
        write("\u{001B}[?2004l")
        if kittyProtocolActiveFlag {
            write("\u{001B}[<u")
            kittyProtocolActiveFlag = false
            setKittyProtocolActive(false)
        }

        kittyQueryWorkItem?.cancel()
        kittyQueryWorkItem = nil
        kittyQueryResolved = false
        kittyQueryBuffer = ""
        stdinBuffer?.destroy()
        stdinBuffer = nil

        readSource?.cancel()
        readSource = nil
        resizeSource?.cancel()
        resizeSource = nil
        inputHandler = nil
        resizeHandler = nil

        // Flush any pending stdin data before leaving raw mode.
        tcflush(STDIN_FILENO, TCIFLUSH)

        if hasOriginalTermios {
            var termios = originalTermios
            tcsetattr(STDIN_FILENO, TCSANOW, &termios)
            hasOriginalTermios = false
        }
    }

    public func drainInput(maxMs: Int = 1000, idleMs: Int = 50) {
        if kittyProtocolActiveFlag {
            write("\u{001B}[<u")
            kittyProtocolActiveFlag = false
            setKittyProtocolActive(false)
        }

        let previousHandler = inputHandler
        inputHandler = nil
        let previousOnData = stdinBuffer?.onData
        let previousOnPaste = stdinBuffer?.onPaste

        var lastDataTime = Date()
        stdinBuffer?.onData = { _ in
            lastDataTime = Date()
        }
        stdinBuffer?.onPaste = { _ in
            lastDataTime = Date()
        }

        let endTime = Date().addingTimeInterval(Double(maxMs) / 1000.0)
        while Date() < endTime {
            let idleElapsed = Date().timeIntervalSince(lastDataTime) * 1000.0
            if idleElapsed >= Double(idleMs) { break }
            let remaining = endTime.timeIntervalSinceNow
            if remaining <= 0 { break }
            Thread.sleep(forTimeInterval: min(Double(idleMs) / 1000.0, remaining))
        }

        stdinBuffer?.onData = previousOnData
        stdinBuffer?.onPaste = previousOnPaste
        inputHandler = previousHandler
    }

    private func setupStdinBuffer() {
        let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
        buffer.onData = { [weak self] sequence in
            self?.inputHandler?(sequence)
        }
        buffer.onPaste = { [weak self] content in
            self?.inputHandler?("\u{001B}[200~" + content + "\u{001B}[201~")
        }
        stdinBuffer = buffer
    }

    private func queryAndEnableKittyProtocol() {
        kittyQueryResolved = false
        kittyQueryBuffer = ""

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.kittyQueryResolved else { return }
            self.kittyQueryResolved = true
            self.kittyProtocolActiveFlag = false
            setKittyProtocolActive(false)

            if !self.kittyQueryBuffer.isEmpty {
                self.stdinBuffer?.process(self.kittyQueryBuffer)
                self.kittyQueryBuffer = ""
            }
            self.kittyQueryWorkItem = nil
        }
        kittyQueryWorkItem?.cancel()
        kittyQueryWorkItem = workItem
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1, execute: workItem)

        write("\u{001B}[?u")
    }

    private func enableWindowsVTInput() {
        #if os(Windows)
        let stdInputHandle: DWORD = DWORD(bitPattern: Int32(-10))
        let enableVirtualTerminalInput: DWORD = 0x0200
        let handle = GetStdHandle(stdInputHandle)
        guard handle != INVALID_HANDLE_VALUE else { return }
        var mode: DWORD = 0
        guard GetConsoleMode(handle, &mode) != 0 else { return }
        _ = SetConsoleMode(handle, mode | enableVirtualTerminalInput)
        #endif
    }

    private func handleStdinData(_ data: Data) {
        guard !kittyQueryResolved else {
            stdinBuffer?.process(data)
            return
        }

        let text = String(decoding: data, as: UTF8.self)
        kittyQueryBuffer += text

        if let range = kittyResponseRange(in: kittyQueryBuffer) {
            kittyQueryResolved = true
            kittyProtocolActiveFlag = true
            setKittyProtocolActive(true)
            write("\u{001B}[>3u")

            kittyQueryBuffer.removeSubrange(range)
            let remaining = kittyQueryBuffer
            kittyQueryBuffer = ""

            kittyQueryWorkItem?.cancel()
            kittyQueryWorkItem = nil

            if !remaining.isEmpty {
                stdinBuffer?.process(remaining)
            }
        }
    }

    private func kittyResponseRange(in text: String) -> Range<String.Index>? {
        let pattern = "\\u{001B}\\[\\?(\\d+)u"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return Range(match.range(at: 0), in: text)
    }

    /// Write UTF-8 data to stdout.
    public func write(_ data: String) {
        if let output = data.data(using: .utf8) {
            FileHandle.standardOutput.write(output)
        }
    }

    /// Current terminal column count.
    public var columns: Int {
        return terminalSize().columns
    }

    /// Current terminal row count.
    public var rows: Int {
        return terminalSize().rows
    }

    /// Move the cursor by a number of lines.
    public func moveBy(lines: Int) {
        if lines > 0 {
            write("\u{001B}[\(lines)B")
        } else if lines < 0 {
            write("\u{001B}[\(-lines)A")
        }
    }

    /// Hide the terminal cursor.
    public func hideCursor() {
        write("\u{001B}[?25l")
    }

    /// Show the terminal cursor.
    public func showCursor() {
        write("\u{001B}[?25h")
    }

    /// Clear from cursor to end of line.
    public func clearLine() {
        write("\u{001B}[K")
    }

    /// Clear from cursor to end of screen.
    public func clearFromCursor() {
        write("\u{001B}[J")
    }

    /// Clear the full screen and move cursor to home.
    public func clearScreen() {
        write("\u{001B}[2J\u{001B}[H")
    }

    /// Set the terminal window title.
    public func setTitle(_ title: String) {
        write("\u{001B}]0;\(title)\u{0007}")
    }

    /// v0.69.0: emit OSC 9;4 to toggle terminal progress indicator.
    /// State 1 = "indeterminate" (active), state 0 = "remove" (inactive).
    /// Supported by iTerm2, WezTerm, Windows Terminal, Kitty (and Ghostty after v0.70.0
    /// keep-alive workaround). Other terminals ignore.
    public func setProgress(_ active: Bool) {
        if active {
            write("\u{001B}]9;4;1\u{001B}\\")
        } else {
            write("\u{001B}]9;4;0\u{001B}\\")
        }
    }

    private func terminalSize() -> (columns: Int, rows: Int) {
        var size = winsize()
        if ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 {
            let columns = Int(size.ws_col)
            let rows = Int(size.ws_row)
            if columns > 0, rows > 0 {
                return (columns: columns, rows: rows)
            }
        }
        return (columns: 80, rows: 24)
    }
}
