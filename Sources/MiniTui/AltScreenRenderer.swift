import Foundation

private let enterAltScreen = "\u{001B}[?1049h"
private let exitAltScreen = "\u{001B}[?1049l"
private let disableAutowrap = "\u{001B}[?7l"
private let enableAutowrap = "\u{001B}[?7h"
private let enableButtonMotionMouse = "\u{001B}[?1000h\u{001B}[?1002h\u{001B}[?1004h\u{001B}[?1006h"
private let enableAllMotionMouse = "\u{001B}[?1000h\u{001B}[?1002h\u{001B}[?1003h\u{001B}[?1004h\u{001B}[?1006h"
private let disableMouse = "\u{001B}[?1006l\u{001B}[?1004l\u{001B}[?1003l\u{001B}[?1002l\u{001B}[?1000l"
private let focusIn = "\u{001B}[I"
private let focusOut = "\u{001B}[O"
private let beginSynchronizedOutput = "\u{001B}[?2026h"
private let endSynchronizedOutput = "\u{001B}[?2026l"
private let pageScrollOverlap = 4
private let doubleClickIntervalMilliseconds = 500.0

/// Mouse motion reports requested while the alternate screen is active.
public enum AltScreenMouseMotion: Sendable, Equatable {
    /// Report presses, releases, and pointer motion while a button is down.
    case button
    /// Report all pointer motion, including hover motion.
    case all
    /// Match upstream: button-motion inside a multiplexer, all-motion elsewhere.
    case auto

    /// Multiplexers lag when every pointer movement is forwarded, so they get button-motion
    /// tracking, which still preserves clicks, wheel events, selection, and scrollbar dragging.
    /// Everywhere else uses all-motion so hover feedback (e.g. scrollbar highlight) works without
    /// a button held down.
    static func resolved(_ motion: AltScreenMouseMotion, environment: [String: String]) -> AltScreenMouseMotion {
        guard motion == .auto else { return motion }
        let term = (environment["TERM"] ?? "").lowercased()
        let inMultiplexer = environment["TMUX"] != nil
            || environment["ZELLIJ"] != nil
            || environment["STY"] != nil
            || term.hasPrefix("tmux")
            || term.hasPrefix("screen")
        return inMultiplexer ? .button : .all
    }
}

/// Configuration for an alternate-screen renderer.
public struct AltScreenRendererOptions {
    public var wheelScrollLines: Int
    public var mouse: Bool
    public var mouseMotion: AltScreenMouseMotion
    public var openURL: ((String) -> Void)?
    public var onRightClickPaste: (() -> Void)?

    public init(
        wheelScrollLines: Int = 1,
        mouse: Bool = true,
        mouseMotion: AltScreenMouseMotion = .auto,
        openURL: ((String) -> Void)? = nil,
        onRightClickPaste: (() -> Void)? = nil
    ) {
        self.wheelScrollLines = max(1, wheelScrollLines)
        self.mouse = mouse
        self.mouseMotion = mouseMotion
        self.openURL = openURL
        self.onRightClickPaste = onRightClickPaste
    }
}

/// Logical button decoded from an SGR mouse report.
public enum SgrMouseButton: Sendable, Equatable {
    case primary
    case middle
    case secondary
    case wheelUp
    case wheelDown
    case other(Int)
}

/// Modifier bits decoded from an SGR mouse report.
public struct SgrMouseModifiers: Sendable, Equatable {
    public let shift: Bool
    public let alt: Bool
    public let control: Bool

    public init(shift: Bool, alt: Bool, control: Bool) {
        self.shift = shift
        self.alt = alt
        self.control = control
    }
}

/// One decoded `CSI < Cb ; Cx ; Cy M/m` mouse report.
public struct SgrMouseEvent: Sendable, Equatable {
    public let rawButton: Int
    public let button: SgrMouseButton
    public let x: Int
    public let y: Int
    public let release: Bool
    public let motion: Bool
    public let wheel: Bool
    public let modifiers: SgrMouseModifiers

    public init(rawButton: Int, x: Int, y: Int, release: Bool) {
        self.rawButton = rawButton
        self.x = x
        self.y = y
        self.release = release
        self.motion = rawButton & 32 != 0
        self.wheel = rawButton & 64 != 0
        self.modifiers = SgrMouseModifiers(
            shift: rawButton & 4 != 0,
            alt: rawButton & 8 != 0,
            control: rawButton & 16 != 0
        )
        if rawButton & 64 != 0 {
            switch rawButton & 3 {
            case 0: self.button = .wheelUp
            case 1: self.button = .wheelDown
            default: self.button = .other(rawButton & 3)
            }
        } else {
            switch rawButton & 3 {
            case 0: self.button = .primary
            case 1: self.button = .middle
            case 2: self.button = .secondary
            default: self.button = .other(rawButton & 3)
            }
        }
    }
}

/// Parse one complete SGR mouse report. Coordinates are returned as zero-based cells.
public func parseSgrMouseEvent(_ data: String) -> SgrMouseEvent? {
    let prefix = "\u{001B}[<"
    guard data.hasPrefix(prefix), let final = data.last, final == "M" || final == "m" else {
        return nil
    }
    let bodyStart = data.index(data.startIndex, offsetBy: prefix.count)
    let bodyEnd = data.index(before: data.endIndex)
    let fields = data[bodyStart..<bodyEnd].split(separator: ";", omittingEmptySubsequences: false)
    guard fields.count == 3,
          fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
          let rawButton = Int(fields[0]),
          let column = Int(fields[1]), column > 0,
          let row = Int(fields[2]), row > 0 else {
        return nil
    }
    return SgrMouseEvent(rawButton: rawButton, x: column - 1, y: row - 1, release: final == "m")
}

