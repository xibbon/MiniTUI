import Foundation

/// A stack that allocates children from left to right.
public final class HStack: Stack {
    public override var layoutAxis: StackLayoutNode.Axis { .hstack }

    public override func render(width: Int) -> [String] {
        let safeWidth = max(1, width)
        if let cached = cachedRender(width: safeWidth) { return cached }

        let viewport = LayoutViewport(width: safeWidth, height: Int.max)
        let visibleEntries = visibleStackEntries(entries, viewport: viewport)
        if visibleEntries.isEmpty {
            storeRender([], width: safeWidth)
            return []
        }

        let intrinsicWidths = visibleEntries.map { entry in
            entry.component.render(width: safeWidth).reduce(0) { result, line in
                max(result, visibleWidth(line))
            }
        }
        let widths = allocateStackSizes(
            entries: visibleEntries,
            intrinsicSizes: intrinsicWidths,
            availableSize: safeWidth,
            gap: gap
        )
        let rendered = visibleEntries.indices.map { index in
            widths[index] == 0 ? [] : visibleEntries[index].component.render(width: widths[index])
        }
        let height = rendered.map(\.count).max() ?? 0
        var result = Array(repeating: "", count: height)
        var x = 0
        for index in rendered.indices {
            let lines = rendered[index]
            let childWidth = widths[index]
            var offset = 0
            if align == .center {
                offset = (height - lines.count) / 2
            } else if align == .end {
                offset = height - lines.count
            }
            for row in lines.indices {
                let target = row + offset
                guard result.indices.contains(target) else { continue }
                result[target] = compositeLayoutLine(
                    baseLine: result[target],
                    overlayLine: lines[row],
                    startColumn: x,
                    overlayWidth: childWidth,
                    totalWidth: safeWidth
                )
            }
            x += childWidth + gap
        }
        storeRender(result, width: safeWidth)
        return result
    }
}
