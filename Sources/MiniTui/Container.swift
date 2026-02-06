import Foundation

@MainActor
final class RenderTrace {
    static var active: RenderTrace?

    private var stack: [String] = []
    private(set) var origins: [String] = []

    func push(_ name: String) {
        stack.append(name)
    }

    func pop() {
        _ = stack.popLast()
    }

    func recordLines(_ count: Int) {
        guard count > 0 else { return }
        let origin = stack.joined(separator: " > ")
        origins.append(contentsOf: repeatElement(origin, count: count))
    }
}

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
    open func invalidate() {
        for child in children {
            child.invalidate()
        }
    }

    /// Render all children sequentially and concatenate their lines.
    public func render(width: Int) -> [String] {
        if let trace = RenderTrace.active {
            func componentLabel(_ component: AnyObject) -> String {
                let ptr = Unmanaged.passUnretained(component).toOpaque()
                return "\(type(of: component))@\(ptr)"
            }

            trace.push(componentLabel(self))
            defer { trace.pop() }
            var lines: [String] = []
            for child in children {
                if let container = child as? Container {
                    let originCountBefore = trace.origins.count
                    let childLines = container.render(width: width)
                    let added = trace.origins.count - originCountBefore
                    if added < childLines.count {
                        trace.push(componentLabel(child))
                        trace.recordLines(childLines.count - added)
                        trace.pop()
                    }
                    lines.append(contentsOf: childLines)
                } else {
                    trace.push(componentLabel(child))
                    let childLines = child.render(width: width)
                    trace.recordLines(childLines.count)
                    trace.pop()
                    lines.append(contentsOf: childLines)
                }
            }
            return lines
        }

        var lines: [String] = []
        for child in children {
            lines.append(contentsOf: child.render(width: width))
        }
        return lines
    }

    /// Default no-op input handler for containers.
    open func handleInput(_ data: String) {}
}
