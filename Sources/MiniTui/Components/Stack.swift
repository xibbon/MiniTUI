import Foundation

/// Sizing and visibility options for one stack child.
public struct StackEntryOptions {
    public var basis: LayoutBasis?
    public var grow: Int?
    public var shrink: Int?
    public var minSize: Int?
    public var maxSize: Int?
    public var visible: ((LayoutViewport) -> Bool)?

    public init(
        basis: LayoutBasis? = nil,
        grow: Int? = nil,
        shrink: Int? = nil,
        minSize: Int? = nil,
        maxSize: Int? = nil,
        visible: ((LayoutViewport) -> Bool)? = nil
    ) {
        self.basis = basis
        self.grow = grow
        self.shrink = shrink
        self.minSize = minSize
        self.maxSize = maxSize
        self.visible = visible
    }
}

/// A component paired with stack entry options.
public struct StackEntry {
    public var component: Component
    public var options: StackEntryOptions

    public init(_ component: Component, options: StackEntryOptions = StackEntryOptions()) {
        self.component = component
        self.options = options
    }
}

/// A child accepted by the mixed-child stack initializer.
public enum StackChild {
    case component(Component)
    case entry(StackEntry)
}

/// Configuration shared by vertical and horizontal stacks.
public struct StackOptions {
    public var gap: Int
    public var align: StackLayoutNode.Align

    public init(gap: Int = 0, align: StackLayoutNode.Align = .stretch) {
        self.gap = gap
        self.align = align
    }
}

private func normalizedSize(_ value: Int?, fallback: Int) -> Int {
    max(0, value ?? fallback)
}

/// Base class for vertical and horizontal layout stacks.
open class Stack: Container, LayoutComponent {
    public private(set) var entries: [StackLayoutEntry] = []
    public let gap: Int
    public let align: StackLayoutNode.Align

    private var cachedWidth: Int?
    private var cachedLines: [String]?

    open var layoutAxis: StackLayoutNode.Axis {
        preconditionFailure("Stack subclasses must supply a layout axis")
    }

    public init(children: [StackChild] = [], options: StackOptions = StackOptions()) {
        gap = normalizedSize(options.gap, fallback: 0)
        align = options.align
        super.init()
        for child in children {
            switch child {
            case .component(let component):
                addChild(component)
            case .entry(let entry):
                addChild(entry.component, options: entry.options)
            }
        }
    }

    public convenience init(_ children: [Component], options: StackOptions = StackOptions()) {
        self.init(children: children.map(StackChild.component), options: options)
    }

    /// Add one child with optional main-axis sizing constraints.
    public func addChild(_ component: Component, options: StackEntryOptions) {
        super.addChild(component)
        entries.append(StackLayoutEntry(
            component: component,
            basis: options.basis,
            grow: options.grow.map { normalizedSize($0, fallback: 0) },
            shrink: options.shrink.map { normalizedSize($0, fallback: 1) },
            minSize: options.minSize.map { normalizedSize($0, fallback: 0) },
            maxSize: options.maxSize.map { normalizedSize($0, fallback: Int.max) },
            visible: options.visible
        ))
        invalidateCache()
    }

    public override func addChild(_ component: Component) {
        addChild(component, options: StackEntryOptions())
    }

    public override func removeChild(_ component: Component) {
        super.removeChild(component)
        if let index = entries.firstIndex(where: { $0.component === component }) {
            entries.remove(at: index)
        }
        invalidateCache()
    }

    public override func clear() {
        super.clear()
        entries.removeAll()
        invalidateCache()
    }

    open override func invalidate() {
        invalidateCache()
        super.invalidate()
    }

    public var layoutNode: LayoutNode {
        .stack(StackLayoutNode(type: layoutAxis, entries: entries, gap: gap, align: align))
    }

    func cachedRender(width: Int) -> [String]? {
        cachedWidth == width ? cachedLines : nil
    }

    func storeRender(_ lines: [String], width: Int) {
        cachedWidth = width
        cachedLines = lines
    }

    private func invalidateCache() {
        cachedWidth = nil
        cachedLines = nil
    }
}

/// Filter stack entries for the current layout viewport.
public func visibleStackEntries(
    _ entries: [StackLayoutEntry],
    viewport: LayoutViewport
) -> [StackLayoutEntry] {
    entries.filter { $0.visible?(viewport) ?? true }
}

private func clampStackSize(_ size: Int, entry: StackLayoutEntry) -> Int {
    let minimum = max(0, entry.minSize ?? 0)
    let maximum = max(minimum, entry.maxSize ?? Int.max)
    return max(minimum, min(maximum, max(0, size)))
}

private enum StackDistributionMode {
    case grow
    case shrink
}

private func distributeStackSizes(
    _ sizes: inout [Int],
    entries: [StackLayoutEntry],
    amount: Int,
    mode: StackDistributionMode
) {
    var remaining = amount
    while remaining > 0 {
        let candidates = entries.indices.filter { index in
            let entry = entries[index]
            switch mode {
            case .grow:
                return (entry.grow ?? 0) > 0 && sizes[index] < (entry.maxSize ?? Int.max)
            case .shrink:
                return (entry.shrink ?? 1) > 0 && sizes[index] > (entry.minSize ?? 0)
            }
        }
        if candidates.isEmpty { return }

        let totalWeight = candidates.reduce(0) { result, index in
            let entry = entries[index]
            switch mode {
            case .grow:
                return result + (entry.grow ?? 0)
            case .shrink:
                return result + (entry.shrink ?? 1) * max(1, sizes[index])
            }
        }
        var distributed = 0
        for index in candidates {
            if remaining <= 0 { break }
            let entry = entries[index]
            let weight: Int
            let capacity: Int
            switch mode {
            case .grow:
                weight = entry.grow ?? 0
                capacity = (entry.maxSize ?? Int.max) - sizes[index]
            case .shrink:
                weight = (entry.shrink ?? 1) * max(1, sizes[index])
                capacity = sizes[index] - (entry.minSize ?? 0)
            }
            let proposed = max(1, remaining * weight / totalWeight)
            let delta = min(remaining, proposed, capacity)
            if delta <= 0 { continue }
            sizes[index] += mode == .grow ? delta : -delta
            remaining -= delta
            distributed += delta
        }
        if distributed == 0 { return }
    }
}

/// Allocate stack entry sizes using basis, grow, shrink, and min/max constraints.
public func allocateStackSizes(
    entries: [StackLayoutEntry],
    intrinsicSizes: [Int],
    availableSize: Int?,
    gap: Int
) -> [Int] {
    var sizes = entries.indices.map { index in
        let initial: Int
        switch entries[index].basis {
        case .points(let points): initial = points
        case .auto, nil: initial = intrinsicSizes.indices.contains(index) ? intrinsicSizes[index] : 0
        }
        return clampStackSize(initial, entry: entries[index])
    }
    guard let availableSize else { return sizes }

    let contentSize = max(0, availableSize - max(0, entries.count - 1) * gap)
    let total = sizes.reduce(0, +)
    if total < contentSize {
        distributeStackSizes(&sizes, entries: entries, amount: contentSize - total, mode: .grow)
    } else if total > contentSize {
        distributeStackSizes(&sizes, entries: entries, amount: total - contentSize, mode: .shrink)
    }
    return sizes
}
