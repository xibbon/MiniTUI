import Foundation

public struct OverlayOptions: Sendable {
    public var row: Int?
    public var col: Int?
    public var width: Int?

    public init(row: Int? = nil, col: Int? = nil, width: Int? = nil) {
        self.row = row
        self.col = col
        self.width = width
    }
}

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
    private var overlayStack: [OverlayEntry] = []

    private struct OverlayEntry {
        let component: Component
        let options: OverlayOptions?
        let preFocus: Component?
    }

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

    /// Show an overlay component centered (or at specified position).
    public func showOverlay(_ component: Component, options: OverlayOptions? = nil) {
        overlayStack.append(OverlayEntry(component: component, options: options, preFocus: focusedComponent))
        setFocus(component)
        requestRender()
    }

    /// Hide the topmost overlay and restore previous focus.
    public func hideOverlay() {
        guard let overlay = overlayStack.popLast() else { return }
        setFocus(overlay.preFocus)
        requestRender()
    }

    public func hasOverlay() -> Bool {
        return !overlayStack.isEmpty
    }

    public override func invalidate() {
        super.invalidate()
        for overlay in overlayStack {
            overlay.component.invalidate()
        }
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
            if isKeyRelease(input), !focused.wantsKeyRelease {
                return
            }
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

    private static let segmentReset = "\u{001B}[0m\u{001B}]8;;\u{0007}"

    private func compositeOverlays(_ lines: [String], termWidth: Int, termHeight: Int) -> [String] {
        if overlayStack.isEmpty { return lines }
        var result = lines
        let viewportStart = max(0, result.count - termHeight)

        for overlay in overlayStack {
            let requestedWidth = overlay.options?.width ?? 80
            let maxWidth = max(1, min(requestedWidth, termWidth - 4))
            let overlayLines = overlay.component.render(width: maxWidth)
            let height = overlayLines.count

            let row = max(0, min(overlay.options?.row ?? (termHeight - height) / 2, termHeight - height))
            let col = max(0, min(overlay.options?.col ?? (termWidth - maxWidth) / 2, termWidth - maxWidth))

            for i in 0..<height {
                let idx = viewportStart + row + i
                if idx >= 0 && idx < result.count {
                    result[idx] = compositeLineAt(
                        baseLine: result[idx],
                        overlayLine: overlayLines[i],
                        startCol: col,
                        overlayWidth: maxWidth,
                        totalWidth: termWidth
                    )
                }
            }
        }

        return result
    }

    private func compositeLineAt(
        baseLine: String,
        overlayLine: String,
        startCol: Int,
        overlayWidth: Int,
        totalWidth: Int
    ) -> String {
        if containsImage(baseLine) { return baseLine }

        let afterStart = startCol + overlayWidth
        let base = extractSegments(
            baseLine,
            beforeEnd: startCol,
            afterStart: afterStart,
            afterLen: max(0, totalWidth - afterStart),
            strictAfter: true
        )

        let overlay = sliceWithWidth(overlayLine, startCol: 0, length: overlayWidth)

        let beforePad = max(0, startCol - base.beforeWidth)
        let overlayPad = max(0, overlayWidth - overlay.width)
        let actualBeforeWidth = max(startCol, base.beforeWidth)
        let actualOverlayWidth = max(overlayWidth, overlay.width)
        let afterTarget = max(0, totalWidth - actualBeforeWidth - actualOverlayWidth)
        let afterPad = max(0, afterTarget - base.afterWidth)

        let r = TUI.segmentReset
        let result = base.before
            + String(repeating: " ", count: beforePad)
            + r
            + overlay.text
            + String(repeating: " ", count: overlayPad)
            + r
            + base.after
            + String(repeating: " ", count: afterPad)

        let resultWidth = actualBeforeWidth + actualOverlayWidth + max(afterTarget, base.afterWidth)
        if resultWidth <= totalWidth {
            return result
        }

        return sliceByColumn(result, startCol: 0, length: totalWidth, strict: true)
    }

    private func doRender() {
        let width = terminal.columns
        let height = terminal.rows

        var renderedLines = render(width: width)
        if !overlayStack.isEmpty {
            renderedLines = compositeOverlays(renderedLines, termWidth: width, termHeight: height)
        }
        let cursorPosition: CursorPosition?
        let cleanedLines: [String]
        if useSystemCursor {
            let extraction = extractCursorPosition(from: renderedLines)
            cleanedLines = extraction.lines
            cursorPosition = extraction.cursor
        } else {
            cleanedLines = renderedLines
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
        let overlayActive = !overlayStack.isEmpty
        let shouldShowSystemCursor = !overlayActive && useSystemCursor && focusedComponent is SystemCursorAware
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
        guard useSystemCursor, overlayStack.isEmpty, let cursor else { return }

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
