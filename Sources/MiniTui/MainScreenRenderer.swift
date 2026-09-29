import Foundation

private struct KittyImageHeader {
    let ids: [UInt32]
    let rows: Int
}

private func parseKittyImageHeader(_ line: String) -> KittyImageHeader? {
    guard let sequence = line.range(of: "\u{001B}_G"),
          let controlsEnd = line[sequence.upperBound...].firstIndex(of: ";") else {
        return nil
    }
    let controls = line[sequence.upperBound..<controlsEnd].split(separator: ",")
    var ids: [UInt32] = []
    var rows = 1
    for control in controls {
        let pair = control.split(separator: "=", maxSplits: 1)
        guard pair.count == 2, let value = UInt32(pair[1]), value > 0 else { continue }
        if pair[0] == "i" { ids.append(value) }
        if pair[0] == "r" { rows = Int(value) }
    }
    return KittyImageHeader(ids: ids, rows: rows)
}

/// Differential renderer for the terminal main screen and scrollback.
@MainActor
public final class MainScreenRenderer: TuiRenderer {
    public let mode = TuiMode.mainScreen

    private let terminal: Terminal
    private let logDirectory: String?
    private var onRenderFailure: () -> Void
    private var previousLines: [String] = []
    private var previousKittyImageIds: [UInt32] = []
    private var previousResetSource: [String] = []
    private var previousWidth = 0
    private var previousHeight = 0
    private var cursorRow = 0
    private var hardwareCursorRow = 0
    private var previousViewportTop = 0
    private var lastSystemCursor: CursorPosition?
    private var maxLinesRendered = 0
    private var fullRedrawCount = 0

    /// Create a main-screen renderer for a terminal.
    public init(terminal: Terminal, logDirectory: String? = nil) {
        self.logDirectory = logDirectory
        self.terminal = terminal
        self.onRenderFailure = {}
    }

    var crashLogURL: URL {
        let directory = logDirectory.map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("pi-tui-crash.log")
    }

    func setRenderFailureHandler(_ handler: @escaping () -> Void) {
        onRenderFailure = handler
    }

    public func start() {}

    public func stop(preserveScreen: Bool = false) {
        guard !preserveScreen, !previousLines.isEmpty else { return }

        let targetRow = previousLines.count
        let lineDiff = targetRow - hardwareCursorRow
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
        hardwareCursorRow = 0
        previousViewportTop = 0
    }

    public func invalidateCursorState() {
        lastSystemCursor = nil
    }

    public func clearRenderState() {
        previousLines = []
        previousKittyImageIds = []
        previousResetSource = []
        previousWidth = 0
        previousHeight = 0
        cursorRow = 0
        hardwareCursorRow = 0
        previousViewportTop = 0
        lastSystemCursor = nil
        maxLinesRendered = 0
    }

    public func takeOverRenderState(from previous: any TuiRenderer) {
        guard let previous = previous as? MainScreenRenderer, previous !== self else { return }

        previousLines = previous.previousLines.map { isImageLine($0) ? "" : $0 }
        previousKittyImageIds = []
        // Image lines were dropped, so their normalized source must not reuse them.
        previousResetSource = previous.previousResetSource.enumerated().map { index, source in
            index < previous.previousLines.count && isImageLine(previous.previousLines[index]) ? "" : source
        }
        previousWidth = previous.previousWidth
        previousHeight = previous.previousHeight
        cursorRow = previous.cursorRow
        hardwareCursorRow = previous.hardwareCursorRow
        previousViewportTop = previous.previousViewportTop
        lastSystemCursor = previous.lastSystemCursor
        maxLinesRendered = previous.maxLinesRendered
    }

    private func collectKittyImageIds(_ lines: [String]) -> [UInt32] {
        var seen: Set<UInt32> = []
        var ids: [UInt32] = []
        for line in lines {
            for id in parseKittyImageHeader(line)?.ids ?? [] where seen.insert(id).inserted {
                ids.append(id)
            }
        }
        return ids
    }

    private func deleteKittyImages(_ ids: [UInt32]) -> String {
        ids.map { deleteKittyImage(imageId: $0) }.joined()
    }

    private func kittyReservedRows(_ lines: [String], at index: Int, through maxIndex: Int? = nil) -> Int {
        let rows = parseKittyImageHeader(lines[index])?.rows ?? 1
        guard rows > 1 else { return 1 }
        let limit = min(rows, (maxIndex ?? lines.count - 1) - index + 1, lines.count - index)
        guard limit > 1 else { return 1 }
        var reserved = 1
        while reserved < limit {
            let line = lines[index + reserved]
            if isImageLine(line) || visibleWidth(line) > 0 { break }
            reserved += 1
        }
        return reserved
    }

    private func expandedKittyRange(first: Int, last: Int, newLines: [String]) -> (first: Int, last: Int) {
        var expandedFirst = first
        var expandedLast = last
        for lines in [previousLines, newLines] {
            for index in lines.indices where !(parseKittyImageHeader(lines[index])?.ids.isEmpty ?? true) {
                let blockEnd = index + kittyReservedRows(lines, at: index) - 1
                if index >= first || (index <= last && blockEnd >= first) {
                    expandedFirst = min(expandedFirst, index)
                    expandedLast = max(expandedLast, blockEnd)
                }
            }
        }
        return (expandedFirst, expandedLast)
    }

