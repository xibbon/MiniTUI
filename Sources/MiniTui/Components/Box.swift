import Foundation

/// Container that adds padding and optional background styling.
open class Box: Component {
    /// Current child components.
    public private(set) var children: [Component] = []
    private var paddingX: Int
    private let paddingY: Int
    private var bgFn: ((String) -> String)?

    private var childRecord: ChildLines?
    private var cachedWidth: Int?
    private var cachedChildGeneration: Int?
    private var cachedBgSample: String?
    private var cachedLines: [String]?
    internal private(set) var childRecordRebuildCount = 0
    internal private(set) var outputRebuildCount = 0

    /// Create a box with padding and optional background formatter.
    public init(paddingX: Int = 1, paddingY: Int = 1, bgFn: ((String) -> String)? = nil) {
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.bgFn = bgFn
    }

    /// Add a child component.
    public func addChild(_ component: Component) {
        children.append(component)
        invalidateCache()
    }

    /// Remove a child component.
    public func removeChild(_ component: Component) {
        if let index = children.firstIndex(where: { $0 === component }) {
            children.remove(at: index)
            invalidateCache()
        }
    }

    /// Remove all child components.
    public func clear() {
        children.removeAll()
        invalidateCache()
    }

    /// Update the background formatter.
    public func setBgFn(_ bgFn: ((String) -> String)?) {
        self.bgFn = bgFn
        invalidateCache()
    }

    /// Set the horizontal padding and clear cached lines.
    public func setPaddingX(_ paddingX: Int) {
        self.paddingX = paddingX
        invalidateCache()
    }

    /// Invalidate cached lines and child state.
    open func invalidate() {
        invalidateCache()
        for child in children {
            child.invalidate()
        }
    }

    public func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        let contentWidth = max(1, event.width - paddingX * 2)
        let contentY = event.y - paddingY
        let contentX = event.x - paddingX
        guard contentY >= 0, contentX >= 0, contentX < contentWidth else { return nil }
        let layout = childRecord?.width == contentWidth ? childRecord!
            : renderChildLines(children, width: contentWidth, previous: nil)
        var local = event
        local.x = contentX; local.y = contentY
        local.width = contentWidth
        return dispatchMouseToChildLines(layout, local)
    }

    /// Render children with padding and optional background.
    public func render(width: Int) -> [String] {
        if children.isEmpty {
            return []
        }

        let contentWidth = max(1, width - paddingX * 2)
        let leftPad = String(repeating: " ", count: paddingX)

        let previous = childRecord
        childRecord = renderChildLines(children, width: contentWidth, previous: previous)
        if previous?.generation != childRecord?.generation { childRecordRebuildCount += 1 }
        let childLines = childRecord!.lines

        if childLines.isEmpty {
            return []
        }

        let bgSample = bgFn?("test")
        if let cachedLines, cachedWidth == width,
           cachedChildGeneration == childRecord?.generation, cachedBgSample == bgSample {
            return cachedLines
        }

        var result: [String] = []

        for _ in 0..<paddingY {
            result.append(applyBg("", width: width))
        }

        for line in childLines {
            result.append(applyBg(leftPad + line, width: width))
        }

        for _ in 0..<paddingY {
            result.append(applyBg("", width: width))
        }

        cachedWidth = width
        cachedChildGeneration = childRecord?.generation
        cachedBgSample = bgSample
        cachedLines = result
        outputRebuildCount += 1

        return result
    }

    private func applyBg(_ line: String, width: Int) -> String {
        let visLen = visibleWidth(line)
        let padNeeded = max(0, width - visLen)
        let padded = line + String(repeating: " ", count: padNeeded)
        return bgFn?(padded) ?? padded
    }

    private func invalidateCache() {
        cachedWidth = nil
        childRecord = nil
        cachedChildGeneration = nil
        cachedBgSample = nil
        cachedLines = nil
    }
}
