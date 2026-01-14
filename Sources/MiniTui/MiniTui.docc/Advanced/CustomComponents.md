# Creating Custom Components

Build reusable components tailored to your application's needs.

@Metadata {
    @PageKind(article)
    @PageColor(orange)
}

## Overview

While MiniTui provides many built-in components, you'll often need custom components for specific functionality. This guide covers the ``Component`` protocol, rendering best practices, and patterns for building robust custom components.

## The Component Protocol

Every component implements the ``Component`` protocol:

```swift
@MainActor
public protocol Component: AnyObject {
    func render(width: Int) -> [String]
    func handleInput(_ data: String)
    var wantsKeyRelease: Bool { get }
    func invalidate()
}
```

### Required: render(width:)

Returns an array of strings, where each string is one terminal line:

```swift
func render(width: Int) -> [String] {
    return ["Line 1", "Line 2", "Line 3"]
}
```

### Optional: handleInput(_:)

Receives raw terminal input when the component has focus. Default implementation does nothing.

### Optional: wantsKeyRelease

Return `true` to receive Kitty key release events. Default is `false`.

### Optional: invalidate()

Clear cached render state. Called when the component should re-render from scratch.

## Basic Custom Component

Here's a simple progress bar component:

```swift
@MainActor
final class ProgressBar: Component {
    private var progress: Double = 0  // 0.0 to 1.0
    private var label: String
    private let width: Int
    private let filledChar: Character = "█"
    private let emptyChar: Character = "░"

    init(label: String, width: Int = 30) {
        self.label = label
        self.width = width
    }

    func setProgress(_ value: Double) {
        progress = max(0, min(1, value))
    }

    func setLabel(_ text: String) {
        label = text
    }

    func render(width: Int) -> [String] {
        let barWidth = min(self.width, width - label.count - 10)
        let filled = Int(Double(barWidth) * progress)
        let empty = barWidth - filled

        let bar = String(repeating: filledChar, count: filled) +
                  String(repeating: emptyChar, count: empty)
        let percent = String(format: "%3.0f%%", progress * 100)

        return ["\(label) [\(bar)] \(percent)"]
    }

    func handleInput(_ data: String) {}
    func invalidate() {}
}
```

Usage:

```swift
let progress = ProgressBar(label: "Downloading")
tui.addChild(progress)

// Update progress
progress.setProgress(0.5)
tui.requestRender()
```

## Interactive Component

Components that handle input need to implement `handleInput(_:)`:

```swift
@MainActor
final class Counter: Component {
    private var value: Int = 0
    var onChange: ((Int) -> Void)?

    func render(width: Int) -> [String] {
        let line = "Count: \(value)  [↑/↓ to change, Enter to confirm]"
        return [truncateToWidth(line, maxWidth: width)]
    }

    func handleInput(_ data: String) {
        if matchesKey(data, Key.up) {
            value += 1
            onChange?(value)
        } else if matchesKey(data, Key.down) {
            value -= 1
            onChange?(value)
        }
    }

    func invalidate() {}
}
```

## Component with Caching

For expensive renders, cache the output:

```swift
@MainActor
final class ExpensiveComponent: Component {
    private var content: String
    private var cachedLines: [String]?
    private var cachedWidth: Int = 0

    init(content: String) {
        self.content = content
    }

    func setContent(_ newContent: String) {
        content = newContent
        invalidate()
    }

    func render(width: Int) -> [String] {
        // Return cache if valid
        if let cached = cachedLines, cachedWidth == width {
            return cached
        }

        // Perform expensive computation
        let lines = computeExpensiveLayout(width: width)

        // Cache result
        cachedLines = lines
        cachedWidth = width

        return lines
    }

    func invalidate() {
        cachedLines = nil
        cachedWidth = 0
    }

    private func computeExpensiveLayout(width: Int) -> [String] {
        // Expensive computation here
        return wrapTextWithAnsi(content, width: width)
    }
}
```

## Component with Children

Container-like components manage child components:

```swift
@MainActor
final class Panel: Component {
    private var title: String
    private var children: [Component] = []

    init(title: String) {
        self.title = title
    }

    func addChild(_ child: Component) {
        children.append(child)
    }

    func render(width: Int) -> [String] {
        var lines: [String] = []

        // Title bar
        let titleLine = "┌─ \(title) " + String(repeating: "─", count: max(0, width - title.count - 5)) + "┐"
        lines.append(truncateToWidth(titleLine, maxWidth: width))

        // Children
        for child in children {
            let childLines = child.render(width: width - 4)  // Account for borders
            for line in childLines {
                lines.append("│ " + truncateToWidth(line, maxWidth: width - 4, ellipsis: "", pad: true) + " │")
            }
        }

        // Bottom border
        lines.append("└" + String(repeating: "─", count: max(0, width - 2)) + "┘")

        return lines
    }

    func handleInput(_ data: String) {
        // Forward to focused child if needed
    }

    func invalidate() {
        children.forEach { $0.invalidate() }
    }
}
```

