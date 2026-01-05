import Foundation

/// Top-level terminal UI container that manages rendering and input routing.
@MainActor
public final class TUI: Container {
    /// Terminal implementation used for IO.
    public let terminal: Terminal
    private var previousLines: [String] = []
    private var previousWidth: Int = 0
    private var focusedComponent: Component?

    /// Optional handler for Shift+Ctrl+D debug trigger.
    public var onDebug: (() -> Void)?
    /// Optional handler for global input before focused component handling.
    /// Return true to stop propagation to the focused component.
    public var onGlobalInput: ((String) -> Bool)?
    /// When true, show and position the terminal cursor instead of rendering a custom cursor.
    public var useSystemCursor = true {
        didSet {
            updateCursorMode()
        }
    }

    private var renderRequested = false
    private var cursorRow = 0
    private var lastSystemCursor: CursorPosition?
    private var inputBuffer = ""
    private var cellSizeQueryPending = false

    /// Create a TUI bound to a terminal.
    public init(terminal: Terminal) {
        self.terminal = terminal
        super.init()
    }

    /// Set the component that receives keyboard input.
    public func setFocus(_ component: Component?) {
        if let focusedComponent = focusedComponent as? SystemCursorAware {
            focusedComponent.usesSystemCursor = false
        }
        focusedComponent = component
        if let focusedComponent = focusedComponent as? SystemCursorAware {
            focusedComponent.usesSystemCursor = useSystemCursor
        }
        updateCursorMode()
    }

    /// Start terminal input and initial rendering.
    public func start() {
        terminal.start(onInput: { [weak self] data in
            Task { @MainActor in
                self?.handleTerminalInput(data)
            }
        }, onResize: { [weak self] in
            Task { @MainActor in
                self?.requestRender()
            }
        })
        updateCursorMode()
        queryCellSize()
        requestRender()
    }

    /// Stop terminal input and restore terminal state.
    public func stop() {
        terminal.showCursor()
        terminal.stop()
    }

