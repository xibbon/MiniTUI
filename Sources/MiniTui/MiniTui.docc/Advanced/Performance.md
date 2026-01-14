# Performance Optimization

Build efficient terminal applications with optimal rendering and resource usage.

@Metadata {
    @PageKind(article)
    @PageColor(orange)
}

## Overview

MiniTui is designed for performance, using differential rendering and caching to minimize terminal output. This guide covers how to leverage these features and avoid common performance pitfalls.

## Differential Rendering

MiniTui only updates changed lines, dramatically reducing terminal output:

```
Previous render:     Current render:      Output:
Line 1              Line 1               (no change)
Line 2              Line 2 CHANGED       Line 2 CHANGED
Line 3              Line 3               (no change)
```

### How It Works

1. Each render produces an array of strings
2. The TUI compares with previous render
3. Only different lines are written to the terminal
4. Updates are wrapped in CSI 2026 for atomic output

### Enabling Optimal Diffing

Keep lines stable between renders:

```swift
// Good: Stable line structure
func render(width: Int) -> [String] {
    return [
        "Header",
        "Content: \(value)",
        "Footer"
    ]
}

// Bad: Changing line count causes more redraws
func render(width: Int) -> [String] {
    var lines = ["Header"]
    if showContent {
        lines.append("Content: \(value)")
    }
    lines.append("Footer")
    return lines
}
```

## Caching

Implement caching for expensive computations:

```swift
@MainActor
final class CachedComponent: Component {
    private var content: String
    private var cachedLines: [String]?
    private var cachedWidth: Int = 0

    func render(width: Int) -> [String] {
        // Return cache if valid
        if let cached = cachedLines, cachedWidth == width {
            return cached
        }

        // Compute and cache
        let lines = expensiveComputation(width: width)
        cachedLines = lines
        cachedWidth = width
        return lines
    }

    func invalidate() {
        cachedLines = nil
        cachedWidth = 0
    }

    func setContent(_ newContent: String) {
        content = newContent
        invalidate()  // Clear cache on content change
    }
}
```

### When to Cache

- Text wrapping (expensive for long content)
- Markdown parsing
- Syntax highlighting
- Complex layout calculations

### When Not to Cache

- Simple static content
- Content that changes every render
- Components with minimal render cost

## Minimizing Render Requests

### Batch State Changes

```swift
// Bad: Multiple renders
component1.setValue(1)
tui.requestRender()
component2.setValue(2)
tui.requestRender()

// Good: Single render after all changes
component1.setValue(1)
component2.setValue(2)
tui.requestRender()
```

### Defer Renders

```swift
// The TUI already defers renders, but you can batch:
func updateMultipleThings() {
    item1.update()
    item2.update()
    item3.update()
    // Single requestRender at the end
    tui.requestRender()
}
```

### Avoid Unnecessary Renders

```swift
func setValue(_ value: Int) {
    // Skip if value unchanged
    guard value != self.value else { return }
    self.value = value
}
```

## Width Calculation

The `visibleWidth()` function handles ANSI codes but can be expensive:

```swift
// Cache width calculations for static styled text
class StyledLabel: Component {
    private let text: String
    private let styledText: String
    private let textWidth: Int

    init(text: String, color: String) {
        self.text = text
        self.styledText = "\u{001B}[\(color)m\(text)\u{001B}[0m"
        self.textWidth = visibleWidth(styledText)  // Calculate once
    }
}
```

### Pre-computed Widths

For repeated width checks:

```swift
struct CachedLine {
    let text: String
    let width: Int

    init(_ text: String) {
        self.text = text
        self.width = visibleWidth(text)
    }
}
```

## Memory Management

### Weak References

Avoid retain cycles in closures:

```swift
button.onClick = { [weak self] in
    self?.handleClick()
}

loader.onComplete = { [weak self, weak loader] in
    guard let self else { return }
    if let loader { tui.removeChild(loader) }
}
```

### Component Lifecycle

Remove components when no longer needed:

```swift
// Clean up loaders
loader.stop()
tui.removeChild(loader)

// Clear containers
container.clear()
```

### History Limits

For components that accumulate data:

```swift
class MessageList {
    private var messages: [Message] = []
    private let maxMessages = 1000

    func addMessage(_ message: Message) {
        messages.append(message)
        if messages.count > maxMessages {
            messages.removeFirst(messages.count - maxMessages)
        }
    }
}
```

## Large Content Handling

### Pagination

Don't render everything at once:

```swift
class PaginatedList: Component {
    private var items: [Item]
    private var pageSize = 20
    private var currentPage = 0

    func render(width: Int) -> [String] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, items.count)
        let pageItems = Array(items[start..<end])

        return pageItems.map { renderItem($0, width: width) }
    }
}
```

### Virtualization

Only render visible items:

```swift
class VirtualizedList: Component {
    private var items: [Item]
    private var scrollOffset = 0
    private var visibleCount = 20

    func render(width: Int) -> [String] {
        let start = scrollOffset
        let end = min(start + visibleCount, items.count)

        var lines: [String] = []
        for i in start..<end {
            lines.append(renderItem(items[i], width: width))
        }
        return lines
    }
}
```

### Lazy Loading

Load content as needed:

```swift
class LazyContent: Component {
    private var loadedChunks: [Int: [String]] = [:]
    private var currentChunk = 0

    func render(width: Int) -> [String] {
        if loadedChunks[currentChunk] == nil {
            loadedChunks[currentChunk] = loadChunk(currentChunk)
        }
        return loadedChunks[currentChunk] ?? []
    }
}
```

## Profiling

### Measure Render Time

```swift
class ProfilingComponent: Component {
    func render(width: Int) -> [String] {
        let start = CFAbsoluteTimeGetCurrent()
        let result = actualRender(width: width)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        if elapsed > 0.016 {  // More than one frame
            print("Slow render: \(elapsed * 1000)ms")
        }
        return result
    }
}
```

### Monitor Memory

```swift
func logMemory() {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    if result == KERN_SUCCESS {
        print("Memory: \(info.resident_size / 1024 / 1024) MB")
    }
}
```

## Best Practices Summary

1. **Cache expensive computations** - Markdown parsing, text wrapping, width calculations
2. **Implement invalidate()** - Clear caches when content changes
3. **Batch state changes** - Single render request after multiple updates
4. **Use weak references** - Prevent retain cycles in closures
5. **Paginate large lists** - Don't render thousands of items
6. **Keep line structure stable** - Better differential rendering
7. **Limit history** - Prevent unbounded memory growth
8. **Profile slow renders** - Identify bottlenecks

## Topics

### Utilities

- ``visibleWidth(_:)``
- ``truncateToWidth(_:maxWidth:ellipsis:pad:)``
- ``wrapTextWithAnsi(_:width:)``

### Component Protocol

- ``Component/invalidate()``
- ``Component/render(width:)``