@MainActor
private final class WeakRootComponent: Component {
    weak var root: Component?

    func render(width: Int) -> [String] {
        root?.render(width: width) ?? []
    }

    func invalidate() {
        root?.invalidate()
    }
}

private struct SelectionPoint {
    var row: Int
    var col: Int
    var scrollView: ScrollView?
    var boundary = false
}

private struct SelectionRange {
    var start: SelectionPoint
    var end: SelectionPoint
}

private enum SelectionGranularity {
    case character
    case word
    case line
}

private struct ClickTarget {
    var timestamp: Double
    var count: Int
    var row: Int
    var scrollView: ScrollView?
    var wordStart: Int
    var wordEnd: Int
}

private struct ScrollbarDrag {
    var scrollView: ScrollView
    var grabOffset: Int
}

private struct ScrollbarTarget {
    var scrollView: ScrollView
    var geometry: ScrollbarGeometry
}

private struct CachedKittyImage {
    var transmissionGeneration: Int
    var transmissionBytes: Int
    var estimatedDecodedBytes: Int
}

/// Fixed-viewport renderer for the terminal alternate screen.
@MainActor
public final class AltScreenRenderer: TuiRenderer, TuiLayoutRenderer, TuiInputRenderer, TuiHostedRenderer {
    public let mode = TuiMode.altScreen

    private let terminal: Terminal
    private let options: AltScreenRendererOptions
    private let weakRoot = WeakRootComponent()
    private lazy var implicitScrollView = ScrollView(
        weakRoot,
        options: ScrollViewOptions(follow: .end, primary: true)
    )
    private lazy var flashes = AltScreenFlashContainer { [weak self] in
        self?.requestRender()
    }

    private var explicitLayoutRoot: Component?
    private var requestRenderCallback: () -> Void = {}
    private var hasOverlayCallback: () -> Bool = { false }
    private var previousScreen: [String] = []
    private var previousWidth = 0
    private var previousHeight = 0
    private var currentLayout: LayoutFrame?
    private var altScreenActive = false
    private var imageProtocol: ImageProtocol?
    private var savedCapabilities: TerminalCapabilities?
    private var uploadedKittyImages: [UInt32: CachedKittyImage] = [:]

    private var selectionAnchor: SelectionPoint?
    private var selectionFocus: SelectionPoint?
    private var selectionGranularity = SelectionGranularity.character
    private var selectionInitialRange: SelectionRange?
    private var lastClick: ClickTarget?
    private var selectionDragPointer: (x: Int, y: Int)?
    private var selectionAutoScrollDirection = 0
    private var selectionAutoScrollTask: Task<Void, Never>?
    private var selectionPressActive = false
    private var selectionDragged = false
    private var scrollbarDrag: ScrollbarDrag?
    private var scrollbarHover: ScrollView?
    private var pressedURL: String?

    public init(terminal: Terminal, options: AltScreenRendererOptions = AltScreenRendererOptions()) {
        self.terminal = terminal
        self.options = options
    }

    func attach(
        root: Component,
        requestRender: @escaping () -> Void,
        hasOverlay: @escaping () -> Bool
    ) {
        weakRoot.root = root
        requestRenderCallback = requestRender
        hasOverlayCallback = hasOverlay
    }

    /// Use an explicit constraint-layout root instead of the implicit scrolling document.
    public func setLayoutRoot(_ component: Component?) {
        guard explicitLayoutRoot !== component else { return }
        explicitLayoutRoot = component
        currentLayout = nil
        requestRender()
    }

    public var viewportTop: Int { primaryScrollView.scrollTop }
    public var isFollowingOutput: Bool { primaryScrollView.isFollowingEnd }

    public func setScrollbar(_ mode: ScrollViewScrollbar) {
        primaryScrollView.setScrollbar(mode)
    }

    public func flash(_ message: String, durationMilliseconds: Int = 1_000) {
        flashes.flash(message, durationMilliseconds: durationMilliseconds)
    }

    public func renderLayout(
        root: Component,
        width: Int,
        height: Int,
        requestRender: @escaping () -> Void
    ) -> LayoutFrame {
        if weakRoot.root == nil { weakRoot.root = root }
        return renderLayoutFrame(
            root: explicitLayoutRoot ?? implicitScrollView,
            width: width,
            height: height,
            requestRender: requestRender
        )
    }

    public func start() {
        stopSelectionAutoScroll()
        selectionPressActive = false
        stopScrollbarHover()
        stopScrollbarDrag()
        flashes.dispose()
        altScreenActive = true
        let capabilities = getCapabilities()
        imageProtocol = capabilities.images
        uploadedKittyImages.removeAll()
        if capabilities.images == .iterm2 {
            savedCapabilities = capabilities
            setCapabilities(TerminalCapabilities(
                images: nil,
                trueColor: capabilities.trueColor,
                hyperlinks: capabilities.hyperlinks
            ))
            weakRoot.invalidate()
        }
        resetInteractionState()
        clearRenderState()
        let mouseSequence: String
        switch AltScreenMouseMotion.resolved(options.mouseMotion, environment: ProcessInfo.processInfo.environment) {
        case .button: mouseSequence = enableButtonMotionMouse
        case .all, .auto: mouseSequence = enableAllMotionMouse
        }
        terminal.write(
            enterAltScreen
                + disableAutowrap
                + (options.mouse ? mouseSequence : "")
                + "\u{001B}[2J\u{001B}[H\u{001B}[?25l"
        )
    }

