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
    /// When true, the overlay is displayed but doesn't capture keyboard focus.
    /// Input continues to go to the component underneath. Useful for status
    /// overlays, notifications, or background panels.
    public var nonCapturing: Bool?

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
        visible: (@Sendable (Int, Int) -> Bool)? = nil,
        nonCapturing: Bool? = nil
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
        self.nonCapturing = nonCapturing
    }
}

public struct OverlayBounds: Sendable, Equatable {
    public var row: Int
    public var col: Int
    public var width: Int
    public var height: Int
    public init(row: Int, col: Int, width: Int, height: Int) {
        self.row = row; self.col = col; self.width = width; self.height = height
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

    /// Return the last rendered bounds while this overlay is present and visible.
    public func getBounds() -> OverlayBounds? { tui?.overlayBounds(entry) }

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
    /// The screen that the active renderer controls.
    public var mode: TuiMode { activeRenderer.mode }

    private var activeRenderer: any TuiRenderer
    private var renderers: [TuiMode: any TuiRenderer]
    private var focusedComponent: Component?

    /// Optional handler for Shift+Ctrl+D debug trigger.
    public var onDebug: (() -> Void)?
    /// Optional handler for global input before focused component handling.
    /// Return true to stop propagation to the focused component.
    public var onGlobalInput: ((String) -> Bool)?
    /// When true, show and position the terminal cursor instead of rendering a custom cursor.
    public var useSystemCursor = false {
        didSet {
            updateCursorMode()
        }
    }
    /// When true, record line origin metadata for debugging overlong lines.
    public var debugLineOrigins = false

    private var renderRequested = false
    private var stopped = false
    private var terminalStarted = false
    private var inputBuffer = ""
    private var cellSizeQueryPending = false
    private var terminalColorSchemeListeners: [UUID: (TerminalColorScheme) -> Void] = [:]
    private var pendingDeviceAttributesQueries: [DeviceAttributesQuery] = []
    private var programStatus = ProgramStatusNegotiation()
    /// Supply PI_PROGRAM_STATUS. The default reads the process environment at start.
    public var programStatusEnvironment: () -> String? = {
        ProcessInfo.processInfo.environment["PI_PROGRAM_STATUS"]
    }

    private enum DeviceAttributesQuery {
        case colors(TerminalColorQuery)
        case programStatus(stale: Bool)
    }
    private var terminalColorSchemeNotificationsEnabled = false
    private var clearOnShrink = false
    /// v0.70.5: rate-limit renders to ~60Hz so streaming token bursts don't redraw faster
    /// than terminals can repaint. `lastRenderAt` is updated each time `doRender()` actually
    /// runs, and `pendingRenderTask` holds the throttled follow-up if a render is requested
    /// during the throttle window.
    private static let minRenderIntervalMs: Double = 16
    private var lastRenderAt: DispatchTime = .now()
    private var pendingRenderTask: Task<Void, Never>?
    private var renderCompletionContinuations: [CheckedContinuation<Void, Never>] = []
    private var overlayStack: [OverlayEntry] = []
    private var renderedOverlayLayouts: [(entry: OverlayEntry, bounds: OverlayBounds)] = []
    /// v0.69.0 + v0.70.0: keep-alive timer for OSC 9;4 progress indicator.
    private var progressTimer: DispatchSourceTimer?

    @MainActor private final class TerminalColorQuery {
        var foreground: RgbColor?
        var background: RgbColor?
        var palette: [RgbColor?] = Array(repeating: nil, count: 16)
        var replied: Set<OscColorTarget> = []
        var continuation: CheckedContinuation<TerminalColors, Never>?
        var onLateReply: (@MainActor (TerminalColors) -> Void)?
        var timeoutTask: Task<Void, Never>?
        var complete = false

        var result: TerminalColors {
            TerminalColors(
                foreground: foreground,
                background: background,
                palette: palette.allSatisfy { $0 != nil } ? palette.compactMap { $0 } : nil
            )
        }

        func finish() {
            guard !complete else { return }
            complete = true
            timeoutTask?.cancel()
            timeoutTask = nil
            if let continuation {
                self.continuation = nil
                continuation.resume(returning: result)
            } else {
                onLateReply?(result)
            }
            onLateReply = nil
        }
    }

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
        var bounds: OverlayBounds?

        init(component: Component, options: OverlayOptions?, preFocus: Component?, hidden: Bool) {
            self.component = component
            self.options = options
            self.preFocus = preFocus
            self.hidden = hidden
        }
    }

