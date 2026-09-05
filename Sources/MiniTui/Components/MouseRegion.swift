public typealias MouseRegionHandler = @MainActor (TuiMouseEvent) -> TuiMouseEventResult?

/// Add mouse handling without changing the child's rendered output.
public final class MouseRegion: Component {
    private let child: any Component
    private let onMouse: MouseRegionHandler
    public init(child: any Component, onMouse: @escaping MouseRegionHandler) {
        self.child = child; self.onMouse = onMouse
    }
    public func render(width: Int) -> [String] { child.render(width: width) }
    public func invalidate() { child.invalidate() }
    public func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        dispatchMouseEvent(child, event) ?? onMouse(event)
    }
}
