import Foundation

/// UI building block that can render lines and optionally handle input.
public protocol Component: AnyObject {
    /// Render the component into an array of terminal lines for the given width.
    func render(width: Int) -> [String]
    /// Handle raw terminal input when the component is focused.
    func handleInput(_ data: String)
    /// Clear any cached render state.
    func invalidate()
}

public extension Component {
    /// Default no-op input handler.
    func handleInput(_ data: String) {}
    /// Default no-op invalidation.
    func invalidate() {}
}
