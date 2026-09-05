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

@MainActor
enum LayoutMouseDispatchContext {
    static var component: (any Component)?
}

/// Component that composes and renders a list of child components.
open class Container: Component {
    /// Current child components in render order.
    public private(set) var children: [Component] = []

    private var mouseLayout: (width: Int, children: [(component: any Component, height: Int)])?

    open func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        if LayoutMouseDispatchContext.component === self && self is any LayoutComponent { return nil }
        guard event.y >= 0, event.y < event.height else { return nil }
        let layout = mouseLayout?.width == event.width ? mouseLayout!.children
            : children.map { (component: $0, height: $0.render(width: event.width).count) }
        var childY = 0
        for (child, height) in layout {
            if event.y >= childY && event.y < childY + height {
                var local = event
                local.y -= childY; local.height = height
                let result = dispatchMouseEvent(child, local)
                if let result, result.focus == true, self is any MouseFocusOwner { return result.withFocusTarget(self) }
                return result
            }
            childY += height
        }
        return nil
    }

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
    open func render(width: Int) -> [String] {
        var mouseChildren: [(component: any Component, height: Int)] = []
        defer { mouseLayout = (width, mouseChildren) }
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
                    mouseChildren.append((child, childLines.count))
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
                    mouseChildren.append((child, childLines.count))
                    trace.recordLines(childLines.count)
                    trace.pop()
                    lines.append(contentsOf: childLines)
                }
            }
            return lines
        }

        var lines: [String] = []
        for child in children {
            let childLines = child.render(width: width)
            mouseChildren.append((child, childLines.count))
            lines.append(contentsOf: childLines)
        }
        return lines
    }

    /// Default no-op input handler for containers.
    open func handleInput(_ data: String) {}
}
