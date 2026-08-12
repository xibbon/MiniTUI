import Foundation

/// Differential renderer for the terminal main screen and scrollback.
@MainActor
public final class MainScreenRenderer: TuiRenderer {
    public let mode = TuiMode.mainScreen

    private let terminal: Terminal
    private var onRenderFailure: () -> Void
    private var previousLines: [String] = []
    private var previousResetSource: [String] = []
    private var previousWidth = 0
    private var previousHeight = 0
    private var cursorRow = 0
    private var lastSystemCursor: CursorPosition?
    private var maxLinesRendered = 0
    private var fullRedrawCount = 0

    /// Create a main-screen renderer for a terminal.
    public init(terminal: Terminal) {
        self.terminal = terminal
        self.onRenderFailure = {}
    }

    func setRenderFailureHandler(_ handler: @escaping () -> Void) {
        onRenderFailure = handler
    }

    public func start() {}

    public func stop(preserveScreen: Bool = false) {
        guard !preserveScreen, !previousLines.isEmpty else { return }

        let targetRow = previousLines.count
        let lineDiff = targetRow - cursorRow
        if lineDiff > 0 {
            terminal.write("\u{001B}[\(lineDiff)B")
        } else if lineDiff < 0 {
            terminal.write("\u{001B}[\(-lineDiff)A")
        }
        terminal.write("\r\n")
    }

    public func invalidateRenderState() {
        previousLines = []
        previousWidth = -1
        previousHeight = -1
        cursorRow = 0
    }

    public func invalidateCursorState() {
        lastSystemCursor = nil
    }

    public func clearRenderState() {
        previousLines = []
        previousResetSource = []
        previousWidth = 0
        previousHeight = 0
        cursorRow = 0
        lastSystemCursor = nil
        maxLinesRendered = 0
    }

    public func takeOverRenderState(from previous: any TuiRenderer) {
        guard let previous = previous as? MainScreenRenderer, previous !== self else { return }

        previousLines = previous.previousLines
        previousResetSource = previous.previousResetSource
        previousWidth = previous.previousWidth
        previousHeight = previous.previousHeight
        cursorRow = previous.cursorRow
        lastSystemCursor = previous.lastSystemCursor
        maxLinesRendered = previous.maxLinesRendered
    }

