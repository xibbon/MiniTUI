/// The terminal screen that a renderer controls.
public enum TuiMode: Sendable, Equatable, Hashable {
    case mainScreen
    case altScreen
}

/// A hardware cursor location in the composed document.
public struct CursorPosition: Sendable, Equatable {
    public let row: Int
    public let col: Int

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }
}

/// The composed output and presentation policy for one render cycle.
@MainActor
public struct TuiRenderFrame {
    public let lines: [String]
    public let cursor: CursorPosition?
    public let width: Int
    public let height: Int
    public let clearOnShrink: Bool
    public let hasOverlayEntries: Bool
    public let hasVisibleOverlay: Bool
    public let useSystemCursor: Bool
    public let lineOrigins: [String]?
    /// The constraint-layout result used to paint this frame, when the active
    /// renderer owns a fixed viewport.
    public let layoutFrame: LayoutFrame?

    public init(
        lines: [String],
        cursor: CursorPosition?,
        width: Int,
        height: Int,
        clearOnShrink: Bool,
        hasOverlayEntries: Bool,
        hasVisibleOverlay: Bool,
        useSystemCursor: Bool,
        lineOrigins: [String]? = nil,
        layoutFrame: LayoutFrame? = nil
    ) {
        self.lines = lines
        self.cursor = cursor
        self.width = width
        self.height = height
        self.clearOnShrink = clearOnShrink
        self.hasOverlayEntries = hasOverlayEntries
        self.hasVisibleOverlay = hasVisibleOverlay
        self.useSystemCursor = useSystemCursor
        self.lineOrigins = lineOrigins
        self.layoutFrame = layoutFrame
    }
}

/// Optional renderer refinement for application-owned viewport layout.
///
/// TUI uses this only for renderers that need the layout box tree. Main-screen
/// rendering continues to use the unconstrained component output.
@MainActor
public protocol TuiLayoutRenderer: TuiRenderer {
    func renderLayout(
        root: Component,
        width: Int,
        height: Int,
        requestRender: @escaping () -> Void
    ) -> LayoutFrame
}

/// Optional renderer refinement for input that must be consumed before it can
/// reach a focused component, such as terminal pointer reports.
@MainActor
public protocol TuiInputRenderer: TuiRenderer {
    @discardableResult
    func handleInput(_ data: String) -> Bool
}

/// Optional renderer refinement for services supplied by its owning TUI.
@MainActor
protocol TuiHostedRenderer: TuiRenderer {
    func attach(
        root: Component,
        requestRender: @escaping () -> Void,
        hasOverlay: @escaping () -> Bool
    )
}

/// Presents composed TUI frames on a terminal.
@MainActor
public protocol TuiRenderer: AnyObject {
    var mode: TuiMode { get }

    func start()
    func stop(preserveScreen: Bool)
    func present(_ frame: TuiRenderFrame)

    /// Drop cached differential state for an explicit full render.
    func invalidateRenderState()

    /// Drop the cached hardware cursor location without invalidating line state.
    func invalidateCursorState()

    /// Drop all cached scrollback and differential state.
    func clearRenderState()

    /// Receive render state from the renderer that previously owned the terminal.
    func takeOverRenderState(from previous: any TuiRenderer)
}