    public func stop(preserveScreen: Bool = false) {
        stopSelectionAutoScroll()
        selectionPressActive = false
        stopScrollbarHover()
        stopScrollbarDrag()
        flashes.dispose()
        guard altScreenActive else { return }

        terminal.write(
            beginSynchronizedOutput
                + deleteKittyImages()
                + (options.mouse ? disableMouse : "")
                + enableAutowrap
                + endSynchronizedOutput
        )
        uploadedKittyImages.removeAll()

        // Consume delayed terminal reports before raw mode is released to the parent shell.
        terminal.drainInput(maxMs: 100, idleMs: 10)

        if preserveScreen {
            terminal.write(beginSynchronizedOutput + exitAltScreen + "\u{001B}[?25h" + endSynchronizedOutput)
        } else {
            let width = max(1, terminal.columns)
            let document = replayDocument(width: width)
            var buffer = beginSynchronizedOutput + exitAltScreen + disableAutowrap
            for row in document.indices {
                if row > 0 { buffer += "\r\n" }
                buffer += "\r\u{001B}[2K" + document[row]
            }
            buffer += "\u{001B}[0m" + enableAutowrap + "\r\n\u{001B}[?25h" + endSynchronizedOutput
            terminal.write(buffer)
        }
        altScreenActive = false
        if let savedCapabilities {
            setCapabilities(savedCapabilities)
            self.savedCapabilities = nil
        }
    }

    public func invalidateRenderState() {
        previousScreen = []
        previousWidth = -1
        previousHeight = -1
        currentLayout = nil
    }

    public func invalidateCursorState() {}

    public func clearRenderState() {
        previousScreen = []
        previousWidth = 0
        previousHeight = 0
        currentLayout = nil
    }

    public func takeOverRenderState(from previous: any TuiRenderer) {
        guard let previous = previous as? AltScreenRenderer, previous !== self else { return }
        previousScreen = previous.previousScreen
        previousWidth = previous.previousWidth
        previousHeight = previous.previousHeight
        currentLayout = previous.currentLayout
        uploadedKittyImages = previous.uploadedKittyImages
    }

    public func scrollBy(_ lines: Int) {
        primaryScrollView.scrollBy(lines)
        requestRender()
    }

    public func scrollToTop() {
        primaryScrollView.scrollToStart()
        requestRender()
    }

    public func scrollToBottom() {
        primaryScrollView.scrollToEnd()
        requestRender()
    }

    public func present(_ frame: TuiRenderFrame) {
        guard altScreenActive else { return }
        let width = max(1, frame.width)
        let height = max(1, frame.height)
        let nextLayout = frame.layoutFrame
        var screen = frame.lines.map(stripLeadingOSC133Zones)
        if screen.count > height { screen = Array(screen.suffix(height)) }
        screen = applySelection(to: screen, layout: nextLayout)
        screen = compositeFlashes(on: screen, width: width, height: height)
        screen = screen.map { line in
            let normalized = normalizeTerminalOutput(line)
            if isImageLine(normalized) { return normalized }
            let bounded = visibleWidth(normalized) <= width
                ? normalized
                : sliceByColumn(normalized, startCol: 0, length: width, strict: true)
            return bounded + "\u{001B}[0m" + osc8HyperlinkCloseBell
        }

        let fullRedraw = previousScreen.isEmpty || previousWidth != width || previousHeight != height
        let imagesNeedRedraw = screen.indices.contains { row in
            let previous = previousScreen.indices.contains(row) ? previousScreen[row] : ""
            return screen[row] != previous && (isImageLine(screen[row]) || isImageLine(previous))
        }
        let redrawImages = fullRedraw || imagesNeedRedraw
        let hadUploadedKittyImages = !uploadedKittyImages.isEmpty
        let prepared = redrawImages && imageProtocol == .kitty
            ? prepareKittyScreen(screen)
            : (lines: screen, evictedImageDeletion: "")

        var buffer = beginSynchronizedOutput
        if fullRedraw {
            if imageProtocol == .kitty {
                buffer += hadUploadedKittyImages ? deleteAllKittyPlacements() : deleteKittyImages()
            }
            buffer += "\u{001B}[2J"
        } else if imagesNeedRedraw {
            if imageProtocol == .iterm2 { buffer += "\u{001B}[2J" }
            if imageProtocol == .kitty { buffer += deleteAllKittyPlacements() }
        }
        buffer += prepared.evictedImageDeletion

        for row in 0..<height {
            let line = screen.indices.contains(row) ? screen[row] : ""
            let old = previousScreen.indices.contains(row) ? previousScreen[row] : ""
            if !fullRedraw && !imagesNeedRedraw && line == old { continue }
            let outputLine = prepared.lines.indices.contains(row) ? prepared.lines[row] : ""
            buffer += "\u{001B}[\(row + 1);1H\u{001B}[2K" + outputLine
        }

        if frame.useSystemCursor, !frame.hasVisibleOverlay, let cursor = frame.cursor {
            let row = max(0, min(height - 1, cursor.row))
            let col = max(0, min(width - 1, cursor.col))
            buffer += "\u{001B}[\(row + 1);\(col + 1)H\u{001B}[?25h"
        } else {
            buffer += "\u{001B}[?25l"
        }
        buffer += endSynchronizedOutput
        terminal.write(buffer)

        previousScreen = screen
        previousWidth = width
        previousHeight = height
        currentLayout = nextLayout
    }

