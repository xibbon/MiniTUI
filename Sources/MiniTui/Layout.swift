import Foundation

/// A rectangle in terminal-cell coordinates.
public struct LayoutRect {
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// A component's allocated rectangle and its laid-out descendants.
public final class LayoutBox {
    public var component: Component
    public var rect: LayoutRect
    public var clip: LayoutRect
    public var children: [LayoutBox]
    public weak var parent: LayoutBox?
    public var lines: [String]?
    public var lineOffset: Int?
    public var scrollView: ScrollView?
    public var scrollContentLines: [String]?
    public var layer: Int

    public init(
        component: Component,
        rect: LayoutRect,
        clip: LayoutRect,
        children: [LayoutBox] = [],
        parent: LayoutBox? = nil,
        lines: [String]? = nil,
        lineOffset: Int? = nil,
        scrollView: ScrollView? = nil,
        scrollContentLines: [String]? = nil,
        layer: Int = 0
    ) {
        self.component = component
        self.rect = rect
        self.clip = clip
        self.children = children
        self.parent = parent
        self.lines = lines
        self.lineOffset = lineOffset
        self.scrollView = scrollView
        self.scrollContentLines = scrollContentLines
        self.layer = layer
    }
}

/// One complete constrained layout and its painted lines.
public struct LayoutFrame {
    public var root: LayoutBox
    public var width: Int
    public var height: Int
    public var lines: [String]
    public var primaryScrollView: ScrollView?

    public init(
        root: LayoutBox,
        width: Int,
        height: Int,
        lines: [String],
        primaryScrollView: ScrollView? = nil
    ) {
        self.root = root
        self.width = width
        self.height = height
        self.lines = lines
        self.primaryScrollView = primaryScrollView
    }
}

/// The cell geometry used to paint a scroll-view thumb.
public struct ScrollbarGeometry {
    public var column: Int
    public var trackTop: Int
    public var trackHeight: Int
    public var thumbTop: Int
    public var thumbHeight: Int
    public var maxScrollTop: Int

    public init(
        column: Int,
        trackTop: Int,
        trackHeight: Int,
        thumbTop: Int,
        thumbHeight: Int,
        maxScrollTop: Int
    ) {
        self.column = column
        self.trackTop = trackTop
        self.trackHeight = trackHeight
        self.thumbTop = thumbTop
        self.thumbHeight = thumbHeight
        self.maxScrollTop = maxScrollTop
    }
}

@MainActor
private final class LayoutContext {
    let viewport: LayoutViewport
    var renderCache: [ObjectIdentifier: [Int: [String]]] = [:]
    let requestRender: () -> Void
    var primaryScrollView: ScrollView?

