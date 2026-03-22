import Foundation

/// Anchor position for overlays.
public enum OverlayAnchor: String, Sendable {
    case center
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
    case topCenter = "top-center"
    case bottomCenter = "bottom-center"
    case leftCenter = "left-center"
    case rightCenter = "right-center"
}

/// Margin configuration for overlays.
public struct OverlayMargin: Sendable, Equatable {
    public var top: Int?
    public var right: Int?
    public var bottom: Int?
    public var left: Int?

    public init(top: Int? = nil, right: Int? = nil, bottom: Int? = nil, left: Int? = nil) {
        self.top = top
        self.right = right
        self.bottom = bottom
        self.left = left
    }

    public init(all value: Int) {
        self.top = value
        self.right = value
        self.bottom = value
        self.left = value
    }
}

/// Value that can be absolute or percentage.
public enum SizeValue: Sendable, Equatable, ExpressibleByIntegerLiteral {
    case absolute(Int)
    case percent(Double)

    public init(integerLiteral value: Int) {
        self = .absolute(value)
    }

    public init(_ value: Int) {
        self = .absolute(value)
    }

    public init(percent: Double) {
        self = .percent(percent)
    }

}

/// Options for overlay positioning and sizing.
public struct OverlayOptions: Sendable {
    public var width: SizeValue?
    public var minWidth: Int?
    public var maxHeight: SizeValue?
    public var anchor: OverlayAnchor?
    public var offsetX: Int?
    public var offsetY: Int?
    public var row: SizeValue?
    public var col: SizeValue?
    public var margin: OverlayMargin?
    public var visible: (@Sendable (Int, Int) -> Bool)?

    public init(
        width: SizeValue? = nil,
        minWidth: Int? = nil,
        maxHeight: SizeValue? = nil,
        anchor: OverlayAnchor? = nil,
        offsetX: Int? = nil,
        offsetY: Int? = nil,
        row: SizeValue? = nil,
        col: SizeValue? = nil,
        margin: OverlayMargin? = nil,
        visible: (@Sendable (Int, Int) -> Bool)? = nil
    ) {
        self.width = width
        self.minWidth = minWidth
        self.maxHeight = maxHeight
        self.anchor = anchor
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.row = row
        self.col = col
        self.margin = margin
        self.visible = visible
    }
}

/// Handle returned by showOverlay for controlling the overlay.
@MainActor
public final class OverlayHandle {
    private weak var tui: TUI?
    private let entry: TUI.OverlayEntry

    fileprivate init(tui: TUI, entry: TUI.OverlayEntry) {
        self.tui = tui
        self.entry = entry
    }

    /// Permanently remove the overlay.
    public func hide() {
        tui?.removeOverlay(entry)
    }

    /// Temporarily hide or show the overlay.
    public func setHidden(_ hidden: Bool) {
        tui?.setOverlayHidden(entry, hidden: hidden)
    }

    /// Check if the overlay is temporarily hidden.
    public func isHidden() -> Bool {
        return entry.hidden
    }
}

/// Top-level terminal UI container that manages rendering and input routing.
@MainActor
public final class TUI: Container {
    /// Terminal implementation used for IO.
    public let terminal: Terminal
    private var previousLines: [String] = []
    private var previousResetSource: [String] = []
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
    /// When true, record line origin metadata for debugging overlong lines.
    public var debugLineOrigins = false

    private var renderRequested = false
    private var stopped = false
    private var cursorRow = 0
    private var lastSystemCursor: CursorPosition?
    private var lastLineOrigins: [String] = []
    private var inputBuffer = ""
    private var cellSizeQueryPending = false
    private var clearOnShrink = ProcessInfo.processInfo.environment["PI_CLEAR_ON_SHRINK"] == "1"
    private var maxLinesRendered = 0
    private var fullRedrawCount = 0
    private var overlayStack: [OverlayEntry] = []

    private final class LineOrigins {
        var values: [String]

        init(_ values: [String]) {
            self.values = values
        }
    }

    fileprivate final class OverlayEntry {
        let component: Component
        let options: OverlayOptions?
        let preFocus: Component?
        var hidden: Bool

        init(component: Component, options: OverlayOptions?, preFocus: Component?, hidden: Bool) {
            self.component = component
            self.options = options
            self.preFocus = preFocus
            self.hidden = hidden
        }
    }

    /// Create a TUI bound to a terminal.
    public init(terminal: Terminal) {
        self.terminal = terminal
        super.init()
    }

    /// Return true when clearing is enabled on content shrink.
    public func getClearOnShrink() -> Bool {
        return clearOnShrink
    }