    public func present(_ frame: TuiRenderFrame) {
        let normalizedLines = frame.lines.map(normalizeTerminalOutput)
        let newLines = applyLineResets(
            normalizedLines,
            previousSource: previousResetSource,
            previousLines: previousLines
        )
        let widthChanged = previousWidth != 0 && previousWidth != frame.width
        let heightChanged = previousHeight != 0 && previousHeight != frame.height

        let debugRedraw = ProcessInfo.processInfo.environment["PI_DEBUG_REDRAW"] == "1"
        func logRedraw(_ reason: String) {
            guard debugRedraw else { return }
            let logPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".pi/agent/pi-debug.log")
            let formatter = ISO8601DateFormatter()
            let message = "[\(formatter.string(from: Date()))] fullRender: \(reason) (prev=\(previousLines.count), new=\(newLines.count), height=\(frame.height))\n"
            do {
                try FileManager.default.createDirectory(
                    at: logPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let handle = try FileHandle(forWritingTo: logPath)
                handle.seekToEndOfFile()
                if let data = message.data(using: .utf8) {
                    handle.write(data)
                }
                try handle.close()
            } catch {
                // Best-effort logging only.
            }
        }

        func fullRender(clear: Bool, reason: String) {
            logRedraw(reason)
            fullRedrawCount += 1
            var buffer = "\u{001B}[?2026h"
            if clear {
                buffer += "\u{001B}[2J\u{001B}[H\u{001B}[3J"
            }
            for i in 0..<newLines.count {
                if i > 0 { buffer += "\r\n" }
                buffer += newLines[i]
            }
            buffer += "\u{001B}[?2026l"
            terminal.write(buffer)
            cursorRow = max(0, newLines.count - 1)
            if clear {
                maxLinesRendered = newLines.count
            } else {
                maxLinesRendered = max(maxLinesRendered, newLines.count)
            }
            previousLines = newLines
            previousResetSource = normalizedLines
            previousWidth = frame.width
            previousHeight = frame.height
            positionCursorIfNeeded(frame.cursor, frame: frame)
        }

        if previousLines.isEmpty && !widthChanged {
            fullRender(clear: false, reason: "first render")
            return
        }

        if widthChanged {
            fullRender(clear: true, reason: "width changed (\(previousWidth) -> \(frame.width))")
            return
        }

        // Height changes normally need a full re-render to keep the visible viewport aligned,
        // but Termux changes height when the software keyboard shows or hides.
        // In that environment, a full redraw causes the entire history to replay on every toggle.
        if heightChanged && !MainScreenRenderer.isTermuxSession() {
            fullRender(clear: true, reason: "terminal height changed (\(previousHeight) -> \(frame.height))")
            return
        }

        if frame.clearOnShrink && newLines.count < maxLinesRendered && !frame.hasOverlayEntries {
            fullRender(clear: true, reason: "clearOnShrink (maxLinesRendered=\(maxLinesRendered))")
            return
        }

        var firstChanged = -1
        var lastChanged = -1
        let maxLines = max(newLines.count, previousLines.count)
        for i in 0..<maxLines {
            let oldLine = i < previousLines.count ? previousLines[i] : ""
            let newLine = i < newLines.count ? newLines[i] : ""
            if oldLine != newLine {
                if firstChanged == -1 {
                    firstChanged = i
                }
                lastChanged = i
            }
        }

        if firstChanged == -1 {
            if frame.useSystemCursor, frame.cursor != lastSystemCursor {
                positionCursorIfNeeded(frame.cursor, frame: frame)
            }
            previousResetSource = normalizedLines
            previousHeight = frame.height
            maxLinesRendered = max(maxLinesRendered, newLines.count)
            return
        }

        if firstChanged >= newLines.count {
            if previousLines.count > newLines.count {
                var buffer = "\u{001B}[?2026h"
                let targetRow = max(0, newLines.count - 1)
                let lineDiff = targetRow - cursorRow
                if lineDiff > 0 {
                    buffer += "\u{001B}[\(lineDiff)B"
                } else if lineDiff < 0 {
                    buffer += "\u{001B}[\(-lineDiff)A"
                }
                buffer += "\r"
                let extraLines = previousLines.count - newLines.count
                for _ in 0..<extraLines {
                    buffer += "\r\n\u{001B}[2K"
                }
                buffer += "\u{001B}[\(extraLines)A"
                buffer += "\u{001B}[?2026l"
                terminal.write(buffer)
                cursorRow = targetRow
            }
            previousLines = newLines
            previousResetSource = normalizedLines
            previousWidth = frame.width
            previousHeight = frame.height
            maxLinesRendered = max(maxLinesRendered, newLines.count)
            positionCursorIfNeeded(frame.cursor, frame: frame)
            return
        }

        let viewportTop = cursorRow - frame.height + 1
        if firstChanged < viewportTop {
            fullRender(clear: true, reason: "firstChanged < viewportTop (\(firstChanged) < \(viewportTop))")
            return
        }

        var buffer = "\u{001B}[?2026h"
        let lineDiff = firstChanged - cursorRow
        if lineDiff > 0 {
            buffer += "\u{001B}[\(lineDiff)B"
        } else if lineDiff < 0 {
            buffer += "\u{001B}[\(-lineDiff)A"
        }
        buffer += "\r"

        let renderEnd = min(lastChanged, newLines.count - 1)
        if renderEnd >= firstChanged {
            for i in firstChanged...renderEnd {
                if i > firstChanged { buffer += "\r\n" }
                buffer += "\u{001B}[2K"
                let line = newLines[i]
                if !isImageLine(line), visibleWidth(line) > frame.width {
                    reportOverlongLine(line, index: i, lines: newLines, frame: frame)
                }
                buffer += line
            }
        }

        var finalCursorRow = renderEnd

        if previousLines.count > newLines.count {
            if renderEnd < newLines.count - 1 {
                let moveDown = newLines.count - 1 - renderEnd
                buffer += "\u{001B}[\(moveDown)B"
                finalCursorRow = newLines.count - 1
            }
            let extraLines = previousLines.count - newLines.count
            for _ in newLines.count..<previousLines.count {
                buffer += "\r\n\u{001B}[2K"
            }
            buffer += "\u{001B}[\(extraLines)A"
        }

        buffer += "\u{001B}[?2026l"
        terminal.write(buffer)
        cursorRow = finalCursorRow
        previousLines = newLines
        previousResetSource = normalizedLines
        previousWidth = frame.width
        previousHeight = frame.height
        maxLinesRendered = max(maxLinesRendered, newLines.count)
        positionCursorIfNeeded(frame.cursor, frame: frame)
    }

