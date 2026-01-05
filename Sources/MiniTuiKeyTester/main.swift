import Darwin
import Foundation
import MiniTui

private final class KeyLogger: Component {
    private var log: [String] = []
    private let maxLines = 20
    private let terminal: Terminal

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    func handleInput(_ data: String) {
        if matchesKey(data, Key.ctrl("c")) {
            terminal.showCursor()
            terminal.stop()
            print("\nExiting...")
            Darwin.exit(0)
        }

        let hex = data.utf8.map { String(format: "%02x", $0) }.joined()
        let charCodes = data.unicodeScalars.map { String($0.value) }.joined(separator: ", ")
        var repr = data
        repr = repr.replacingOccurrences(of: "\u{001B}", with: "\\x1b")
        repr = repr.replacingOccurrences(of: "\r", with: "\\r")
        repr = repr.replacingOccurrences(of: "\n", with: "\\n")
        repr = repr.replacingOccurrences(of: "\t", with: "\\t")
        repr = repr.replacingOccurrences(of: "\u{007F}", with: "\\x7f")

        let logLine = "Hex: \(padRight(hex, to: 20)) | Chars: [\(padRight(charCodes, to: 15))] | Repr: \"\(repr)\""
        log.append(logLine)
        if log.count > maxLines {
            log.removeFirst()
        }

    }

    func render(width: Int) -> [String] {
        var lines: [String] = []

        lines.append(String(repeating: "=", count: width))
        lines.append(padLine("Key Code Tester - Press keys to see their codes (Ctrl+C to exit)", width: width))
        lines.append(String(repeating: "=", count: width))
        lines.append(padLine("", width: width))

        for entry in log {
            lines.append(padLine(entry, width: width))
        }

        let remaining = max(0, 25 - lines.count)
        if remaining > 0 {
            for _ in 0..<remaining {
                lines.append(String(repeating: " ", count: width))
            }
        }

        lines.append(String(repeating: "=", count: width))
        lines.append(padLine("Test these:", width: width))
        lines.append(padLine("  - Shift + Enter (should show: \\x1b[13;2u with Kitty protocol)", width: width))
        lines.append(padLine("  - Alt/Option + Enter", width: width))
        lines.append(padLine("  - Option/Alt + Backspace", width: width))
        lines.append(padLine("  - Cmd/Ctrl + Backspace", width: width))
        lines.append(padLine("  - Regular Backspace", width: width))
        lines.append(String(repeating: "=", count: width))

        return lines
    }
}

@main
struct MiniTuiKeyTester {
    @MainActor
    static func main() {
        let terminal = ProcessTerminal()
        let tui = TUI(terminal: terminal)
        let logger = KeyLogger(terminal: terminal)

        tui.addChild(logger)
        tui.setFocus(logger)
        tui.start()

        RunLoop.main.run()
    }
}

private func padRight(_ value: String, to length: Int) -> String {
    guard value.count < length else { return value }
    return value + String(repeating: " ", count: length - value.count)
}

private func padLine(_ text: String, width: Int) -> String {
    let truncated = truncateToWidth(text, maxWidth: width)
    let padding = max(0, width - visibleWidth(truncated))
    return truncated + String(repeating: " ", count: padding)
}
