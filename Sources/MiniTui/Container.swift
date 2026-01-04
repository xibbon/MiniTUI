import Foundation

/// Component that composes and renders a list of child components.
open class Container: Component {
    /// Current child components in render order.
    public private(set) var children: [Component] = []

    /// Create an empty container.
    public init() {}

    /// Add a child component to the end of the list.
    public func addChild(_ component: Component) {
        children.append(component)
    }

    /// Remove the first matching child component.
    public func removeChild(_ component: Component) {
        if let index = children.firstIndex(where: { $0 === component }) {
            children.remove(at: index)
        }
    }

    /// Remove all child components.
    public func clear() {
        children.removeAll()
    }

    /// Invalidate all child components.
    public func invalidate() {
        for child in children {
            child.invalidate()
        }
    }

    /// Render all children sequentially and concatenate their lines.
    public func render(width: Int) -> [String] {
        var lines: [String] = []
        for child in children {
            lines.append(contentsOf: child.render(width: width))
        }
        return lines
    }

    /// Default no-op input handler for containers.
    open func handleInput(_ data: String) {}
}