    private func deleteChangedKittyImages(first: Int, last: Int) -> String {
        guard first >= 0, last >= first, first < previousLines.count else { return "" }
        var seen: Set<UInt32> = []
        var ids: [UInt32] = []
        for index in first...min(last, previousLines.count - 1) {
            for id in parseKittyImageHeader(previousLines[index])?.ids ?? [] where seen.insert(id).inserted {
                ids.append(id)
            }
        }
        return deleteKittyImages(ids)
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
        let previousBufferLength = previousHeight > 0 ? previousViewportTop + previousHeight : frame.height
        var prevViewportTop = heightChanged ? max(0, previousBufferLength - frame.height) : previousViewportTop
        var viewportTop = prevViewportTop
        var currentHardwareRow = hardwareCursorRow

        func lineDiff(to targetRow: Int) -> Int {
            let currentScreenRow = currentHardwareRow - prevViewportTop
            let targetScreenRow = targetRow - viewportTop
            return targetScreenRow - currentScreenRow
        }

        let debugRedraw = ProcessInfo.processInfo.environment["PI_TUI_DEBUG_REDRAW"] == "1"
        func logRedraw(_ reason: String) {
            guard debugRedraw, let logDirectory else { return }
            let logPath = URL(fileURLWithPath: logDirectory).appendingPathComponent("pi-tui-debug.log")
            let formatter = ISO8601DateFormatter()
            let message = "[\(formatter.string(from: Date()))] fullRender: \(reason) (prev=\(previousLines.count), new=\(newLines.count), height=\(frame.height))\n"
            do {
                try FileManager.default.createDirectory(
                    at: logPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if !FileManager.default.fileExists(atPath: logPath.path) {
                    FileManager.default.createFile(atPath: logPath.path, contents: nil)
                }
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
                buffer += deleteKittyImages(previousKittyImageIds)
                buffer += "\u{001B}[2J\u{001B}[H\u{001B}[3J"
            }
            var i = 0
            while i < newLines.count {
                if i > 0 { buffer += "\r\n" }
                let line = newLines[i]
                let reserved = isImageLine(line) ? kittyReservedRows(newLines, at: i) : 1
                if reserved > 1 && reserved <= frame.height {
                    buffer += String(repeating: "\r\n", count: reserved - 1)
                    buffer += "\u{001B}[\(reserved - 1)A" + line + "\u{001B}[\(reserved - 1)B"
                    i += reserved
                    continue
                }
                buffer += line
                i += 1
            }
            buffer += "\u{001B}[?2026l"
            terminal.write(buffer)
            cursorRow = max(0, newLines.count - 1)
            hardwareCursorRow = cursorRow
            if clear {
                maxLinesRendered = newLines.count
            } else {
                maxLinesRendered = max(maxLinesRendered, newLines.count)
            }
            previousLines = newLines
            previousKittyImageIds = collectKittyImageIds(newLines)
            previousResetSource = normalizedLines
            previousWidth = frame.width
            previousHeight = frame.height
            previousViewportTop = max(0, max(frame.height, newLines.count) - frame.height)
            positionCursorIfNeeded(frame.cursor, frame: frame)
        }

        if previousLines.isEmpty && !widthChanged && !heightChanged {
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
        let appendedLines = newLines.count > previousLines.count
        if appendedLines {
            if firstChanged == -1 { firstChanged = previousLines.count }
            lastChanged = newLines.count - 1
        }
        if firstChanged != -1 {
            let expanded = expandedKittyRange(first: firstChanged, last: lastChanged, newLines: newLines)
            firstChanged = expanded.first
            lastChanged = expanded.last
        }
        let appendStart = appendedLines && firstChanged == previousLines.count && firstChanged > 0

        if firstChanged == -1 {
            if frame.useSystemCursor, frame.cursor != lastSystemCursor {
                positionCursorIfNeeded(frame.cursor, frame: frame)
            }
            previousResetSource = normalizedLines
            previousHeight = frame.height
            previousViewportTop = prevViewportTop
            maxLinesRendered = max(maxLinesRendered, newLines.count)
            return
        }

        if firstChanged >= newLines.count {
            if previousLines.count > newLines.count {
                var buffer = "\u{001B}[?2026h"
                buffer += deleteChangedKittyImages(first: firstChanged, last: lastChanged)
                let targetRow = max(0, newLines.count - 1)
                if targetRow < prevViewportTop {
                    fullRender(clear: true, reason: "deleted lines moved viewport above visible area")
                    return
                }
                let delta = lineDiff(to: targetRow)
                if delta > 0 {
                    buffer += "\u{001B}[\(delta)B"
                } else if delta < 0 {
                    buffer += "\u{001B}[\(-delta)A"
                }
                buffer += "\r"
                let extraLines = previousLines.count - newLines.count
                if extraLines > frame.height {
                    fullRender(clear: true, reason: "deleted lines exceed viewport height")
                    return
                }
                let clearStartOffset = newLines.isEmpty ? 0 : 1
                if extraLines > 0 && clearStartOffset > 0 {
                    buffer += "\u{001B}[1B"
                }
                for index in 0..<extraLines {
                    buffer += "\r\u{001B}[2K"
                    if index < extraLines - 1 { buffer += "\u{001B}[1B" }
                }
                let moveBack = max(0, extraLines - 1 + clearStartOffset)
                if moveBack > 0 {
                    buffer += "\u{001B}[\(moveBack)A"
                }
                buffer += "\u{001B}[?2026l"
                terminal.write(buffer)
                cursorRow = targetRow
                hardwareCursorRow = targetRow
            }
            previousLines = newLines
            previousKittyImageIds = collectKittyImageIds(newLines)
            previousResetSource = normalizedLines
            previousWidth = frame.width
            previousHeight = frame.height
            previousViewportTop = prevViewportTop
            maxLinesRendered = max(maxLinesRendered, newLines.count)
            positionCursorIfNeeded(frame.cursor, frame: frame)
            return
        }

        if firstChanged < prevViewportTop {
            fullRender(clear: true, reason: "firstChanged < viewportTop (\(firstChanged) < \(prevViewportTop))")
            return
        }

        var buffer = "\u{001B}[?2026h"
        buffer += deleteChangedKittyImages(first: firstChanged, last: lastChanged)
        let previousViewportBottom = prevViewportTop + frame.height - 1
        let moveTargetRow = appendStart ? firstChanged - 1 : firstChanged
        if moveTargetRow > previousViewportBottom {
            let currentScreenRow = max(0, min(frame.height - 1, currentHardwareRow - prevViewportTop))
            let moveToBottom = frame.height - 1 - currentScreenRow
            if moveToBottom > 0 { buffer += "\u{001B}[\(moveToBottom)B" }
            let scroll = moveTargetRow - previousViewportBottom
            buffer += String(repeating: "\r\n", count: scroll)
            prevViewportTop += scroll
            viewportTop += scroll
            currentHardwareRow = moveTargetRow
        }
        let delta = lineDiff(to: moveTargetRow)
        if delta > 0 {
            buffer += "\u{001B}[\(delta)B"
        } else if delta < 0 {
            buffer += "\u{001B}[\(-delta)A"
        }
        buffer += appendStart ? "\r\n" : "\r"

        let renderEnd = min(lastChanged, newLines.count - 1)
        if renderEnd >= firstChanged {
            var i = firstChanged
            while i <= renderEnd {
                if i > firstChanged { buffer += "\r\n" }
                let line = newLines[i]
                let reserved = isImageLine(line) ? kittyReservedRows(newLines, at: i, through: renderEnd) : 1
                if reserved > 1 {
                    let imageStartScreenRow = i - viewportTop
                    if imageStartScreenRow < 0 || imageStartScreenRow + reserved > frame.height {
                        fullRender(clear: true, reason: "Kitty image pre-clear would scroll")
                        return
                    }
                    buffer += "\u{001B}[2K"
                    for _ in 1..<reserved { buffer += "\r\n\u{001B}[2K" }
                    buffer += "\u{001B}[\(reserved - 1)A" + line + "\u{001B}[\(reserved - 1)B"
                    i += reserved
                    continue
                }
                buffer += "\u{001B}[2K"
                if !isImageLine(line), visibleWidth(line) > frame.width {
                    reportOverlongLine(line, index: i, lines: newLines, frame: frame)
                }
                buffer += line
                i += 1
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
        cursorRow = max(0, newLines.count - 1)
        hardwareCursorRow = finalCursorRow
        previousViewportTop = max(prevViewportTop, finalCursorRow - frame.height + 1)
        previousLines = newLines
        previousKittyImageIds = collectKittyImageIds(newLines)
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
        let lineDiff = cursor.row - hardwareCursorRow
        if lineDiff > 0 {
            buffer += "\u{001B}[\(lineDiff)B"
        } else if lineDiff < 0 {
            buffer += "\u{001B}[\(-lineDiff)A"
        }
        buffer += "\r"
        buffer += "\u{001B}[\(clampedCol + 1)G"

        terminal.write(buffer)
        hardwareCursorRow = cursor.row
        lastSystemCursor = cursor
    }

    @discardableResult
    func writeCrashDump(_ line: String, index: Int, lines: [String], frame: TuiRenderFrame) -> URL {
        let origin = frame.lineOrigins.flatMap { index < $0.count ? $0[index] : nil }
        let crashLogPath = crashLogURL
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

        return crashLogPath
    }

    private func reportOverlongLine(
        _ line: String,
        index: Int,
        lines: [String],
        frame: TuiRenderFrame
    ) -> Never {
        let origin = frame.lineOrigins.flatMap { index < $0.count ? $0[index] : nil }
        let crashLogPath = crashLogURL
        writeCrashDump(line, index: index, lines: lines, frame: frame)

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