    @discardableResult
    public func handleInput(_ data: String) -> Bool {
        if data == focusOut {
            let hadActiveSelection = selectionPressActive
            selectionPressActive = false
            stopSelectionAutoScroll()
            stopScrollbarHover()
            stopScrollbarDrag()
            pressedURL = nil
            selectionDragged = false
            if hadActiveSelection { clearSelection() }
            lastClick = nil
            requestRender()
            return true
        }
        if data == focusIn { return true }

        if let wheel = parseWheelEvent(data) {
            routeWheel(direction: wheel.direction, x: wheel.x, y: wheel.y)
            return true
        }
        if let event = parseSgrMouseEvent(data) {
            if handleRightClickPaste(event) { return true }
            let handled = handleScrollbarMouseEvent(event)
            if scrollbarDrag == nil { updateScrollbarHover(x: event.x, y: event.y) }
            if !handled { handleSelectionMouseEvent(event) }
            return true
        }
        if isMouseSequence(data) { return true }

        let keybindings = getKeybindings()
        let release = isKeyRelease(data)
        if keybindings.matches(data, TUIKeybinding.altScreenPageUp) {
            if !release { scrollBy(-max(1, primaryScrollView.viewportHeight - pageScrollOverlap)) }
            return true
        }
        if keybindings.matches(data, TUIKeybinding.altScreenPageDown) {
            if !release { scrollBy(max(1, primaryScrollView.viewportHeight - pageScrollOverlap)) }
            return true
        }
        if keybindings.matches(data, TUIKeybinding.altScreenHalfPageUp) {
            if !release { scrollBy(-max(1, primaryScrollView.viewportHeight / 2)) }
            return true
        }
        if keybindings.matches(data, TUIKeybinding.altScreenHalfPageDown) {
            if !release { scrollBy(max(1, primaryScrollView.viewportHeight / 2)) }
            return true
        }
        if keybindings.matches(data, TUIKeybinding.altScreenPreviousPrompt) {
            if !release { scrollToPrompt(direction: -1) }
            return true
        }
        if keybindings.matches(data, TUIKeybinding.altScreenNextPrompt) {
            if !release { scrollToPrompt(direction: 1) }
            return true
        }
        if keybindings.matches(data, TUIKeybinding.altScreenTop) {
            if !release { scrollToTop() }
            return true
        }
        if keybindings.matches(data, TUIKeybinding.altScreenBottom) {
            if !release { scrollToBottom() }
            return true
        }
        return false
    }

    private var primaryScrollView: ScrollView {
        currentLayout?.primaryScrollView ?? implicitScrollView
    }

    private func requestRender() {
        requestRenderCallback()
    }

    private func resetInteractionState() {
        selectionAnchor = nil
        selectionFocus = nil
        selectionGranularity = .character
        selectionInitialRange = nil
        lastClick = nil
        pressedURL = nil
        selectionDragged = false
    }

    private func clearSelection() {
        selectionAnchor = nil
        selectionFocus = nil
        selectionGranularity = .character
        selectionInitialRange = nil
    }

    private func replayDocument(width: Int) -> [String] {
        let lines: [String]
        if let currentLayout,
           let box = getScrollViewBox(frame: currentLayout, scrollView: primaryScrollView),
           let content = box.scrollContentLines {
            lines = content
        } else {
            lines = previousScreen
        }
        return lines.map { line in
            let clean = stripLeadingOSC133Zones(line).replacingOccurrences(of: systemCursorMarker, with: "")
            if isImageLine(clean) || visibleWidth(clean) <= width { return clean }
            return sliceByColumn(clean, startCol: 0, length: width, strict: true)
        }
    }

    private func scrollToPrompt(direction: Int) {
        guard let currentLayout,
              let lines = getScrollViewBox(frame: currentLayout, scrollView: primaryScrollView)?.scrollContentLines else {
            return
        }
        var row = primaryScrollView.scrollTop + direction
        while row >= 0 && row < lines.count {
            if isOSC133PromptStart(lines[row]) {
                primaryScrollView.scrollTo(row)
                requestRender()
                return
            }
            row += direction
        }
    }

    private func parseWheelEvent(_ data: String) -> (direction: Int, x: Int, y: Int)? {
        if let event = parseSgrMouseEvent(data), event.wheel {
            switch event.button {
            case .wheelUp: return (-1, event.x, event.y)
            case .wheelDown: return (1, event.x, event.y)
            default: return nil
            }
        }
        let characters = Array(data.unicodeScalars)
        if characters.count == 6,
           characters[0].value == 0x1B,
           characters[1] == "[",
           characters[2] == "M" {
            let button = Int(characters[3].value) - 32
            guard button & 64 != 0 else { return nil }
            let direction = button & 3
            guard direction == 0 || direction == 1 else { return nil }
            return (
                direction == 0 ? -1 : 1,
                Int(characters[4].value) - 33,
                Int(characters[5].value) - 33
            )
        }
        return nil
    }