    /// Create a TUI bound to a terminal.
    public init(terminal: Terminal, showHardwareCursor: Bool = false, logDirectory: String? = nil) {
        let renderer = MainScreenRenderer(terminal: terminal, logDirectory: logDirectory)
        self.useSystemCursor = showHardwareCursor
        self.terminal = terminal
        self.activeRenderer = renderer
        self.renderers = [.mainScreen: renderer]
        super.init()
        renderer.setRenderFailureHandler { [weak self] in
            self?.stop()
        }
    }

    /// Register a renderer that can become active in a later mode switch.
    public func registerRenderer(_ renderer: any TuiRenderer) {
        if let renderer = renderer as? MainScreenRenderer {
            renderer.setRenderFailureHandler { [weak self] in
                self?.stop()
            }
        }
        if let renderer = renderer as? any TuiHostedRenderer {
            renderer.attach(
                root: self,
                requestRender: { [weak self] in self?.requestRender() },
                hasOverlay: { [weak self] in self?.hasOverlay() ?? false }
            )
        }
        renderers[renderer.mode] = renderer
    }

    /// Create and register an alternate-screen renderer.
    @discardableResult
    public func enableAltScreen(options: AltScreenRendererOptions = AltScreenRendererOptions()) -> AltScreenRenderer {
        let renderer = AltScreenRenderer(terminal: terminal, options: options)
        registerRenderer(renderer)
        return renderer
    }

