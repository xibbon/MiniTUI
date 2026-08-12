import Foundation

/// A stack that allocates children from top to bottom.
public final class VStack: Stack {
    public override var layoutAxis: StackLayoutNode.Axis { .vstack }

    public override func render(width: Int) -> [String] {
        let safeWidth = max(1, width)
        if let cached = cachedRender(width: safeWidth) { return cached }

        let viewport = LayoutViewport(width: safeWidth, height: Int.max)
        let visibleEntries = visibleStackEntries(entries, viewport: viewport)
        let rendered = visibleEntries.map { $0.component.render(width: safeWidth) }
        let sizes = allocateStackSizes(
            entries: visibleEntries,
            intrinsicSizes: rendered.map(\.count),
            availableSize: nil,
            gap: gap
        )
        var lines: [String] = []
        for index in visibleEntries.indices {
            if index > 0 {
                lines.append(contentsOf: repeatElement("", count: gap))
            }
            let childLines = Array(rendered[index].prefix(sizes[index]))
            lines.append(contentsOf: childLines)
            if childLines.count < sizes[index] {
                lines.append(contentsOf: repeatElement("", count: sizes[index] - childLines.count))
            }
        }
        storeRender(lines, width: safeWidth)
        return lines
    }
}
