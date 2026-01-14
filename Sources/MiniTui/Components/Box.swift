import Foundation

/// Container that adds padding and optional background styling.
open class Box: Component {
    /// Current child components.
    public private(set) var children: [Component] = []
    private let paddingX: Int
    private let paddingY: Int
    private var bgFn: ((String) -> String)?

    private var cachedWidth: Int?
    private var cachedChildLines: String?
    private var cachedBgSample: String?
    private var cachedLines: [String]?

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
    }

    /// Invalidate cached lines and child state.
    open func invalidate() {
        invalidateCache()
        for child in children {
            child.invalidate()
        }
    }

    /// Render children with padding and optional background.
    public func render(width: Int) -> [String] {
        if children.isEmpty {
            return []
        }

        let contentWidth = max(1, width - paddingX * 2)
        let leftPad = String(repeating: " ", count: paddingX)

        var childLines: [String] = []
        for child in children {
            let lines = child.render(width: contentWidth)
            for line in lines {
                childLines.append(leftPad + line)
            }
        }

        if childLines.isEmpty {
            return []
        }

        let bgSample = bgFn?("test")
        let childLinesKey = childLines.joined(separator: "\n")

        if let cachedLines, cachedWidth == width, cachedChildLines == childLinesKey, cachedBgSample == bgSample {
            return cachedLines
        }

        var result: [String] = []

        for _ in 0..<paddingY {
            result.append(applyBg("", width: width))
        }

        for line in childLines {
            result.append(applyBg(line, width: width))
        }

        for _ in 0..<paddingY {
            result.append(applyBg("", width: width))
        }

        cachedWidth = width
        cachedChildLines = childLinesKey
        cachedBgSample = bgSample
        cachedLines = result

        return result
    }

    private func applyBg(_ line: String, width: Int) -> String {
        let visLen = visibleWidth(line)
        let padNeeded = max(0, width - visLen)
        let padded = line + String(repeating: " ", count: padNeeded)
        if let bgFn {
            return applyBackgroundToLine(padded, width: width, bgFn: bgFn)
        }
        return padded
    }

    private func invalidateCache() {
        cachedWidth = nil
        cachedChildLines = nil
        cachedBgSample = nil
        cachedLines = nil
    }
}