    /// Switch to a registered renderer. Return false if the mode is not registered.
    @discardableResult
    public func switchRenderer(to mode: TuiMode) -> Bool {
        guard let nextRenderer = renderers[mode] else { return false }
        guard nextRenderer !== activeRenderer else { return true }

        if terminalStarted {
            activeRenderer.stop(preserveScreen: true)
        }
        nextRenderer.takeOverRenderState(from: activeRenderer)
        activeRenderer = nextRenderer
        invalidate()
        if terminalStarted {
            activeRenderer.start()
            requestRender()
        }
        return true
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
    public func getFocusedComponent() -> Component? { focusedComponent }

    public func setFocus(_ component: Component?) {
        (focusedComponent as? any Focusable)?.focused = false
        (component as? any Focusable)?.focused = true
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
        // Non-capturing overlays don't steal focus
        if isOverlayVisible(entry) && !(options?.nonCapturing == true) {
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
        } else if isOverlayVisible(entry) && !(entry.options?.nonCapturing == true) {
            setFocus(entry.component)
        }
        updateCursorMode()
        requestRender()
    }

    fileprivate func overlayBounds(_ entry: OverlayEntry) -> OverlayBounds? {
        guard overlayStack.contains(where: { $0 === entry }), isOverlayVisible(entry) else { return nil }
        return entry.bounds
    }

    public func isOverlayFocused() -> Bool {
        overlayStack.contains { $0.component === focusedComponent && isOverlayVisible($0) }
    }

    public func resolveMouseFocusTarget(_ component: any Component) -> any Component {
        func contains(_ root: any Component, _ target: any Component) -> Bool {
            if root === target { return true }
            let children = (root as? Container)?.children ?? (root as? Box)?.children ?? []
            return children.contains { contains($0, target) }
        }
        for entry in overlayStack.reversed() where isOverlayVisible(entry) {
            if contains(entry.component, component) { return entry.component }
        }
        return component
    }

    public func dispatchMouseToOverlay(_ event: TuiMouseEvent) -> (hit: Bool, result: TuiMouseDispatchResult?) {
        for (entry, bounds) in renderedOverlayLayouts.reversed() {
            guard event.screenX >= bounds.col, event.screenX < bounds.col + bounds.width,
                  event.screenY >= bounds.row, event.screenY < bounds.row + bounds.height else { continue }
            var local = event
            local.x = event.screenX - bounds.col; local.y = event.screenY - bounds.row
            local.width = bounds.width; local.height = bounds.height
            let result = dispatchMouseEvent(entry.component, local)
            return (true, result?.focus == true ? result?.withFocusTarget(entry.component) : result)
        }
        return (false, nil)
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
            // Skip non-capturing overlays when finding focus target
            if isOverlayVisible(entry) && !(entry.options?.nonCapturing == true) {
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

    /// v0.69.0 + v0.70.0: toggle the OSC 9;4 progress indicator. While active, the indicator
    /// is refreshed periodically so terminals like Ghostty don't time it out during long runs.
    /// Pass `false` to clear; idempotent.
    public func setProgress(_ active: Bool) {
        if active {
            if progressTimer != nil { return }
            terminal.setProgress(true)
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
            // Refresh every ~5s. Long enough to avoid spamming the terminal, short enough that
            // Ghostty (which expires the indicator on idle) keeps showing the activity.
            timer.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5))
            timer.setEventHandler { [weak self] in
                self?.terminal.setProgress(true)
            }
            timer.resume()
            progressTimer = timer
        } else {
            progressTimer?.cancel()
            progressTimer = nil
            terminal.setProgress(false)
        }
    }

    /// Clear stale scrollback state, useful when switching sessions.
    public func clearScrollback() {
        activeRenderer.clearRenderState()
        terminal.clearScreen()
        requestRender(force: true)
    }

    /// Set or remove the terminal I/O error callback. It can run on an I/O queue.
    public func setIOErrorHandler(_ handler: (@Sendable (TerminalIOError) -> Void)?) {
        terminal.setIOErrorHandler(handler)
    }

    /// Store the latest status and report it when the terminal has confirmed support.
    public func setProgramStatus(_ status: ProgramStatus) {
        let bytes = programStatus.set(status)
        if canWriteProgramStatus, !bytes.isEmpty { terminal.write(bytes) }
    }

    private var canWriteProgramStatus: Bool {
        terminalStarted && !stopped && terminal.supportsTerminalQueries
            && (terminal as? ProcessTerminal)?.isLost != true
    }

    /// Start terminal input and initial rendering.
    public func start() {
        stopped = false
        activeRenderer.start()
        terminal.start(onInput: { [weak self] data in
            Task { @MainActor in
                self?.handleTerminalInput(data)
            }
        }, onResize: { [weak self] in
            Task { @MainActor in
                self?.requestRender()
            }
        })
        terminalStarted = true
        if canWriteProgramStatus {
            let bytes = programStatus.start(environmentValue: programStatusEnvironment())
            if programStatus.queryPending {
                pendingDeviceAttributesQueries.append(.programStatus(stale: false))
                terminal.write(bytes + "\u{001B}[c")
            } else if !bytes.isEmpty {
                terminal.write(bytes)
            }
        }
        updateCursorMode()
        if terminalColorSchemeNotificationsEnabled {
            terminal.write("\u{001B}[?2031h")
        }
        queryCellSize()
        requestRender()
    }

    /// Stop terminal input and restore terminal state.
    public func stop() {
        let canClearProgramStatus = canWriteProgramStatus
        stopped = true
        for index in pendingDeviceAttributesQueries.indices {
            if case .programStatus = pendingDeviceAttributesQueries[index] {
                pendingDeviceAttributesQueries[index] = .programStatus(stale: true)
            }
        }
        // Clear OSC 9;4 progress indicator on shutdown so the host terminal doesn't keep
        // showing activity after pi exits.
        progressTimer?.cancel()
        progressTimer = nil
        terminal.setProgress(false)
        let clearStatus = programStatus.stop()
        if canClearProgramStatus, ((terminal as? ProcessTerminal)?.isLost != true), !clearStatus.isEmpty {
            terminal.write(clearStatus)
        }
        if terminalColorSchemeNotificationsEnabled {
            terminal.write("\u{001B}[?2031l")
        }
        activeRenderer.stop(preserveScreen: false)
        terminal.showCursor()
        terminal.stop()
        terminalStarted = false
    }

    /// Request a render, optionally forcing a full redraw. v0.70.5: renders are throttled to
    /// `minRenderIntervalMs` (~60Hz) — burst requests during the throttle window collapse into
    /// a single follow-up render at the end of the window. Force-renders skip the throttle.
    public func requestRender(force: Bool = false) {
        if stopped { return }
        if force {
            activeRenderer.invalidateRenderState()
            pendingRenderTask?.cancel()
            pendingRenderTask = nil
            renderRequested = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.stopped || !self.renderRequested { return }
                self.renderRequested = false
                self.lastRenderAt = .now()
                self.doRender()
                self.flushRenderCompletionContinuations()
            }
            return
        }
        if renderRequested { return }
        renderRequested = true
        scheduleRender()
    }

