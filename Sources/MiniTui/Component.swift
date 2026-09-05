import Foundation

/// UI building block that can render lines and optionally handle input.
@MainActor
public protocol Component: AnyObject {
    /// Render the component into an array of terminal lines for the given width.
    func render(width: Int) -> [String]
    /// Handle raw terminal input when the component is focused.
    func handleInput(_ data: String)
    /// Handle a normalized mouse event. Return nil to leave it unhandled.
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult?
    /// Return true to receive Kitty key release events.
    var wantsKeyRelease: Bool { get }
    /// Clear any cached render state.
    func invalidate()
}

public extension Component {
    /// The default keeps existing conformers source compatible and permits generic dispatch.
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? { nil }
    /// Default no-op input handler.
    func handleInput(_ data: String) {}
    /// Default to filtering key release events.
    var wantsKeyRelease: Bool { false }
    /// Default no-op invalidation.
    func invalidate() {}
}

/// Optional focus state for controls that render a cursor marker.
@MainActor
public protocol Focusable: Component {
    var focused: Bool { get set }
}