    /// Enable or disable clearing empty rows when content shrinks.
    public func setClearOnShrink(_ enabled: Bool) {
        clearOnShrink = enabled
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

    /// Show an overlay component with configurable positioning and sizing.
    @discardableResult
    public func showOverlay(_ component: Component, options: OverlayOptions? = nil) -> OverlayHandle {
        let entry = OverlayEntry(component: component, options: options, preFocus: focusedComponent, hidden: false)
        overlayStack.append(entry)
        if isOverlayVisible(entry) {
            setFocus(component)
        }
        updateCursorMode()
        requestRender()
        return OverlayHandle(tui: self, entry: entry)
    }

    /// Hide the topmost overlay and restore previous focus.
    public func hideOverlay() {
        guard let overlay = overlayStack.popLast() else { return }
        let topVisible = getTopmostVisibleOverlay()
        setFocus(topVisible?.component ?? overlay.preFocus)
        updateCursorMode()
        requestRender()
    }

    /// Return true if any overlays are visible.
    public func hasOverlay() -> Bool {
        return overlayStack.contains { isOverlayVisible($0) }
    }

    fileprivate func removeOverlay(_ entry: OverlayEntry) {
        guard let index = overlayStack.firstIndex(where: { $0 === entry }) else { return }
        overlayStack.remove(at: index)
        if focusedComponent === entry.component {
            let topVisible = getTopmostVisibleOverlay()
            setFocus(topVisible?.component ?? entry.preFocus)
        }
        updateCursorMode()
        requestRender()
    }

    fileprivate func setOverlayHidden(_ entry: OverlayEntry, hidden: Bool) {
        guard entry.hidden != hidden else { return }
        entry.hidden = hidden
        if hidden {
            if focusedComponent === entry.component {
                let topVisible = getTopmostVisibleOverlay()
                setFocus(topVisible?.component ?? entry.preFocus)
            }
        } else if isOverlayVisible(entry) {
            setFocus(entry.component)
        }
        updateCursorMode()
        requestRender()
    }

    private func isOverlayVisible(_ entry: OverlayEntry) -> Bool {
        if entry.hidden { return false }
        if let visible = entry.options?.visible {
            return visible(terminal.columns, terminal.rows)
        }
        return true
    }

    private func getTopmostVisibleOverlay() -> OverlayEntry? {
        for entry in overlayStack.reversed() {
            if isOverlayVisible(entry) {
                return entry
            }
        }
        return nil
    }

    public override func invalidate() {
        super.invalidate()
        for overlay in overlayStack {
            overlay.component.invalidate()
        }
    }

    /// Start terminal input and initial rendering.
    public func start() {
        stopped = false
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
        stopped = true
        if !previousLines.isEmpty {
            let targetRow = previousLines.count
            let lineDiff = targetRow - cursorRow
            if lineDiff > 0 {
                terminal.write("\u{001B}[\(lineDiff)B")
            } else if lineDiff < 0 {
                terminal.write("\u{001B}[\(-lineDiff)A")
            }
            terminal.write("\r\n")
        }
        terminal.showCursor()
        terminal.stop()
    }

    /// Request a render, optionally forcing a full redraw.
    public func requestRender(force: Bool = false) {
        if stopped { return }
        if force {
            previousLines = []
            previousWidth = -1
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

        if let focused = focusedComponent,
           let focusedOverlay = overlayStack.first(where: { $0.component === focused }),
           !isOverlayVisible(focusedOverlay) {
            if let topVisible = getTopmostVisibleOverlay() {
                setFocus(topVisible.component)
            } else {
                setFocus(focusedOverlay.preFocus)
            }
        }

        if let focused = focusedComponent {
            if isKeyRelease(input), !focused.wantsKeyRelease {
                return
            }
            let shouldPreserveKillChain: Bool
            if focused is KillBufferAware {
                let kb = getKeybindings()
                shouldPreserveKillChain = kb.matches(input, TUIKeybinding.editorDeleteToLineStart)
                    || kb.matches(input, TUIKeybinding.editorDeleteToLineEnd)
                    || kb.matches(input, TUIKeybinding.editorDeleteWordBackward)
                    || kb.matches(input, TUIKeybinding.editorDeleteWordForward)
            } else {
                shouldPreserveKillChain = false
            }
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

    private static let kittyImagePrefix = "\u{001B}_G"
    private static let itermImagePrefix = "\u{001B}]1337;File="

    private func containsImage(_ line: String) -> Bool {
        // Fast path: sequence at line start (single-row images).
        if line.hasPrefix(TUI.kittyImagePrefix) || line.hasPrefix(TUI.itermImagePrefix) {
            return true
        }
        // Slow path: sequence elsewhere (multi-row images have cursor-up prefix).
        return line.contains(TUI.kittyImagePrefix) || line.contains(TUI.itermImagePrefix)
    }

    private static let segmentReset = "\u{001B}[0m\u{001B}]8;;\u{0007}"

    private func parseSizeValue(_ value: SizeValue?, reference: Int) -> Int? {
        guard let value else { return nil }
        switch value {
        case .absolute(let absolute):
            return absolute
        case .percent(let percent):
            return Int((Double(reference) * percent / 100.0).rounded(.down))
        }
    }

    private func resolveOverlayLayout(
        options: OverlayOptions?,
        overlayHeight: Int,
        termWidth: Int,
        termHeight: Int
    ) -> (width: Int, row: Int, col: Int, maxHeight: Int?) {
        let opt = options ?? OverlayOptions()

        let marginTop = max(0, opt.margin?.top ?? 0)
        let marginRight = max(0, opt.margin?.right ?? 0)
        let marginBottom = max(0, opt.margin?.bottom ?? 0)
        let marginLeft = max(0, opt.margin?.left ?? 0)

        let availWidth = max(1, termWidth - marginLeft - marginRight)
        let availHeight = max(1, termHeight - marginTop - marginBottom)

        var width = parseSizeValue(opt.width, reference: termWidth) ?? min(80, availWidth)
        if let minWidth = opt.minWidth {
            width = max(width, minWidth)
        }
        width = max(1, min(width, availWidth))

        var maxHeight = parseSizeValue(opt.maxHeight, reference: termHeight)
        if let value = maxHeight {
            maxHeight = max(1, min(value, availHeight))
        }

        let effectiveHeight = maxHeight.map { min(overlayHeight, $0) } ?? overlayHeight

        var row: Int
        if let rowValue = opt.row {
            switch rowValue {
            case .absolute(let absolute):
                row = absolute
            case .percent(let percent):
                let maxRow = max(0, availHeight - effectiveHeight)
                row = marginTop + Int((Double(maxRow) * percent / 100.0).rounded(.down))
            }
        } else {
            row = resolveAnchorRow(opt.anchor ?? .center, height: effectiveHeight, availHeight: availHeight, marginTop: marginTop)
        }

        var col: Int
        if let colValue = opt.col {
            switch colValue {
            case .absolute(let absolute):
                col = absolute
            case .percent(let percent):
                let maxCol = max(0, availWidth - width)
                col = marginLeft + Int((Double(maxCol) * percent / 100.0).rounded(.down))
            }
        } else {
            col = resolveAnchorCol(opt.anchor ?? .center, width: width, availWidth: availWidth, marginLeft: marginLeft)
        }

        if let offsetY = opt.offsetY {
            row += offsetY
        }
        if let offsetX = opt.offsetX {
            col += offsetX
        }

        row = max(marginTop, min(row, termHeight - marginBottom - effectiveHeight))
        col = max(marginLeft, min(col, termWidth - marginRight - width))

        return (width, row, col, maxHeight)
    }

    private func resolveAnchorRow(_ anchor: OverlayAnchor, height: Int, availHeight: Int, marginTop: Int) -> Int {
        switch anchor {
        case .topLeft, .topCenter, .topRight:
            return marginTop
        case .bottomLeft, .bottomCenter, .bottomRight:
            return marginTop + availHeight - height
        case .leftCenter, .center, .rightCenter:
            return marginTop + (availHeight - height) / 2
        }
    }

    private func resolveAnchorCol(_ anchor: OverlayAnchor, width: Int, availWidth: Int, marginLeft: Int) -> Int {
        switch anchor {
        case .topLeft, .leftCenter, .bottomLeft:
            return marginLeft
        case .topRight, .rightCenter, .bottomRight:
            return marginLeft + availWidth - width
        case .topCenter, .center, .bottomCenter:
            return marginLeft + (availWidth - width) / 2
        }
    }

    private func compositeOverlays(
        _ lines: [String],
        termWidth: Int,
        termHeight: Int,
        lineOrigins: LineOrigins? = nil
    ) -> [String] {
        if overlayStack.isEmpty { return lines }
        var result = lines
        var rendered: [(lines: [String], row: Int, col: Int, width: Int, component: Component)] = []
        var minLinesNeeded = result.count

        for entry in overlayStack {
            if !isOverlayVisible(entry) { continue }

            let baseLayout = resolveOverlayLayout(options: entry.options, overlayHeight: 0, termWidth: termWidth, termHeight: termHeight)
            var overlayLines = entry.component.render(width: baseLayout.width)
            if let maxHeight = baseLayout.maxHeight, overlayLines.count > maxHeight {
                overlayLines = Array(overlayLines.prefix(maxHeight))
            }
            let layout = resolveOverlayLayout(options: entry.options, overlayHeight: overlayLines.count, termWidth: termWidth, termHeight: termHeight)

            rendered.append((lines: overlayLines, row: layout.row, col: layout.col, width: layout.width, component: entry.component))
            minLinesNeeded = max(minLinesNeeded, layout.row + overlayLines.count)
        }

        if rendered.isEmpty {
            return lines
        }

        while result.count < minLinesNeeded {
            result.append("")
            lineOrigins?.values.append("<overlay padding>")
        }

        let viewportStart = max(0, result.count - termHeight)
        var modifiedLines = Set<Int>()

        for overlay in rendered {
            let overlayObj: AnyObject = overlay.component
            let overlayName = "\(type(of: overlay.component))@\(Unmanaged.passUnretained(overlayObj).toOpaque())"
            for i in 0..<overlay.lines.count {
                let idx = viewportStart + overlay.row + i
                if idx >= 0 && idx < result.count {
                    let overlayLine = overlay.lines[i]
                    let truncatedOverlay = visibleWidth(overlayLine) > overlay.width
                        ? sliceByColumn(overlayLine, startCol: 0, length: overlay.width, strict: true)
                        : overlayLine
                    result[idx] = compositeLineAt(
                        baseLine: result[idx],
                        overlayLine: truncatedOverlay,
                        startCol: overlay.col,
                        overlayWidth: overlay.width,
                        totalWidth: termWidth
                    )
                    if let origins = lineOrigins, idx < origins.values.count {
                        let base = origins.values[idx]
                        if base.isEmpty {
                            origins.values[idx] = "Overlay(\(overlayName))"
                        } else {
                            origins.values[idx] = base + " + Overlay(\(overlayName))"
                        }
                    }
                    modifiedLines.insert(idx)
                }
            }
        }

        for idx in modifiedLines {
            if visibleWidth(result[idx]) > termWidth {
                result[idx] = sliceByColumn(result[idx], startCol: 0, length: termWidth, strict: true)
            }
        }

        return result
    }

    private func applyLineResets(
        _ lines: [String],
        previousSource: [String],
        previousLines: [String]
    ) -> [String] {
        let reset = TUI.segmentReset
        var result = lines
        let canReuse = !previousSource.isEmpty && previousSource.count == previousLines.count
        for index in result.indices {
            let line = result[index]
            if canReuse, index < previousSource.count, previousSource[index] == line, index < previousLines.count {
                result[index] = previousLines[index]
                continue
            }
            if !containsImage(line) {
                result[index] = line + reset
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

        let overlay = sliceWithWidth(overlayLine, startCol: 0, length: overlayWidth, strict: true)

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

        if visibleWidth(result) <= totalWidth {
            return result
        }

        return sliceByColumn(result, startCol: 0, length: totalWidth, strict: true)
    }

    private func doRender() {
        if stopped { return }
        let width = terminal.columns
        let height = terminal.rows

        var renderedLines: [String]
        var lineOrigins: LineOrigins?
        if debugLineOrigins {
            let trace = RenderTrace()
            RenderTrace.active = trace
            renderedLines = render(width: width)
            RenderTrace.active = nil
            var origins = trace.origins
            if origins.count < renderedLines.count {
                origins.append(contentsOf: repeatElement("<unknown>", count: renderedLines.count - origins.count))
            } else if origins.count > renderedLines.count {
                origins = Array(origins.prefix(renderedLines.count))
            }
            lineOrigins = LineOrigins(origins)
        } else {
            renderedLines = render(width: width)
        }
        if !overlayStack.isEmpty {
            renderedLines = compositeOverlays(renderedLines, termWidth: width, termHeight: height, lineOrigins: lineOrigins)
        }
        let cursorPosition: CursorPosition?
        let cleanedLines: [String]
        if useSystemCursor {
            let extraction = extractCursorPosition(from: renderedLines, height: height)
            cleanedLines = extraction.lines
            cursorPosition = extraction.cursor
        } else {
            cleanedLines = renderedLines
            cursorPosition = nil
        }
        let resetLines = applyLineResets(
            cleanedLines,
            previousSource: previousResetSource,
            previousLines: previousLines
        )
        let widthChanged = previousWidth != 0 && previousWidth != width
        let newLines = resetLines
        lastLineOrigins = debugLineOrigins ? (lineOrigins?.values ?? []) : []

        let debugRedraw = ProcessInfo.processInfo.environment["PI_DEBUG_REDRAW"] == "1"
        func logRedraw(_ reason: String) {
            guard debugRedraw else { return }
            let logPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".pi/agent/pi-debug.log")
            let formatter = ISO8601DateFormatter()
            let message = "[\(formatter.string(from: Date()))] fullRender: \(reason) (prev=\(previousLines.count), new=\(newLines.count), height=\(height))\n"
            do {
                try FileManager.default.createDirectory(at: logPath.deletingLastPathComponent(), withIntermediateDirectories: true)
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
                buffer += "\u{001B}[3J\u{001B}[2J\u{001B}[H"
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
            previousResetSource = cleanedLines
            previousWidth = width
            positionCursorIfNeeded(cursorPosition, width: width)
        }

        if previousLines.isEmpty && !widthChanged {
            fullRender(clear: false, reason: "first render")
            return
        }

        if widthChanged {
            fullRender(clear: true, reason: "width changed (\(previousWidth) -> \(width))")
            return
        }

        if clearOnShrink && newLines.count < maxLinesRendered && overlayStack.isEmpty {
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
            if useSystemCursor, cursorPosition != lastSystemCursor {
                positionCursorIfNeeded(cursorPosition, width: width)
            }
            previousResetSource = cleanedLines
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
            previousResetSource = cleanedLines
            previousWidth = width
            maxLinesRendered = max(maxLinesRendered, newLines.count)
            positionCursorIfNeeded(cursorPosition, width: width)
            return
        }

        let viewportTop = cursorRow - height + 1
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
                if !containsImage(line), visibleWidth(line) > width {
                    let origin = debugLineOrigins && i < lastLineOrigins.count ? lastLineOrigins[i] : nil
                    let crashLogPath = FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".pi/agent/pi-crash.log")
                    let formatter = ISO8601DateFormatter()
                    var crashLines = [
                        "Crash at \(formatter.string(from: Date()))",
                        "Terminal width: \(width)",
                        "Line \(i) visible width: \(visibleWidth(line))",
                    ]
                    if let origin {
                        crashLines.append("Origin: \(origin)")
                    }
                    crashLines.append("")
                    crashLines.append("=== All rendered lines ===")
                    crashLines.append(contentsOf: newLines.enumerated().map { idx, value in
                        if debugLineOrigins, idx < lastLineOrigins.count {
                            return "[\(idx)] (w=\(visibleWidth(value))) [\(lastLineOrigins[idx])] \(value)"
                        }
                        return "[\(idx)] (w=\(visibleWidth(value))) \(value)"
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

                    stop()

                    var errorLines = [
                        "Rendered line \(i) exceeds terminal width (\(visibleWidth(line)) > \(width)).",
                    ]
                    if let origin {
                        errorLines.append("Origin: \(origin)")
                    }
                    errorLines.append("")
                    errorLines.append("This is likely caused by a custom TUI component not truncating its output.")
                    errorLines.append("Use visibleWidth() to measure and truncateToWidth() to truncate lines.")
                    errorLines.append("")
                    errorLines.append("Debug log written to: \(crashLogPath.path)")
                    let errorMsg = errorLines.joined(separator: "\n")
                    fatalError(errorMsg)
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
        previousResetSource = cleanedLines
        previousWidth = width
        maxLinesRendered = max(maxLinesRendered, newLines.count)
        positionCursorIfNeeded(cursorPosition, width: width)
    }

    private func updateCursorMode() {
        let overlayActive = hasOverlay()
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

    private func extractCursorPosition(from lines: [String], height: Int) -> (lines: [String], cursor: CursorPosition?) {
        var cursor: CursorPosition?
        var cleaned = lines
        let viewportTop = max(0, lines.count - max(0, height))
        if !lines.isEmpty {
            for row in stride(from: lines.count - 1, through: viewportTop, by: -1) {
                if let range = cleaned[row].range(of: systemCursorMarker) {
                    let prefix = String(cleaned[row][..<range.lowerBound])
                    let col = visibleWidth(prefix)
                    cursor = CursorPosition(row: row, col: col)
                    cleaned[row] = cleaned[row].replacingOccurrences(of: systemCursorMarker, with: "")
                    break
                }
            }
        }

        return (cleaned, cursor)
    }

    private func positionCursorIfNeeded(_ cursor: CursorPosition?, width: Int) {
        guard useSystemCursor, !hasOverlay(), let cursor else { return }

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