    @MainActor
    private func scheduleRender() {
        if stopped || !renderRequested || pendingRenderTask != nil { return }
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds &- lastRenderAt.uptimeNanoseconds) / 1_000_000
        let delayMs = max(0, TUI.minRenderIntervalMs - elapsedMs)
        if delayMs == 0 {
            // Cache stays warm with a microtask-style yield so synchronous requestRender bursts
            // collapse into a single render rather than each spawning their own task.
            Task { @MainActor [weak self] in
                guard let self, !self.stopped, self.renderRequested else { return }
                self.renderRequested = false
                self.lastRenderAt = .now()
                self.doRender()
                self.flushRenderCompletionContinuations()
                if self.renderRequested { self.scheduleRender() }
            }
            return
        }
        pendingRenderTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delayMs * 1_000_000))
            guard let self, !Task.isCancelled else { return }
            self.pendingRenderTask = nil
            if self.stopped || !self.renderRequested { return }
            self.renderRequested = false
            self.lastRenderAt = .now()
            self.doRender()
            self.flushRenderCompletionContinuations()
            if self.renderRequested { self.scheduleRender() }
        }
    }

    /// v0.70.5: suspend until any in-flight render completes. Used by tests that drive the TUI
    /// imperatively and need the pixel state to settle before asserting on `previousLines`.
    public func waitForRender() async {
        if !renderRequested && pendingRenderTask == nil { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            renderCompletionContinuations.append(continuation)
        }
    }

    @MainActor
    private func flushRenderCompletionContinuations() {
        let continuations = renderCompletionContinuations
        renderCompletionContinuations = []
        for cont in continuations {
            cont.resume()
        }
    }

    private func handleTerminalInput(_ data: String) {
        var input = data

        while !input.isEmpty {
            let afterProgramStatus = consumeProgramStatusReplyPrefix(input)
            if afterProgramStatus.count != input.count {
                input = afterProgramStatus
                continue
            }
            let afterColorResponse = consumeTerminalColorResponsePrefix(input)
            if afterColorResponse.count != input.count {
                input = afterColorResponse
                continue
            }

            let afterColorScheme = consumeTerminalColorSchemeReportPrefix(input)
            if afterColorScheme.count != input.count {
                input = afterColorScheme
                continue
            }
            break
        }
        if input.isEmpty {
            return
        }

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

        if let inputRenderer = activeRenderer as? any TuiInputRenderer,
           inputRenderer.handleInput(input) {
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

    /// Subscribe to terminal color-scheme reports. Returns an unsubscribe closure.
    @discardableResult
    public func onTerminalColorSchemeChange(_ listener: @escaping (TerminalColorScheme) -> Void) -> () -> Void {
        let id = UUID()
        terminalColorSchemeListeners[id] = listener
        return { [weak self] in
            Task { @MainActor in
                self?.terminalColorSchemeListeners[id] = nil
            }
        }
    }

    /// Enable or disable terminal color-scheme change notifications.
    public func setTerminalColorSchemeNotifications(_ enabled: Bool) {
        guard terminalColorSchemeNotificationsEnabled != enabled else { return }
        terminalColorSchemeNotificationsEnabled = enabled
        if !stopped {
            terminal.write(enabled ? "\u{001B}[?2031h" : "\u{001B}[?2031l")
        }
    }

    /// Query the default foreground, background, and ANSI colors 0 through 15.
    /// The terminal's DA1 reply ends the query. A timeout returns the colors received so far.
    /// If more replies arrive, `onLateReply` receives the completed result.
    public func queryTerminalColors(
        timeoutMs: Int,
        onLateReply: (@MainActor (TerminalColors) -> Void)? = nil
    ) async -> TerminalColors {
        let query = TerminalColorQuery()
        query.onLateReply = onLateReply
        return await withCheckedContinuation { continuation in
            query.continuation = continuation
            let milliseconds = max(0, timeoutMs)
            let nanoseconds = UInt64(milliseconds) * 1_000_000
            query.timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled, let continuation = query.continuation else { return }
                query.continuation = nil
                continuation.resume(returning: query.result)
            }
            pendingDeviceAttributesQueries.append(.colors(query))
            let paletteRequests = (0..<16).map { "\u{001B}]4;\($0);?\u{0007}" }.joined()
            terminal.write("\u{001B}]10;?\u{0007}\u{001B}]11;?\u{0007}" + paletteRequests + "\u{001B}[c")
        }
    }

    private func consumeTerminalColorSchemeReportPrefix(_ data: String) -> String {
        guard let report = parseTerminalColorSchemeReportPrefix(data) else { return data }
        let listeners = Array(terminalColorSchemeListeners.values)
        for listener in listeners {
            listener(report.scheme)
        }
        return data.substring(from: report.length, length: data.count - report.length)
    }

    private func consumeProgramStatusReplyPrefix(_ data: String) -> String {
        guard data.utf8.starts(with: "\u{001B}]7501;?".utf8) else { return data }
        let scalars = data.unicodeScalars
        for index in scalars.indices.dropFirst(8) {
            let end: String.Index
            if scalars[index].value == 7 {
                end = scalars.index(after: index)
            } else if scalars[index].value == 27 {
                let next = scalars.index(after: index)
                guard next != scalars.endIndex, scalars[next].value == 92 else { return data }
                end = scalars.index(after: next)
            } else {
                continue
            }
            guard isProgramStatusReply(String(data[..<end])) else { return data }
            if canWriteProgramStatus {
                let bytes = programStatus.receiveReply()
                if !bytes.isEmpty { terminal.write(bytes) }
            }
            return String(data[end...])
        }
        return data
    }

    private func consumeTerminalColorResponsePrefix(_ data: String) -> String {
        if !pendingDeviceAttributesQueries.isEmpty, let length = parseDeviceAttributesResponsePrefix(data) {
            switch pendingDeviceAttributesQueries.removeFirst() {
            case .colors(let query): query.finish()
            case .programStatus(let stale): _ = programStatus.endQuery(isStale: stale)
            }
            return data.substring(from: length, length: data.count - length)
        }
        guard let query = pendingDeviceAttributesQueries.lazy.compactMap({ entry -> TerminalColorQuery? in
            if case .colors(let query) = entry { return query }
            return nil
        }).first, let response = parseOscColorResponsePrefix(data) else { return data }
        if !query.complete, query.replied.insert(response.target).inserted {
            switch response.target {
            case .foreground:
                query.foreground = response.rgb
            case .background:
                query.background = response.rgb
            case .palette(let index):
                if index < 16 { query.palette[index] = response.rgb }
            }
            if query.replied.count == 18 { query.finish() }
        }
        return data.substring(from: response.length, length: data.count - response.length)
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

        let partialResponsePattern = "^\\u{001B}\\[6(?:;\\d*){0,2}$"
        if inputBuffer.range(of: partialResponsePattern, options: .regularExpression) != nil {
            return ""
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

    private static let segmentReset = "\u{001B}[0m" + osc8HyperlinkCloseBell

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
        renderedOverlayLayouts = []
        for entry in overlayStack { entry.bounds = nil }
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

            let bounds = OverlayBounds(row: layout.row, col: layout.col, width: layout.width, height: overlayLines.count)
            entry.bounds = bounds
            renderedOverlayLayouts.append((entry, bounds))
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
        var layoutFrame: LayoutFrame?
        var lineOrigins: LineOrigins?
        if let layoutRenderer = activeRenderer as? any TuiLayoutRenderer {
            let nextLayout = layoutRenderer.renderLayout(
                root: self,
                width: width,
                height: height,
                requestRender: { [weak self] in self?.requestRender() }
            )
            layoutFrame = nextLayout
            renderedLines = nextLayout.lines
        } else if debugLineOrigins {
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
        do {
            renderedLines = compositeOverlays(
                renderedLines,
                termWidth: width,
                termHeight: height,
                lineOrigins: lineOrigins
            )
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

        activeRenderer.present(
            TuiRenderFrame(
                lines: cleanedLines,
                cursor: cursorPosition,
                width: width,
                height: height,
                clearOnShrink: clearOnShrink,
                hasOverlayEntries: !overlayStack.isEmpty,
                hasVisibleOverlay: hasOverlay(),
                useSystemCursor: useSystemCursor,
                lineOrigins: debugLineOrigins ? (lineOrigins?.values ?? []) : nil,
                layoutFrame: layoutFrame
            )
        )
    }
    private func updateCursorMode() {
        guard !stopped else { return }
        let overlayActive = hasOverlay()
        let shouldShowSystemCursor = !overlayActive && useSystemCursor && focusedComponent is SystemCursorAware
        if shouldShowSystemCursor {
            terminal.showCursor()
        } else {
            terminal.hideCursor()
            activeRenderer.invalidateCursorState()
        }

        if let focusedComponent = focusedComponent as? SystemCursorAware {
            focusedComponent.usesSystemCursor = useSystemCursor
        }
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