## Handling ANSI Codes

When working with styled text, use the utility functions:

```swift
func render(width: Int) -> [String] {
    // visibleWidth excludes ANSI codes from width calculation
    let styledText = "\u{001B}[31mRed text\u{001B}[0m"
    let actualWidth = visibleWidth(styledText)  // Returns 8, not 17

    // truncateToWidth handles ANSI codes correctly
    let truncated = truncateToWidth(styledText, maxWidth: 5)  // "Red t..."

    // wrapTextWithAnsi preserves styles across line breaks
    let wrapped = wrapTextWithAnsi(styledText, width: 4)
    // Returns: ["\u{001B}[31mRed \u{001B}[0m", "\u{001B}[31mtext\u{001B}[0m"]

    return wrapped
}
```

## System Cursor Support

Components can opt into system cursor positioning:

```swift
@MainActor
final class CursorInput: Component, SystemCursorAware {
    var usesSystemCursor: Bool = false
    private var text: String = ""
    private var cursorPos: Int = 0

    func render(width: Int) -> [String] {
        var line = text
        if usesSystemCursor && cursorPos <= text.count {
            // Insert cursor marker at position
            let index = text.index(text.startIndex, offsetBy: cursorPos)
            line = String(text[..<index]) + systemCursorMarker + String(text[index...])
        }
        return [truncateToWidth(line, maxWidth: width)]
    }
}
```

The TUI will position the terminal cursor at `systemCursorMarker` when `useSystemCursor` is enabled.

## Best Practices

### 1. Respect Width

Always fit output within the provided width:

```swift
func render(width: Int) -> [String] {
    return lines.map { truncateToWidth($0, maxWidth: width) }
}
```

### 2. Handle Edge Cases

```swift
func render(width: Int) -> [String] {
    guard width > 0 else { return [] }
    guard !content.isEmpty else { return ["(empty)"] }
    // Normal rendering
}
```

### 3. Use Weak References

Avoid retain cycles with closures:

```swift
button.onClick = { [weak self] in
    self?.handleClick()
}
```

### 4. Request Renders After State Changes

```swift
func setValue(_ value: Int) {
    self.value = value
    // Don't render here - let the TUI manage it
}
```

The parent should call `tui.requestRender()` after state changes.

### 5. Implement invalidate() for Cached Components

```swift
func invalidate() {
    cachedLines = nil
    children.forEach { $0.invalidate() }
}
```

## Common Patterns

### Theming

Accept a theme object for customization:

```swift
struct ProgressTheme {
    let filledColor: (String) -> String
    let emptyColor: (String) -> String
    let labelColor: (String) -> String
}

@MainActor
final class ThemedProgress: Component {
    private let theme: ProgressTheme

    init(theme: ProgressTheme) {
        self.theme = theme
    }

    func render(width: Int) -> [String] {
        let filled = theme.filledColor("████")
        let empty = theme.emptyColor("░░░░")
        return [filled + empty]
    }
}
```

### Event Callbacks

Use closures for component events:

```swift
@MainActor
final class Button: Component {
    var onPress: (() -> Void)?
    var onCancel: (() -> Void)?

    func handleInput(_ data: String) {
        if matchesKey(data, Key.enter) {
            onPress?()
        } else if matchesKey(data, Key.escape) {
            onCancel?()
        }
    }
}
```

### Composition Over Inheritance

Prefer composing existing components:

```swift
@MainActor
final class LabeledInput: Component {
    private let label: Text
    private let input: Input

    init(labelText: String) {
        label = Text(labelText, paddingX: 0, paddingY: 0)
        input = Input()
    }

    func render(width: Int) -> [String] {
        return label.render(width: width) + input.render(width: width)
    }

    func handleInput(_ data: String) {
        input.handleInput(data)
    }
}
```

## Topics

### Protocol

- ``Component``

### Utilities

- ``visibleWidth(_:)``
- ``truncateToWidth(_:maxWidth:ellipsis:pad:)``
- ``wrapTextWithAnsi(_:width:)``
- ``matchesKey(_:_:)``