    private func applyLineResets(
        _ lines: [String],
        previousSource: [String],
        previousLines: [String]
    ) -> [String] {
        let reset = "\u{001B}[0m" + osc8HyperlinkCloseBell
        var result = lines
        let canReuse = !previousSource.isEmpty && previousSource.count == previousLines.count
        for index in result.indices {
            let line = result[index]
            if canReuse, index < previousSource.count, previousSource[index] == line, index < previousLines.count {
                result[index] = previousLines[index]
                continue
            }
            if !isImageLine(line) {
                result[index] = line + reset
            }
        }
        return result
    }

    private func positionCursorIfNeeded(_ cursor: CursorPosition?, frame: TuiRenderFrame) {
        guard frame.useSystemCursor, !frame.hasVisibleOverlay, let cursor else { return }

        let clampedCol = max(0, min(cursor.col, max(0, frame.width - 1)))
        var buffer = ""
        let lineDiff = cursor.row - cursorRow
        if lineDiff > 0 {
            buffer += "\u{001B}[\(lineDiff)B"
        } else if lineDiff < 0 {
            buffer += "\u{001B}[\(-lineDiff)A"
        }
        buffer += "\r"
        buffer += "\u{001B}[\(clampedCol + 1)G"

        terminal.write(buffer)
        cursorRow = cursor.row
        lastSystemCursor = cursor
    }

    private func reportOverlongLine(
        _ line: String,
        index: Int,
        lines: [String],
        frame: TuiRenderFrame
    ) -> Never {
        let origin = frame.lineOrigins.flatMap { index < $0.count ? $0[index] : nil }
        let crashLogPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/pi-crash.log")
        let formatter = ISO8601DateFormatter()
        var crashLines = [
            "Crash at \(formatter.string(from: Date()))",
            "Terminal width: \(frame.width)",
            "Line \(index) visible width: \(visibleWidth(line))",
        ]
        if let origin {
            crashLines.append("Origin: \(origin)")
        }
        crashLines.append("")
        crashLines.append("=== All rendered lines ===")
        crashLines.append(contentsOf: lines.enumerated().map { lineIndex, value in
            if let origins = frame.lineOrigins, lineIndex < origins.count {
                return "[\(lineIndex)] (w=\(visibleWidth(value))) [\(origins[lineIndex])] \(value)"
            }
            return "[\(lineIndex)] (w=\(visibleWidth(value))) \(value)"
        })
        crashLines.append("")
        let crashData = crashLines.joined(separator: "\n")
        do {
            try FileManager.default.createDirectory(
                at: crashLogPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try crashData.write(to: crashLogPath, atomically: true, encoding: .utf8)
        } catch {
            // Best-effort logging, continue to crash.
        }

        onRenderFailure()

        var errorLines = [
            "Rendered line \(index) exceeds terminal width (\(visibleWidth(line)) > \(frame.width)).",
        ]
        if let origin {
            errorLines.append("Origin: \(origin)")
        }
        errorLines.append("")
        errorLines.append("This is likely caused by a custom TUI component not truncating its output.")
        errorLines.append("Use visibleWidth() to measure and truncateToWidth() to truncate lines.")
        errorLines.append("")
        errorLines.append("Debug log written to: \(crashLogPath.path)")
        let errorMessage = errorLines.joined(separator: "\n")
        // Internal component contract violation: renderers must not emit lines wider
        // than the terminal. Crash after writing a debug log.
        fatalError(errorMessage)
    }

    private static func isTermuxSession() -> Bool {
        ProcessInfo.processInfo.environment["TERMUX_VERSION"] != nil
    }
}
