/// Mouse gestures use zero-based terminal cell coordinates.
public enum TuiMouseEventType: String, Sendable { case press, release, move, drag, click, wheel }
public enum TuiMouseButton: String, Sendable { case left, middle, right, none }

public struct TuiMouseEvent: Sendable, Equatable {
    public var type: TuiMouseEventType
    public var button: TuiMouseButton
    public var x: Int
    public var y: Int
    public var screenX: Int
    public var screenY: Int
    public var width: Int
    public var height: Int
    public var shift: Bool
    public var alt: Bool
    public var ctrl: Bool
    /// Logical lines. A negative value scrolls up.
    public var wheelDelta: Int?
    public var clickCount: Int?

    public init(type: TuiMouseEventType, button: TuiMouseButton, x: Int, y: Int,
                screenX: Int, screenY: Int, width: Int, height: Int,
                shift: Bool = false, alt: Bool = false, ctrl: Bool = false,
                wheelDelta: Int? = nil, clickCount: Int? = nil) {
        self.type = type; self.button = button; self.x = x; self.y = y
        self.screenX = screenX; self.screenY = screenY; self.width = width; self.height = height
        self.shift = shift; self.alt = alt; self.ctrl = ctrl
        self.wheelDelta = wheelDelta; self.clickCount = clickCount
    }
}

/// Capture and focus each imply handled. A nil render flag defaults to false for
/// move/release and true for press/click/drag/wheel. Dispatch preserves the flag.
@MainActor
public class TuiMouseEventResult {
    public var handled: Bool?
    public var capture: Bool?
    public var focus: Bool?
    public var render: Bool?
    public init(handled: Bool? = nil, capture: Bool? = nil, focus: Bool? = nil, render: Bool? = nil) {
        self.handled = handled; self.capture = capture; self.focus = focus; self.render = render
    }
    /// Return a copy with focus requested, without changing a reusable handler result.
    func requestingFocus() -> TuiMouseEventResult {
        if let result = self as? TuiMouseDispatchResult {
            return TuiMouseDispatchResult(target: result.target, focusTarget: result.focusTarget,
                                          capture: capture, focus: true, render: render)
        }
        return TuiMouseEventResult(handled: handled, capture: capture, focus: true, render: render)
    }

    public func shouldRender(for type: TuiMouseEventType) -> Bool {
        render ?? (type != .move && type != .release)
    }
}

@MainActor
public struct TuiMouseDispatchTarget {
    public var component: any Component
    public var originX: Int
    public var originY: Int
    public var width: Int
    public var height: Int
    public init(component: any Component, originX: Int, originY: Int, width: Int, height: Int) {
        self.component = component; self.originX = originX; self.originY = originY
        self.width = width; self.height = height
    }
}

/// Class inheritance preserves a child's dispatch target through delegating components.
@MainActor
public final class TuiMouseDispatchResult: TuiMouseEventResult {
    public var target: TuiMouseDispatchTarget
    public var focusTarget: (any Component)?
    func withFocusTarget(_ component: any Component) -> TuiMouseDispatchResult {
        TuiMouseDispatchResult(target: target, focusTarget: component, capture: capture, focus: focus, render: render)
    }

    public init(target: TuiMouseDispatchTarget, focusTarget: (any Component)? = nil,
                capture: Bool? = nil, focus: Bool? = nil, render: Bool? = nil) {
        self.target = target; self.focusTarget = focusTarget
        super.init(handled: true, capture: capture, focus: focus, render: render)
    }
}

/// Opt in when a container handles keyboard input on behalf of its children.
/// Swift cannot test whether a protocol's default input method was overridden.
@MainActor
public protocol MouseFocusOwner: Component {}

@MainActor
public func dispatchMouseEvent(_ component: any Component, _ event: TuiMouseEvent) -> TuiMouseDispatchResult? {
    guard let result = component.handleMouse(event) else { return nil }
    if let dispatched = result as? TuiMouseDispatchResult {
        if dispatched.focus == true, component is any MouseFocusOwner {
            return dispatched.withFocusTarget(component)
        }
        return dispatched
    }
    guard result.handled == true || result.capture == true || result.focus == true else { return nil }
    return TuiMouseDispatchResult(
        target: TuiMouseDispatchTarget(component: component,
            originX: event.screenX - event.x, originY: event.screenY - event.y,
            width: event.width, height: event.height),
        focusTarget: result.focus == true ? component : nil,
        capture: result.capture, focus: result.focus, render: result.render)
}

@MainActor
public func retargetMouseEvent(_ event: TuiMouseEvent, _ target: TuiMouseDispatchTarget) -> TuiMouseEvent {
    var event = event
    event.x = event.screenX - target.originX; event.y = event.screenY - target.originY
    event.width = target.width; event.height = target.height
    return event
}