    /// Request a render, optionally forcing a full redraw.
    public func requestRender(force: Bool = false) {
        if force {
            previousLines = []
            previousWidth = 0
            cursorRow = 0
        }
        if renderRequested { return }
        renderRequested = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.renderRequested = false
            self.doRender()
        }
    }

    private func handleTerminalInput(_ data: String) {
        var input = data

        if cellSizeQueryPending {
            inputBuffer += input
            let filtered = parseCellSizeResponse()
            if filtered.isEmpty { return }
            input = filtered
        }

        if matchesKey(input, Key.shiftCtrl("d")), let onDebug {
            onDebug()
            return
        }

        if let onGlobalInput, onGlobalInput(input) {
            return
        }

        if let focused = focusedComponent {
            let shouldPreserveKillChain = focused is KillBufferAware
                && (matchesKey(input, Key.ctrl("k"))
                    || matchesKey(input, Key.ctrl("w"))
                    || matchesKey(input, Key.alt("backspace"))
                    || matchesKey(input, Key.alt("d")))
            if !shouldPreserveKillChain {
                KillBuffer.shared.breakChain()
            }
            focused.handleInput(input)
            requestRender()
        }
    }

    private func queryCellSize() {
        guard getCapabilities().images != nil else {
            return
        }
        cellSizeQueryPending = true
        terminal.write("\u{001B}[16t")
    }

    private func parseCellSizeResponse() -> String {
        let responsePattern = "\\u{001B}\\[6;(\\d+);(\\d+)t"
        if let match = matchRegex(responsePattern, in: inputBuffer) {
            let heightPx = Int(match[1]) ?? 0
            let widthPx = Int(match[2]) ?? 0

            if heightPx > 0 && widthPx > 0 {
                setCellDimensions(CellDimensions(widthPx: widthPx, heightPx: heightPx))
                invalidate()
                requestRender()
            }

            inputBuffer = inputBuffer.replacingOccurrences(of: match[0], with: "")
            cellSizeQueryPending = false
        }

        if let lastChar = inputBuffer.last {
            let partialPattern = "\\u{001B}(\\[6?;?[\\d;]*)?$"
            if inputBuffer.range(of: partialPattern, options: .regularExpression) != nil {
                if String(lastChar).range(of: "[a-zA-Z~]", options: .regularExpression) == nil {
                    return ""
                }
            }
        }

        let result = inputBuffer
        inputBuffer = ""
        cellSizeQueryPending = false
        return result
    }

    private func containsImage(_ line: String) -> Bool {
        return line.contains("\u{001B}_G") || line.contains("\u{001B}]1337;File=")
    }

    private func doRender() {
        let width = terminal.columns
        let height = terminal.rows

        let rawLines = render(width: width)
        let cursorPosition: CursorPosition?
        let cleanedLines: [String]
        if useSystemCursor {
            let extraction = extractCursorPosition(from: rawLines)
            cleanedLines = extraction.lines
            cursorPosition = extraction.cursor
        } else {
            cleanedLines = rawLines
            cursorPosition = nil
        }
        let newLines = clampLines(cleanedLines, width: width)
        let widthChanged = previousWidth != 0 && previousWidth != width

        if previousLines.isEmpty {
            var buffer = "\u{001B}[?2026h"
            for i in 0..<newLines.count {
                if i > 0 { buffer += "\r\n" }
                buffer += newLines[i]
            }
            buffer += "\u{001B}[?2026l"
            terminal.write(buffer)
            cursorRow = newLines.count - 1
            previousLines = newLines
            previousWidth = width
            positionCursorIfNeeded(cursorPosition, width: width)
            return
        }

        if widthChanged {
            var buffer = "\u{001B}[?2026h"
            buffer += "\u{001B}[3J\u{001B}[2J\u{001B}[H"
            for i in 0..<newLines.count {
                if i > 0 { buffer += "\r\n" }
                buffer += newLines[i]
            }
            buffer += "\u{001B}[?2026l"
            terminal.write(buffer)
            cursorRow = newLines.count - 1
            previousLines = newLines
            previousWidth = width
            positionCursorIfNeeded(cursorPosition, width: width)
            return
        }

        var firstChanged = -1
        let maxLines = max(newLines.count, previousLines.count)
        for i in 0..<maxLines {
            let oldLine = i < previousLines.count ? previousLines[i] : ""
            let newLine = i < newLines.count ? newLines[i] : ""
            if oldLine != newLine, firstChanged == -1 {
                firstChanged = i
            }
        }

        if firstChanged == -1 {
            if useSystemCursor, cursorPosition != lastSystemCursor {
                positionCursorIfNeeded(cursorPosition, width: width)
            }
            return
        }

        let viewportTop = cursorRow - height + 1
        if firstChanged < viewportTop {
            var buffer = "\u{001B}[?2026h"
            buffer += "\u{001B}[3J\u{001B}[2J\u{001B}[H"
            for i in 0..<newLines.count {
                if i > 0 { buffer += "\r\n" }
                buffer += newLines[i]
            }
            buffer += "\u{001B}[?2026l"
            terminal.write(buffer)
            cursorRow = newLines.count - 1
            previousLines = newLines
            previousWidth = width
            positionCursorIfNeeded(cursorPosition, width: width)
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

        for i in firstChanged..<newLines.count {
            if i > firstChanged { buffer += "\r\n" }
            buffer += "\u{001B}[2K"
            buffer += newLines[i]
        }

        if previousLines.count > newLines.count {
            let extraLines = previousLines.count - newLines.count
            for _ in newLines.count..<previousLines.count {
                buffer += "\r\n\u{001B}[2K"
            }
            buffer += "\u{001B}[\(extraLines)A"
        }

        buffer += "\u{001B}[?2026l"
        terminal.write(buffer)
        cursorRow = newLines.count - 1
        previousLines = newLines
        previousWidth = width
        positionCursorIfNeeded(cursorPosition, width: width)
    }

    private func updateCursorMode() {
        let shouldShowSystemCursor = useSystemCursor && focusedComponent is SystemCursorAware
        if shouldShowSystemCursor {
            terminal.showCursor()
        } else {
            terminal.hideCursor()
            lastSystemCursor = nil
        }

        if let focusedComponent = focusedComponent as? SystemCursorAware {
            focusedComponent.usesSystemCursor = useSystemCursor
        }
    }

    private struct CursorPosition: Equatable {
        let row: Int
        let col: Int
    }

    private func extractCursorPosition(from lines: [String]) -> (lines: [String], cursor: CursorPosition?) {
        var cursor: CursorPosition?
        var cleaned: [String] = []
        cleaned.reserveCapacity(lines.count)

        for (row, line) in lines.enumerated() {
            if let range = line.range(of: systemCursorMarker) {
                let prefix = String(line[..<range.lowerBound])
                let col = visibleWidth(prefix)
                if cursor == nil {
                    cursor = CursorPosition(row: row, col: col)
                }
                cleaned.append(line.replacingOccurrences(of: systemCursorMarker, with: ""))
            } else {
                cleaned.append(line)
            }
        }

        return (cleaned, cursor)
    }

    private func positionCursorIfNeeded(_ cursor: CursorPosition?, width: Int) {
        guard useSystemCursor, let cursor else { return }

        let clampedCol = max(0, min(cursor.col, max(0, width - 1)))
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

    private func clampLines(_ lines: [String], width: Int) -> [String] {
        guard width > 0 else { return lines }
        var clamped: [String] = []
        clamped.reserveCapacity(lines.count)

        for line in lines {
            if containsImage(line) || visibleWidth(line) <= width {
                clamped.append(line)
            } else {
                clamped.append(truncateToWidth(line, maxWidth: width, ellipsis: ""))
            }
        }

        return clamped
    }

    private func matchRegex(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        var results: [String] = []
        for index in 0..<match.numberOfRanges {
            let matchRange = match.range(at: index)
            if let swiftRange = Range(matchRange, in: text) {
                results.append(String(text[swiftRange]))
            } else {
                results.append("")
            }
        }
        return results
    }
}
