import Foundation

/// UI building block that can render lines and optionally handle input.
@MainActor
public protocol Component: AnyObject {
    /// Render terminal lines for the given width. The returned array is a value snapshot:
    /// changing a copy does not change the component's cached output. A component that
    /// changes its own content must invalidate its cache and request a render from its host.
    func render(width: Int) -> [String]
    /// Handle raw terminal input when the component is focused.
    func handleInput(_ data: String)
    /// Handle a normalized mouse event. Return nil to leave it unhandled.
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult?
    /// Return true to receive Kitty key release events.
    var wantsKeyRelease: Bool { get }
    /// Return true to receive viewport keys before the fullscreen renderer.
    var capturesViewportInput: Bool { get }
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
    /// Existing components leave viewport keys with the renderer.
    var capturesViewportInput: Bool { false }
    /// Default no-op invalidation.
    func invalidate() {}
}

/// Optional focus state for controls that render a cursor marker.
@MainActor
public protocol Focusable: Component {
    var focused: Bool { get set }
}
