import Foundation

/// The terminal area available to a layout component.
public struct LayoutViewport {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// The initial size of a stack entry on the stack's main axis.
public enum LayoutBasis: Equatable {
    case auto
    case points(Int)
}

/// One child and its sizing rules in a stack layout.
public struct StackLayoutEntry {
    public var component: Component
    public var basis: LayoutBasis?
    public var grow: Int?
    public var shrink: Int?
    public var minSize: Int?
    public var maxSize: Int?
    public var visible: ((LayoutViewport) -> Bool)?

    public init(
        component: Component,
        basis: LayoutBasis? = nil,
        grow: Int? = nil,
        shrink: Int? = nil,
        minSize: Int? = nil,
        maxSize: Int? = nil,
        visible: ((LayoutViewport) -> Bool)? = nil
    ) {
        self.component = component
        self.basis = basis
        self.grow = grow
        self.shrink = shrink
        self.minSize = minSize
        self.maxSize = maxSize
        self.visible = visible
    }
}

/// The layout description for a vertical or horizontal stack.
public struct StackLayoutNode {
    public enum Axis: Equatable {
        case vstack
        case hstack
    }

    public enum Align: Equatable {
        case stretch
        case start
        case center
        case end
    }

    public var type: Axis
    public var entries: [StackLayoutEntry]
    public var gap: Int
    public var align: Align

    public init(type: Axis, entries: [StackLayoutEntry], gap: Int = 0, align: Align = .stretch) {
        self.type = type
        self.entries = entries
        self.gap = gap
        self.align = align
    }
}

/// The behavior at a nested scroll boundary.
public enum ScrollOverscroll: Equatable {
    case chain
    case contain
}

/// Mutable state owned by a scroll view.
@MainActor
public protocol ScrollLayoutState: AnyObject {
    var scrollTop: Int { get }
    var primary: Bool { get }
    var overscroll: ScrollOverscroll { get }
    var viewportHeight: Int { get }
    func contentWidth(forWidth width: Int) -> Int
    func updateLayout(contentHeight: Int, viewportHeight: Int, requestRender: @escaping () -> Void)
}

/// The layout description for a scroll view.
public struct ScrollLayoutNode {
    public var component: Component
    public var state: ScrollLayoutState

    public init(component: Component, state: ScrollLayoutState) {
        self.component = component
        self.state = state
    }
}

/// An opt-in component layout description.
public enum LayoutNode {
    case stack(StackLayoutNode)
    case scroll(ScrollLayoutNode)
}

/// A component that participates in the constraint-based layout engine.
public protocol LayoutComponent: Component {
    var layoutNode: LayoutNode { get }
}

/// Return a component's layout node, or nil for ordinary rendered components.
@MainActor
public func getLayoutNode(_ component: Component) -> LayoutNode? {
    (component as? LayoutComponent)?.layoutNode
}
