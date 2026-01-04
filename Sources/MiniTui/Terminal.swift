import Foundation
import Dispatch

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Minimal terminal interface used by the TUI renderer.
public protocol Terminal: AnyObject {
    /// Start the terminal and provide input/resize handlers.
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void)
    /// Stop the terminal and restore any modified state.
    func stop()
    /// Write raw data to the terminal output.
    func write(_ data: String)
    /// Current terminal column count.
    var columns: Int { get }
    /// Current terminal row count.
    var rows: Int { get }
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
}

/// Terminal backed by stdin/stdout with raw mode enabled.
public final class ProcessTerminal: Terminal {
    private var inputHandler: ((String) -> Void)?
    private var resizeHandler: (() -> Void)?
    private var readSource: DispatchSourceRead?
    private var resizeSource: DispatchSourceSignal?
    private var originalTermios = termios()
    private var hasOriginalTermios = false

    /// Create a new process-backed terminal.
    public init() {}

    /// Start raw input and hook resize notifications.
    public func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        inputHandler = onInput
        resizeHandler = onResize

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
                let text = String(decoding: data, as: UTF8.self)
                self.inputHandler?(text)
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

        write("\u{001B}[?2004h")
        write("\u{001B}[>1u")
    }

    /// Stop raw input and restore the previous terminal state.
    public func stop() {
        write("\u{001B}[?2004l")
        write("\u{001B}[<u")

        readSource?.cancel()
        readSource = nil
        resizeSource?.cancel()
        resizeSource = nil
        inputHandler = nil
        resizeHandler = nil

        if hasOriginalTermios {
            var termios = originalTermios
            tcsetattr(STDIN_FILENO, TCSANOW, &termios)
            hasOriginalTermios = false
        }
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