    init(viewport: LayoutViewport, requestRender: @escaping () -> Void) {
        self.viewport = viewport
        self.requestRender = requestRender
    }
}

private func intersect(_ first: LayoutRect, _ second: LayoutRect) -> LayoutRect {
    let x = max(first.x, second.x)
    let y = max(first.y, second.y)
    let right = min(first.x + first.width, second.x + second.width)
    let bottom = min(first.y + first.height, second.y + second.height)
    return LayoutRect(x: x, y: y, width: max(0, right - x), height: max(0, bottom - y))
}

@MainActor
private func renderCached(_ context: LayoutContext, component: Component, width: Int) -> [String] {
    let safeWidth = max(1, width)
    let identifier = ObjectIdentifier(component)
    if let lines = context.renderCache[identifier]?[safeWidth] {
        return lines
    }

    let lines = component.render(width: safeWidth)
    var widths = context.renderCache[identifier] ?? [:]
    widths[safeWidth] = lines
    context.renderCache[identifier] = widths
    return lines
}

@MainActor
private func measureHeight(_ context: LayoutContext, component: Component, width: Int) -> Int {
    renderCached(context, component: component, width: width).count
}

@MainActor
private func measureWidth(_ context: LayoutContext, component: Component, width: Int) -> Int {
    renderCached(context, component: component, width: width).reduce(0) { result, line in
        max(result, visibleWidth(line))
    }
}

private func withParent(_ box: LayoutBox, parent: LayoutBox) -> LayoutBox {
    box.parent = parent
    return box
}

private func translateBox(_ box: LayoutBox, deltaY: Int) {
    box.rect.y += deltaY
    for child in box.children {
        translateBox(child, deltaY: deltaY)
    }
}

private func updateClips(_ box: LayoutBox, parentClip: LayoutRect) {
    box.clip = intersect(parentClip, box.rect)
    for child in box.children {
        updateClips(child, parentClip: box.clip)
    }
}

@MainActor
private func layoutComponent(
    _ context: LayoutContext,
    component: Component,
    x: Int,
    y: Int,
    width: Int,
    height: Int?,
    clip: LayoutRect
) -> LayoutBox {
    let safeWidth = max(1, width)
    guard let node = getLayoutNode(component) else {
        let lines = renderCached(context, component: component, width: safeWidth)
        let allocatedHeight = height.map { max(0, $0) } ?? lines.count
        var lineOffset = 0
        if lines.count > allocatedHeight, allocatedHeight > 0,
           let cursorLine = lines.firstIndex(where: { $0.contains(systemCursorMarker) }),
           cursorLine >= allocatedHeight {
            lineOffset = cursorLine - allocatedHeight + 1
        }
        let rect = LayoutRect(x: x, y: y, width: safeWidth, height: allocatedHeight)
        return LayoutBox(
            component: component,
            rect: rect,
            clip: intersect(clip, rect),
            lines: lines,
            lineOffset: lineOffset
        )
    }

    switch node {
    case .scroll(let scrollNode):
        let previousScrollTop = scrollNode.state.scrollTop
        let contentWidth = scrollNode.state.contentWidth(forWidth: safeWidth)
        let childBox = layoutComponent(
            context,
            component: scrollNode.component,
            x: x,
            y: y - previousScrollTop,
            width: contentWidth,
            height: nil,
            clip: clip
        )
        let contentHeight = childBox.rect.height
        let viewportHeight = height.map { max(0, $0) } ?? contentHeight
        scrollNode.state.updateLayout(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight,
            requestRender: context.requestRender
        )
        translateBox(childBox, deltaY: previousScrollTop - scrollNode.state.scrollTop)

        let scrollView = scrollNode.state as? ScrollView
        if let scrollView, scrollNode.state.primary || context.primaryScrollView == nil {
            context.primaryScrollView = scrollView
        }

        let rect = LayoutRect(x: x, y: y, width: safeWidth, height: viewportHeight)
        let childClip = intersect(clip, rect)
        let box = LayoutBox(
            component: component,
            rect: rect,
            clip: childClip,
            children: [childBox],
            scrollView: scrollView,
            scrollContentLines: renderCached(context, component: scrollNode.component, width: contentWidth)
        )
        childBox.parent = box
        updateClips(childBox, parentClip: childClip)
        return box

    case .stack(let stackNode):
        let entries = visibleStackEntries(stackNode.entries, viewport: context.viewport)
        let gapTotal = max(0, entries.count - 1) * stackNode.gap

        if stackNode.type == .vstack {
            let intrinsicHeights = entries.map { entry in
                switch entry.basis {
                case .points(let points): return points
                case .auto, nil: return measureHeight(context, component: entry.component, width: safeWidth)
                }
            }
            let sizes = allocateStackSizes(
                entries: entries,
                intrinsicSizes: intrinsicHeights,
                availableSize: height,
                gap: stackNode.gap
            )
            let naturalHeight = sizes.reduce(0, +) + gapTotal
            let allocatedHeight = height.map { max(0, $0) } ?? naturalHeight
            let rect = LayoutRect(x: x, y: y, width: safeWidth, height: allocatedHeight)
            let box = LayoutBox(component: component, rect: rect, clip: intersect(clip, rect))
            var childY = y
            for index in entries.indices {
                box.children.append(withParent(
                    layoutComponent(
                        context,
                        component: entries[index].component,
                        x: x,
                        y: childY,
                        width: safeWidth,
                        height: sizes[index],
                        clip: box.clip
                    ),
                    parent: box
                ))
                childY += sizes[index] + stackNode.gap
            }
            return box
        }

        let intrinsicWidths = entries.map { entry in
            switch entry.basis {
            case .points(let points): return points
            case .auto, nil: return measureWidth(context, component: entry.component, width: safeWidth)
            }
        }
        let widths = allocateStackSizes(
            entries: entries,
            intrinsicSizes: intrinsicWidths,
            availableSize: safeWidth,
            gap: stackNode.gap
        )
        let intrinsicHeights = entries.indices.map { index in
            measureHeight(context, component: entries[index].component, width: max(1, widths[index]))
        }
        let allocatedHeight = height.map { max(0, $0) } ?? intrinsicHeights.max() ?? 0
        let rect = LayoutRect(x: x, y: y, width: safeWidth, height: allocatedHeight)
        let box = LayoutBox(component: component, rect: rect, clip: intersect(clip, rect))
        var childX = x
        for index in entries.indices {
            let naturalChildHeight = intrinsicHeights[index]
            let childHeight = stackNode.align == .stretch
                ? allocatedHeight
                : min(allocatedHeight, naturalChildHeight)
            var childY = y
            if stackNode.align == .center {
                childY += (allocatedHeight - childHeight) / 2
            } else if stackNode.align == .end {
                childY += allocatedHeight - childHeight
            }

            let childWidth = widths[index]
            if childWidth == 0 {
                box.children.append(LayoutBox(
                    component: entries[index].component,
                    rect: LayoutRect(x: childX, y: childY, width: 0, height: childHeight),
                    clip: LayoutRect(x: childX, y: childY, width: 0, height: 0),
                    parent: box
                ))
            } else {
                box.children.append(withParent(
                    layoutComponent(
                        context,
                        component: entries[index].component,
                        x: childX,
                        y: childY,
                        width: childWidth,
                        height: childHeight,
                        clip: box.clip
                    ),
                    parent: box
                ))
            }
            childX += childWidth + stackNode.gap
        }
        return box
    }
}

private let layoutSegmentReset = "\u{001B}[0m" + osc8HyperlinkCloseBell

@MainActor
func compositeLayoutLine(
    baseLine: String,
    overlayLine: String,
    startColumn: Int,
    overlayWidth: Int,
    totalWidth: Int
) -> String {
    if isImageLine(baseLine) { return baseLine }

    let afterStart = startColumn + overlayWidth
    let base = extractSegments(
        baseLine,
        beforeEnd: startColumn,
        afterStart: afterStart,
        afterLen: max(0, totalWidth - afterStart),
        strictAfter: true
    )
    let overlay = sliceWithWidth(overlayLine, startCol: 0, length: overlayWidth, strict: true)
    let beforePadding = max(0, startColumn - base.beforeWidth)
    let overlayPadding = max(0, overlayWidth - overlay.width)
    let actualBeforeWidth = max(startColumn, base.beforeWidth)
    let actualOverlayWidth = max(overlayWidth, overlay.width)
    let afterTarget = max(0, totalWidth - actualBeforeWidth - actualOverlayWidth)
    let afterPadding = max(0, afterTarget - base.afterWidth)
    let result = base.before
        + String(repeating: " ", count: beforePadding)
        + layoutSegmentReset
        + overlay.text
        + String(repeating: " ", count: overlayPadding)
        + layoutSegmentReset
        + base.after
        + String(repeating: " ", count: afterPadding)

    if visibleWidth(result) <= totalWidth { return result }
    return sliceByColumn(result, startCol: 0, length: totalWidth, strict: true)
}

/// Remove leading OSC 133 prompt-zone markers while preserving visible text.
public func stripLeadingOSC133Zones(_ line: String) -> String {
    var result = line
    while let ansi = extractAnsiCode(result, at: 0) {
        let bellPrefix = "\u{001B}]133;"
        guard ansi.code.hasPrefix(bellPrefix) else { break }
        let body = ansi.code.dropFirst(bellPrefix.count)
        guard let zone = body.first, zone == "A" || zone == "B" || zone == "C" else { break }
        let suffix = body.dropFirst()
        guard suffix == "\u{0007}" || suffix == "\u{001B}\\" else { break }
        result.removeFirst(ansi.length)
    }
    return result
}

/// Return true when a line starts an OSC 133 semantic prompt zone.
public func isOSC133PromptStart(_ line: String) -> Bool {
    guard let ansi = extractAnsiCode(line, at: 0) else { return false }
    let prefix = "\u{001B}]133;A"
    guard ansi.code.hasPrefix(prefix) else { return false }
    let suffix = ansi.code.dropFirst(prefix.count)
    return suffix == "\u{0007}" || suffix == "\u{001B}\\"
}

private func replaceScrollbarCell(
    line: String,
    column: Int,
    totalWidth: Int,
    replacement: String,
    preserveTargetBackground: Bool
) -> String {
    if isImageLine(line) { return line }

    let range = getGraphemeCellRange(line: line, column: column)
    let start = range?.start ?? column
    let end = range?.end ?? column + 1
    let before = sliceByColumn(line, startCol: 0, length: start, strict: true)
    let target = sliceByColumn(line, startCol: start, length: end - start, strict: true)
    let after = sliceByColumn(line, startCol: end, length: max(0, totalWidth - end), strict: true)

    var targetPrefix = ""
    var targetIndex = 0
    while targetIndex < target.count, let ansi = extractAnsiCode(target, at: targetIndex) {
        targetPrefix += ansi.code
        targetIndex += ansi.length
    }
    let beforePadding = String(repeating: " ", count: max(0, start - visibleWidth(before)))
    let cellPaddingBefore = String(repeating: " ", count: max(0, column - start))
    let cellPaddingAfter = String(repeating: " ", count: max(0, end - column - 1))
    let targetStyle = layoutSegmentReset + (preserveTargetBackground ? getActiveBackgroundAnsi(targetPrefix) : "")
    return before + beforePadding + targetStyle + cellPaddingBefore + replacement + cellPaddingAfter + after
}

/// Return scrollbar geometry, optionally including a hidden automatic track.
@MainActor
public func getScrollbarGeometry(_ box: LayoutBox, includeHiddenAuto: Bool = false) -> ScrollbarGeometry? {
    guard let scrollView = box.scrollView,
          box.rect.width > 0,
          box.rect.height > 0 else {
        return nil
    }

    let contentHeight = box.children.first?.rect.height ?? box.scrollContentLines?.count ?? 0
    let trackHeight = box.rect.height
    let canRevealHiddenAuto = includeHiddenAuto && scrollView.scrollbar == .auto && contentHeight > trackHeight
    guard scrollView.isScrollbarVisible || canRevealHiddenAuto else { return nil }
    let minThumbHeight = min(2, trackHeight)
    let proportionalHeight = contentHeight > 0
        ? Int((Double(trackHeight * trackHeight) / Double(contentHeight)).rounded())
        : trackHeight
    let thumbHeight = max(minThumbHeight, min(trackHeight, proportionalHeight))
    let maxScrollTop = max(0, contentHeight - trackHeight)
    let maxThumbTop = trackHeight - thumbHeight
    let thumbOffset = maxScrollTop == 0
        ? 0
        : Int((Double(scrollView.scrollTop) / Double(maxScrollTop) * Double(maxThumbTop)).rounded())
    let column = box.rect.x + box.rect.width - 1
    guard column >= box.clip.x, column < box.clip.x + box.clip.width else { return nil }

    return ScrollbarGeometry(
        column: column,
        trackTop: box.rect.y,
        trackHeight: trackHeight,
        thumbTop: box.rect.y + thumbOffset,
        thumbHeight: thumbHeight,
        maxScrollTop: maxScrollTop
    )
}

@MainActor
private func paintScrollbar(_ box: LayoutBox, screen: inout [String], totalWidth: Int) {
    guard let geometry = getScrollbarGeometry(box), let scrollView = box.scrollView else { return }
    for offset in 0..<geometry.trackHeight {
        let row = geometry.trackTop + offset
        if row < box.clip.y || row >= box.clip.y + box.clip.height || row < 0 || row >= screen.count {
            continue
        }
        let isThumb = row >= geometry.thumbTop && row < geometry.thumbTop + geometry.thumbHeight
        let replacement = isThumb
            ? scrollView.scrollbarThumbStyle(scrollView.isScrollbarActive ? "█" : "┃")
            : scrollView.scrollbarTrackStyle("│")
        screen[row] = replaceScrollbarCell(
            line: screen[row],
            column: geometry.column,
            totalWidth: totalWidth,
            replacement: replacement,
            preserveTargetBackground: scrollView.scrollbar != .always
        )
    }
}

@MainActor
private func paintBox(_ box: LayoutBox, screen: inout [String], totalWidth: Int) {
    if let lines = box.lines {
        let offset = box.lineOffset ?? 0
        let firstRow = max(box.rect.y, box.clip.y, 0)
        let lastRow = min(box.rect.y + box.rect.height, box.clip.y + box.clip.height, screen.count)
        if firstRow < lastRow {
            for row in firstRow..<lastRow {
                let sourceIndex = offset + row - box.rect.y
                guard lines.indices.contains(sourceIndex) else { continue }
                var line = stripLeadingOSC133Zones(lines[sourceIndex])
                if let imageMetadata = getKittyImageMetadata(line) {
                    let clipBottom = min(screen.count, box.clip.y + box.clip.height)
                    let visibleRows = min(imageMetadata.rows, clipBottom - row)
                    if visibleRows < imageMetadata.rows {
                        line = cropKittyImageLine(line, hiddenRows: 0, visibleRows: visibleRows)
                    }
                }
                if box.rect.x == 0, box.rect.width >= totalWidth,
                   isImageLine(line) || screen[row].isEmpty {
                    screen[row] = line
                } else {
                    screen[row] = compositeLayoutLine(
                        baseLine: screen[row],
                        overlayLine: line,
                        startColumn: box.rect.x,
                        overlayWidth: box.rect.width,
                        totalWidth: totalWidth
                    )
                }
            }
        }
    }

    for child in box.children {
        paintBox(child, screen: &screen, totalWidth: totalWidth)
    }

    if let scrollView = box.scrollView,
       let scrollContentLines = box.scrollContentLines,
       scrollView.scrollTop > 0,
       box.rect.height > 0 {
        for imageRow in stride(from: scrollView.scrollTop - 1, through: 0, by: -1) {
            let imageLine = scrollContentLines.indices.contains(imageRow) ? scrollContentLines[imageRow] : ""
            if let metadata = getKittyImageMetadata(imageLine) {
                let hiddenRows = scrollView.scrollTop - imageRow
                if hiddenRows < metadata.rows {
                    let visibleRows = min(box.rect.height, metadata.rows - hiddenRows)
                    let cropped = cropKittyImageLine(
                        imageLine,
                        hiddenRows: hiddenRows,
                        visibleRows: visibleRows
                    )
                    if box.rect.x == 0, box.rect.width >= totalWidth,
                       screen.indices.contains(box.rect.y) {
                        screen[box.rect.y] = cropped
                    }
                }
                break
            }
            if !imageLine.isEmpty { break }
        }
    }
    paintScrollbar(box, screen: &screen, totalWidth: totalWidth)
}

/// Lay out and paint a component tree into a fixed terminal viewport.
@MainActor
public func renderLayoutFrame(
    root: Component,
    width: Int,
    height: Int,
    requestRender: @escaping () -> Void
) -> LayoutFrame {
    let safeWidth = max(1, width)
    let safeHeight = max(1, height)
    let viewport = LayoutViewport(width: safeWidth, height: safeHeight)
    let context = LayoutContext(viewport: viewport, requestRender: requestRender)
    let viewportRect = LayoutRect(x: 0, y: 0, width: safeWidth, height: safeHeight)
    let rootBox = layoutComponent(
        context,
        component: root,
        x: 0,
        y: 0,
        width: safeWidth,
        height: safeHeight,
        clip: viewportRect
    )
    var lines = Array(repeating: "", count: safeHeight)
    paintBox(rootBox, screen: &lines, totalWidth: safeWidth)
    return LayoutFrame(
        root: rootBox,
        width: safeWidth,
        height: safeHeight,
        lines: lines,
        primaryScrollView: context.primaryScrollView
    )
}

private func containsPoint(_ rect: LayoutRect, x: Int, y: Int) -> Bool {
    x >= rect.x && x < rect.x + rect.width && y >= rect.y && y < rect.y + rect.height
}

/// Return the visual hit path by descending layer, then descending depth.
@MainActor
public func getLayoutBoxesAt(frame: LayoutFrame, x: Int, y: Int) -> [LayoutBox] {
    var result: [(box: LayoutBox, depth: Int)] = []
    func visit(_ box: LayoutBox, depth: Int) {
        guard containsPoint(box.clip, x: x, y: y) else { return }
        result.append((box, depth))
        for child in box.children { visit(child, depth: depth + 1) }
    }
    visit(frame.root, depth: 0)
    result.sort {
        if $0.box.layer != $1.box.layer { return $0.box.layer > $1.box.layer }
        return $0.depth > $1.depth
    }
    return result.map(\.box)
}

/// Find the layout box for a scroll view by identity.
@MainActor
public func getScrollViewBox(frame: LayoutFrame, scrollView: ScrollView) -> LayoutBox? {
    func visit(_ box: LayoutBox) -> LayoutBox? {
        if box.scrollView === scrollView { return box }
        for child in box.children {
            if let match = visit(child) { return match }
        }
        return nil
    }
    return visit(frame.root)
}

/// Return scroll views under a point, ordered from innermost to outermost.
@MainActor
public func getScrollViewsAt(frame: LayoutFrame, x: Int, y: Int) -> [ScrollView] {
    var result: [(scrollView: ScrollView, depth: Int)] = []
    func visit(_ box: LayoutBox, depth: Int) {
        guard containsPoint(box.clip, x: x, y: y) else { return }
        if let scrollView = box.scrollView, containsPoint(box.rect, x: x, y: y) {
            result.append((scrollView, depth))
        }
        for child in box.children {
            visit(child, depth: depth + 1)
        }
    }
    visit(frame.root, depth: 0)
    result.sort { $0.depth > $1.depth }
    return result.map(\.scrollView)
}
