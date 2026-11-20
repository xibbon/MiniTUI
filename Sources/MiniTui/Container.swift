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

/// The last rendered parts and their concatenation for a vertical child list.
@MainActor
struct ChildLines {
    let width: Int
    let children: [any Component]
    let parts: [[String]]
    let lines: [String]
    let generation: Int
}

/// A retained Swift array keeps its buffer alive during this comparison. A cached
/// child therefore needs one buffer comparison; fresh equal output needs N elements.
private func sameLines(_ first: [String], _ second: [String]) -> Bool {
    guard first.count == second.count else { return false }
    if first.isEmpty { return true }
    let sameStorage = first.withUnsafeBufferPointer { firstBuffer in
        second.withUnsafeBufferPointer { secondBuffer in
            firstBuffer.baseAddress == secondBuffer.baseAddress
        }
    }
    return sameStorage || first.elementsEqual(second)
}

@MainActor
func renderChildLines(
    _ children: [any Component], width: Int, previous: ChildLines?,
    render: (any Component) -> [String]
) -> ChildLines {
    let parts = children.map(render)
    if let previous, previous.width == width, previous.children.count == children.count,
       children.indices.allSatisfy({ index in
           children[index] === previous.children[index]
               && sameLines(parts[index], previous.parts[index])
       }) {
        return previous
    }
    var lines: [String] = []
    lines.reserveCapacity(parts.reduce(0) { $0 + $1.count })
    for part in parts { lines.append(contentsOf: part) }
    ChildLinesGeneration.next += 1
    return ChildLines(width: width, children: children, parts: parts, lines: lines,
                      generation: ChildLinesGeneration.next)
}

/// One counter for all records: a record made after its owner dropped the earlier one
/// must not repeat a generation that a cache of that owner still holds.
@MainActor
private enum ChildLinesGeneration {
    static var next = 0
}

@MainActor
func renderChildLines(_ children: [any Component], width: Int, previous: ChildLines?) -> ChildLines {
    renderChildLines(children, width: width, previous: previous) { $0.render(width: width) }
}

@MainActor
func dispatchMouseToChildLines(_ layout: ChildLines, _ event: TuiMouseEvent) -> TuiMouseDispatchResult? {
    var childY = 0
    for index in layout.children.indices {
        let height = layout.parts[index].count
        if event.y >= childY && event.y < childY + height {
            var local = event
            local.y -= childY
            local.height = height
            return dispatchMouseEvent(layout.children[index], local)
        }
        childY += height
    }
    return nil
}

/// Component that composes and renders a list of child components.
open class Container: Component {
    /// Current child components in render order.
    public private(set) var children: [Component] = []

    /// Return true to receive viewport keys before the fullscreen renderer.
    open var capturesViewportInput: Bool { false }

    private var childLines: ChildLines?
    /// Number of child-record rebuilds, for focused reuse tests and measurements.
    internal private(set) var childRecordRebuildCount = 0

    open func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        if LayoutMouseDispatchContext.component === self && self is any LayoutComponent { return nil }
        guard event.y >= 0, event.y < event.height else { return nil }
        let layout = childLines?.width == event.width ? childLines!
            : renderChildLines(children, width: event.width, previous: nil)
        let result = dispatchMouseToChildLines(layout, event)
        if let result, result.focus == true, self is any MouseFocusOwner { return result.withFocusTarget(self) }
        return result
    }

    /// Create an empty container.
    public init() {}

    /// Add a child component to the end of the list.
    public func addChild(_ component: Component) {
        children.append(component)
        childLines = nil
    }

    /// Remove the first matching child component.
    public func removeChild(_ component: Component) {
        if let index = children.firstIndex(where: { $0 === component }) {
            children.remove(at: index)
            childLines = nil
        }
    }

    /// Remove all child components.
    public func clear() {
        children.removeAll()
        childLines = nil
    }

    /// Invalidate all child components.
    open func invalidate() {
        childLines = nil
        for child in children {
            child.invalidate()
        }
    }

    /// Render all children sequentially and concatenate their lines.
    open func render(width: Int) -> [String] {
        let previous = childLines
        if let trace = RenderTrace.active {
            func componentLabel(_ component: AnyObject) -> String {
                "\(type(of: component))@\(ObjectIdentifier(component))"
            }

            trace.push(componentLabel(self))
            defer { trace.pop() }
            childLines = renderChildLines(children, width: width, previous: previous) { child in
                if let container = child as? Container {
                    let originCountBefore = trace.origins.count
                    let childLines = container.render(width: width)
                    let added = trace.origins.count - originCountBefore
                    if added < childLines.count {
                        trace.push(componentLabel(child))
                        trace.recordLines(childLines.count - added)
                        trace.pop()
                    }
                    return childLines
                } else {
                    trace.push(componentLabel(child))
                    let childLines = child.render(width: width)
                    trace.recordLines(childLines.count)
                    trace.pop()
                    return childLines
                }
            }
            if previous?.generation != childLines?.generation {
                childRecordRebuildCount += 1
            }
            return childLines!.lines
        }

        childLines = renderChildLines(children, width: width, previous: previous)
        if previous?.generation != childLines?.generation {
            childRecordRebuildCount += 1
        }
        return childLines!.lines
    }

    /// Default no-op input handler for containers.
    open func handleInput(_ data: String) {}
}