    private func routeWheel(direction: Int, x: Int, y: Int) {
        var remaining = direction * options.wheelScrollLines
        var seen: Set<ObjectIdentifier> = []
        if let currentLayout {
            for scrollView in getScrollViewsAt(frame: currentLayout, x: x, y: y) {
                seen.insert(ObjectIdentifier(scrollView))
                remaining = scrollView.scrollBy(remaining)
                if remaining == 0 || scrollView.overscroll == .contain { break }
            }
        }
        let primary = primaryScrollView
        if remaining != 0, !seen.contains(ObjectIdentifier(primary)) {
            primary.scrollBy(remaining)
        }
        updateScrollbarHover(x: x, y: y)
        requestRender()
    }

    private func handleRightClickPaste(_ event: SgrMouseEvent) -> Bool {
        #if os(Windows)
        guard let onRightClickPaste = options.onRightClickPaste,
              !event.release,
              event.button == .secondary,
              !event.modifiers.shift,
              !event.modifiers.alt,
              !event.modifiers.control else {
            return false
        }
        onRightClickPaste()
        return true
        #else
        return false
        #endif
    }

    private func scrollbarTargetAt(x: Int, y: Int) -> ScrollbarTarget? {
        guard !hasOverlayCallback(), let currentLayout else { return nil }
        for scrollView in getScrollViewsAt(frame: currentLayout, x: x, y: y) {
            guard let box = getScrollViewBox(frame: currentLayout, scrollView: scrollView),
                  let geometry = getScrollbarGeometry(box),
                  x == geometry.column,
                  y >= geometry.thumbTop,
                  y < geometry.thumbTop + geometry.thumbHeight else {
                continue
            }
            return ScrollbarTarget(scrollView: scrollView, geometry: geometry)
        }
        return nil
    }

    private func setScrollbarHover(_ scrollView: ScrollView?) {
        if scrollbarHover === scrollView { return }
        scrollbarHover?.setScrollbarActive(false)
        scrollbarHover = scrollView
        scrollbarHover?.setScrollbarActive(true)
    }

    private func updateScrollbarHover(x: Int, y: Int) {
        setScrollbarHover(scrollbarTargetAt(x: x, y: y)?.scrollView)
    }

    private func stopScrollbarHover() {
        setScrollbarHover(nil)
    }

    private func handleScrollbarMouseEvent(_ event: SgrMouseEvent) -> Bool {
        if let drag = scrollbarDrag {
            if event.release {
                stopScrollbarDrag()
                return true
            }
            if let currentLayout,
               let box = getScrollViewBox(frame: currentLayout, scrollView: drag.scrollView),
               let geometry = getScrollbarGeometry(box) {
                let maxThumbOffset = geometry.trackHeight - geometry.thumbHeight
                let thumbOffset = max(
                    0,
                    min(maxThumbOffset, event.y - geometry.trackTop - drag.grabOffset)
                )
                let scrollTop = maxThumbOffset == 0
                    ? 0
                    : Int((Double(thumbOffset) / Double(maxThumbOffset) * Double(geometry.maxScrollTop)).rounded())
                drag.scrollView.scrollTo(scrollTop)
            }
            return true
        }

        guard !event.release, !event.motion, event.button == .primary,
              let target = scrollbarTargetAt(x: event.x, y: event.y) else {
            return false
        }
        stopSelectionAutoScroll()
        selectionPressActive = false
        clearSelection()
        lastClick = nil
        pressedURL = nil
        selectionDragged = false
        setScrollbarHover(target.scrollView)
        scrollbarDrag = ScrollbarDrag(
            scrollView: target.scrollView,
            grabOffset: event.y - target.geometry.thumbTop
        )
        return true
    }

    private func stopScrollbarDrag() {
        scrollbarDrag = nil
    }

    private func scrollSelectionPoint(scrollView: ScrollView, x: Int, y: Int) -> SelectionPoint? {
        guard let currentLayout,
              let box = getScrollViewBox(frame: currentLayout, scrollView: scrollView),
              box.rect.height > 0,
              box.clip.height > 0 else {
            return nil
        }
        let visibleTop = max(0, box.rect.y, box.clip.y)
        let visibleBottom = min(
            terminal.rows - 1,
            box.rect.y + box.rect.height - 1,
            box.clip.y + box.clip.height - 1
        )
        guard visibleBottom >= visibleTop else { return nil }
        let pointerRow = max(visibleTop, min(visibleBottom, y))
        let maxContentRow = max(0, (box.scrollContentLines?.count ?? 1) - 1)
        return SelectionPoint(
            row: max(0, min(maxContentRow, scrollView.scrollTop + pointerRow - box.rect.y)),
            col: max(0, min(box.rect.width - 1, x - box.rect.x)),
            scrollView: scrollView
        )
    }

    private func selectionPoint(for event: SgrMouseEvent, scrollView: ScrollView?) -> SelectionPoint {
        if let scrollView,
           let point = scrollSelectionPoint(scrollView: scrollView, x: event.x, y: event.y) {
            return point
        }
        return SelectionPoint(
            row: max(0, min(terminal.rows - 1, event.y)),
            col: max(0, min(terminal.columns - 1, event.x))
        )
    }

    private func selectionSourceLine(_ point: SelectionPoint) -> String {
        if let scrollView = point.scrollView,
           let currentLayout,
           let lines = getScrollViewBox(frame: currentLayout, scrollView: scrollView)?.scrollContentLines {
            return lines.indices.contains(point.row) ? lines[point.row] : ""
        }
        return previousScreen.indices.contains(point.row) ? previousScreen[point.row] : ""
    }

    private enum WordClass: Equatable {
        case whitespace
        case punctuation
        case word
    }

    private func wordSelection(_ point: SelectionPoint) -> SelectionRange? {
        let line = stripTerminalSequences(selectionSourceLine(point))
        var segments: [(start: Int, end: Int, kind: WordClass)] = []
        var column = 0
        for character in line {
            let width = visibleWidth(String(character))
            let kind: WordClass
            if isWhitespaceChar(character) {
                kind = .whitespace
            } else if isPunctuationChar(character) {
                kind = .punctuation
            } else {
                kind = .word
            }
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].end += width
            } else {
                segments.append((column, column + width, kind))
            }
            column += width
        }
        guard let segment = segments.first(where: { point.col >= $0.start && point.col < $0.end }) else {
            return nil
        }
        var end = point
        end.col = segment.end
        end.boundary = true
        var start = point
        start.col = segment.start
        return SelectionRange(start: start, end: end)
    }

    /// Upstream's triple-click granularity is a single line (`getLineSelection`, granularity
    /// "line"), despite the changelog wording of "paragraph". Match the source, not the changelog.
    private func lineSelection(_ point: SelectionPoint) -> SelectionRange {
        let source: [String]
        if let scrollView = point.scrollView,
           let currentLayout,
           let lines = getScrollViewBox(frame: currentLayout, scrollView: scrollView)?.scrollContentLines {
            source = lines
        } else {
            source = previousScreen
        }
        let row = max(0, min(max(0, source.count - 1), point.row))
        var start = point
        start.row = row
        start.col = 0
        var end = point
        end.row = row
        end.col = source.indices.contains(row) ? visibleWidth(source[row]) : 0
        end.boundary = true
        return SelectionRange(start: start, end: end)
    }

    private func updateSelectionFocus(_ point: SelectionPoint) {
        guard selectionGranularity != .character, let initial = selectionInitialRange else {
            selectionFocus = point
            return
        }
        let range: SelectionRange?
        switch selectionGranularity {
        case .word: range = wordSelection(point)
        case .line: range = lineSelection(point)
        case .character: range = nil
        }
        guard let range else { return }
        let before = range.start.row < initial.start.row
            || (range.start.row == initial.start.row && range.start.col < initial.start.col)
        if before {
            selectionAnchor = initial.end
            selectionFocus = range.start
        } else {
            selectionAnchor = initial.start
            selectionFocus = range.end
        }
    }

    private func clickCount(point: SelectionPoint, word: SelectionRange?) -> Int {
        let now = Date.timeIntervalSinceReferenceDate * 1_000
        let count: Int
        if let word, let previous = lastClick,
           now - previous.timestamp <= doubleClickIntervalMilliseconds,
           previous.row == point.row,
           previous.scrollView === point.scrollView,
           previous.wordStart == word.start.col,
           previous.wordEnd == word.end.col {
            count = previous.count % 3 + 1
        } else {
            count = 1
        }
        if let word {
            lastClick = ClickTarget(
                timestamp: now,
                count: count,
                row: point.row,
                scrollView: point.scrollView,
                wordStart: word.start.col,
                wordEnd: word.end.col
            )
        } else {
            lastClick = nil
        }
        return count
    }

    private func updateSelectionAutoScroll(_ event: SgrMouseEvent) {
        guard let scrollView = selectionAnchor?.scrollView,
              let currentLayout,
              let box = getScrollViewBox(frame: currentLayout, scrollView: scrollView),
              box.rect.height > 0,
              box.clip.height > 0 else {
            stopSelectionAutoScroll()
            return
        }
        let visibleTop = max(0, box.rect.y, box.clip.y)
        let visibleBottom = min(
            terminal.rows - 1,
            box.rect.y + box.rect.height - 1,
            box.clip.y + box.clip.height - 1
        )
        selectionDragPointer = (event.x, event.y)
        selectionAutoScrollDirection = event.y <= visibleTop ? -1 : event.y >= visibleBottom ? 1 : 0
        if selectionAutoScrollDirection == 0 {
            stopSelectionAutoScroll()
            return
        }
        guard selectionAutoScrollTask == nil else { return }
        selectionAutoScrollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                if !self.autoScrollSelection() { return }
            }
        }
    }

    @discardableResult
    private func autoScrollSelection() -> Bool {
        guard let scrollView = selectionAnchor?.scrollView,
              let pointer = selectionDragPointer,
              selectionAutoScrollDirection != 0 else {
            stopSelectionAutoScroll()
            return false
        }
        let direction = selectionAutoScrollDirection
        let remaining = scrollView.scrollBy(direction)
        if remaining == direction {
            stopSelectionAutoScroll()
            return false
        }
        if let point = scrollSelectionPoint(scrollView: scrollView, x: pointer.x, y: pointer.y) {
            updateSelectionFocus(point)
        }
        requestRender()
        return true
    }

    private func stopSelectionAutoScroll() {
        selectionAutoScrollTask?.cancel()
        selectionAutoScrollTask = nil
        selectionAutoScrollDirection = 0
        selectionDragPointer = nil
    }

    private func handleSelectionMouseEvent(_ event: SgrMouseEvent) {
        guard event.button == .primary else { return }
        let anchorScrollView = selectionAnchor?.scrollView
        let point = selectionPoint(for: event, scrollView: anchorScrollView)
        if event.release {
            guard selectionPressActive else { return }
            selectionPressActive = false
            stopSelectionAutoScroll()
            guard selectionAnchor != nil else { return }
            updateSelectionFocus(point)
            let clickedURL = !selectionDragged
                && selectionAnchor?.scrollView === point.scrollView
                && selectionAnchor?.row == point.row
                && selectionAnchor?.col == point.col
                ? pressedURL
                : nil
            pressedURL = nil
            if let clickedURL, let openURL = options.openURL {
                clearSelection()
                openURL(clickedURL)
                requestRender()
                return
            }
            copySelectionToClipboard()
            requestRender()
            return
        }
        if event.motion {
            guard selectionPressActive, selectionAnchor != nil else { return }
            selectionDragged = true
            lastClick = nil
            pressedURL = nil
            updateSelectionFocus(point)
            updateSelectionAutoScroll(event)
            requestRender()
            return
        }

        stopSelectionAutoScroll()
        selectionPressActive = true
        let scrollView = !hasOverlayCallback() && currentLayout != nil
            ? getScrollViewsAt(frame: currentLayout!, x: event.x, y: event.y).first
            : nil
        let anchor = selectionPoint(for: event, scrollView: scrollView)
        let word = wordSelection(anchor)
        let count = clickCount(point: anchor, word: word)
        let range: SelectionRange?
        if count == 2 {
            range = word
            selectionGranularity = .word
        } else if count == 3 {
            range = lineSelection(anchor)
            selectionGranularity = .line
        } else {
            range = nil
            selectionGranularity = .character
        }
        selectionInitialRange = range
        selectionAnchor = range?.start ?? anchor
        selectionFocus = range?.end ?? anchor
        selectionDragged = false
        if range == nil {
            let row = max(0, min(terminal.rows - 1, event.y))
            let col = max(0, min(terminal.columns - 1, event.x))
            let line = previousScreen.indices.contains(row) ? previousScreen[row] : ""
            pressedURL = osc8URL(in: line, at: col)
        } else {
            pressedURL = nil
        }
        requestRender()
    }

    private func osc8URL(in line: String, at targetColumn: Int) -> String? {
        var activeURL: String?
        var column = 0
        var index = 0
        while index < line.count {
            if let ansi = extractAnsiCode(line, at: index) {
                if ansi.code.hasPrefix("\u{001B}]8;") {
                    let terminatorLength = ansi.code.hasSuffix("\u{0007}") ? 1 : 2
                    let bodyLength = max(0, ansi.code.count - 4 - terminatorLength)
                    let body = ansi.code.substring(from: 4, length: bodyLength)
                    if let separator = body.firstIndex(of: ";") {
                        let url = String(body[body.index(after: separator)...])
                        activeURL = url.isEmpty ? nil : url
                    }
                }
                index += ansi.length
                continue
            }
            let character = line[line.index(line.startIndex, offsetBy: index)]
            let width = visibleWidth(String(character))
            if width > 0, targetColumn >= column, targetColumn < column + width {
                return activeURL
            }
            column += width
            index += 1
        }
        return nil
    }

    private func selectionBounds() -> SelectionRange? {
        guard let anchor = selectionAnchor, let focus = selectionFocus,
              anchor.scrollView === focus.scrollView,
              anchor.row != focus.row || anchor.col != focus.col else {
            return nil
        }
        let anchorFirst = anchor.row < focus.row || (anchor.row == focus.row && anchor.col < focus.col)
        return anchorFirst
            ? SelectionRange(start: anchor, end: focus)
            : SelectionRange(start: focus, end: anchor)
    }

    private func selectionColumns(
        line: String,
        row: Int,
        selection: SelectionRange,
        minColumn: Int = 0,
        maxColumn: Int? = nil
    ) -> (start: Int, end: Int) {
        let lineWidth = visibleWidth(line)
        let upper = maxColumn ?? lineWidth
        var start = max(0, minColumn)
        var end = min(lineWidth, upper)
        if row == selection.start.row {
            start = getGraphemeCellRange(line: line, column: selection.start.col)?.start
                ?? min(selection.start.col, lineWidth)
        }
        if row == selection.end.row {
            end = selection.end.boundary
                ? min(selection.end.col, lineWidth)
                : (getGraphemeCellRange(line: line, column: selection.end.col)?.end
                    ?? min(selection.end.col + 1, lineWidth))
        }
        return (max(minColumn, start), min(upper, end))
    }

    private func selectedText() -> String? {
        guard let selection = selectionBounds() else { return nil }
        let source: [String]
        if let scrollView = selection.start.scrollView,
           let currentLayout,
           let lines = getScrollViewBox(frame: currentLayout, scrollView: scrollView)?.scrollContentLines {
            source = lines
        } else {
            source = previousScreen
        }
        var result: [String] = []
        for row in selection.start.row...selection.end.row {
            let line = source.indices.contains(row) ? source[row] : ""
            let columns = selectionColumns(line: line, row: row, selection: selection)
            let slice = sliceByColumn(
                line,
                startCol: columns.start,
                length: max(0, columns.end - columns.start),
                strict: true
            )
            result.append(stripTerminalSequences(slice).trimmingCharacters(in: .whitespaces))
        }
        let text = result.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private func copySelectionToClipboard() {
        guard let text = selectedText() else { return }
        let encoded = Data(text.utf8).base64EncodedString()
        terminal.write("\u{001B}]52;c;" + encoded + "\u{0007}")
        flash("Copied!")
    }

    private func highlighted(_ text: String) -> String {
        var result = "\u{001B}[7m"
        var index = 0
        while index < text.count {
            if let ansi = extractAnsiCode(text, at: index) {
                result += ansi.code
                if ansi.code.hasSuffix("m") { result += "\u{001B}[7m" }
                index += ansi.length
            } else {
                result.append(text[text.index(text.startIndex, offsetBy: index)])
                index += 1
            }
        }
        return result + "\u{001B}[27m"
    }

    private func applySelection(to screen: [String], layout: LayoutFrame?) -> [String] {
        guard let selection = selectionBounds() else { return screen }
        var screenSelection = selection
        var minRow = 0
        var maxRow = screen.count - 1
        var minColumn = 0
        var maxColumn = terminal.columns
        if let scrollView = selection.start.scrollView {
            guard let layout,
                  let box = getScrollViewBox(frame: layout, scrollView: scrollView) else {
                return screen
            }
            minRow = max(0, box.rect.y, box.clip.y)
            maxRow = min(
                screen.count - 1,
                box.rect.y + box.rect.height - 1,
                box.clip.y + box.clip.height - 1
            )
            minColumn = max(0, box.rect.x, box.clip.x)
            maxColumn = min(
                terminal.columns,
                box.rect.x + box.rect.width,
                box.clip.x + box.clip.width
            )
            screenSelection.start.row = box.rect.y + selection.start.row - scrollView.scrollTop
            screenSelection.start.col = box.rect.x + selection.start.col
            screenSelection.end.row = box.rect.y + selection.end.row - scrollView.scrollTop
            screenSelection.end.col = box.rect.x + selection.end.col
        }
        return screen.enumerated().map { row, line in
            guard row >= minRow, row <= maxRow,
                  row >= screenSelection.start.row, row <= screenSelection.end.row,
                  !isImageLine(line) else {
                return line
            }
            let lineWidth = visibleWidth(line)
            let columns = selectionColumns(
                line: line,
                row: row,
                selection: screenSelection,
                minColumn: minColumn,
                maxColumn: maxColumn
            )
            guard columns.end > columns.start else { return line }
            let before = sliceByColumn(line, startCol: 0, length: columns.start, strict: true)
            let selected = sliceByColumn(
                line,
                startCol: columns.start,
                length: columns.end - columns.start,
                strict: true
            )
            let after = sliceByColumn(
                line,
                startCol: columns.end,
                length: max(0, lineWidth - columns.end),
                strict: true
            )
            return before + highlighted(selected) + after
        }
    }

    private func isMouseSequence(_ data: String) -> Bool {
        if data.hasPrefix("\u{001B}[<"), let last = data.last, last == "M" || last == "m" {
            return true
        }
        let scalars = Array(data.unicodeScalars)
        return scalars.count == 6
            && scalars[0].value == 0x1B
            && scalars[1] == "["
            && scalars[2] == "M"
    }

    private func compositeFlashes(on screen: [String], width: Int, height: Int) -> [String] {
        let flashLines = Array(flashes.render(width: width).suffix(height))
        guard !flashLines.isEmpty else { return screen }
        var result = screen
        while result.count < height { result.append("") }
        for row in flashLines.indices {
            let line = flashLines[row]
            let flashWidth = visibleWidth(line)
            guard flashWidth > 0 else { continue }
            let start = max(0, width - flashWidth)
            let before = sliceByColumn(result[row], startCol: 0, length: start, strict: true)
            let beforePadding = String(repeating: " ", count: max(0, start - visibleWidth(before)))
            result[row] = before + beforePadding + line
        }
        return result
    }

    private func deleteKittyImages() -> String {
        imageProtocol == .kitty ? deleteAllKittyImages() : ""
    }

    private func prepareKittyScreen(_ screen: [String]) -> (lines: [String], evictedImageDeletion: String) {
        let maxOffscreenImages = 16
        let maxTransmissionBytes = 32 * 1_024 * 1_024
        let maxDecodedBytes = 64 * 1_024 * 1_024
        var visible: Set<UInt32> = []
        let lines = screen.map { line -> String in
            guard let placement = getKittyImagePlacement(line) else { return line }
            visible.insert(placement.imageID)
            let cached = uploadedKittyImages.removeValue(forKey: placement.imageID)
            uploadedKittyImages[placement.imageID] = CachedKittyImage(
                transmissionGeneration: placement.transmissionGeneration,
                transmissionBytes: placement.transmissionBytes,
                estimatedDecodedBytes: placement.estimatedDecodedBytes
            )
            return cached?.transmissionGeneration == placement.transmissionGeneration
                ? placement.replacementLine
                : line
        }

        func offscreenTotals() -> (count: Int, transmission: Int, decoded: Int) {
            var count = 0
            var transmission = 0
            var decoded = 0
            for (id, image) in uploadedKittyImages where !visible.contains(id) {
                count += 1
                transmission += image.transmissionBytes
                decoded += image.estimatedDecodedBytes
            }
            return (count, transmission, decoded)
        }

        var totals = offscreenTotals()
        var deletion = ""
        for id in Array(uploadedKittyImages.keys) {
            if totals.count <= maxOffscreenImages,
               totals.transmission <= maxTransmissionBytes,
               totals.decoded <= maxDecodedBytes {
                break
            }
            if visible.contains(id) { continue }
            guard let image = uploadedKittyImages[id] else { continue }
            deletion += deleteKittyImage(imageId: id)
            uploadedKittyImages.removeValue(forKey: id)
            totals.count -= 1
            totals.transmission -= image.transmissionBytes
            totals.decoded -= image.estimatedDecodedBytes
        }
        return (lines, deletion)
    }
}
