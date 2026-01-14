# Core Concepts

Understand the fundamental architecture of MiniTui applications.

@Metadata {
    @PageKind(article)
    @PageColor(blue)
}

## Overview

MiniTui is built around a few core concepts: components, the TUI container, focus management, and rendering. Understanding these concepts will help you build effective terminal applications.

## The Component Protocol

At the heart of MiniTui is the ``Component`` protocol:

```swift
@MainActor
public protocol Component: AnyObject {
    func render(width: Int) -> [String]
    func handleInput(_ data: String)
    var wantsKeyRelease: Bool { get }
    func invalidate()
}
```

### Rendering

The `render(width:)` method returns an array of strings, where each string represents one line in the terminal. Lines should fit within the provided width; the TUI will truncate overflow.

```swift
func render(width: Int) -> [String] {
    return [
        truncateToWidth("Line 1: Some content", maxWidth: width),
        truncateToWidth("Line 2: More content", maxWidth: width)
    ]
}
```

### Input Handling

When a component has focus, its `handleInput(_:)` method receives raw terminal input. Use ``matchesKey(_:_:)`` to detect specific keys:

```swift
func handleInput(_ data: String) {
    if matchesKey(data, Key.enter) {
        submit()
    } else if matchesKey(data, Key.escape) {
        cancel()
    }
}
```

### Invalidation

Call `invalidate()` to clear cached render state. This is useful when content changes and the component needs to re-render.

## The TUI Container

``TUI`` is the top-level container that orchestrates rendering and input:

```swift
let tui = TUI(terminal: ProcessTerminal())

// Add components
tui.addChild(header)
tui.addChild(content)
tui.addChild(input)

// Set focus and start
tui.setFocus(input)
tui.start()
```

### Component Hierarchy

Components are arranged in a hierarchy:
- ``TUI`` extends ``Container``, which manages child components
- Child components render in order (top to bottom)
- You can nest containers for complex layouts

```swift
let section = Container()
section.addChild(Text("Section Title"))
section.addChild(Text("Section content"))

tui.addChild(section)
tui.addChild(Spacer(1))
tui.addChild(anotherSection)
```

### Global Input Handling

Use `onGlobalInput` to intercept input before it reaches the focused component:

```swift
tui.onGlobalInput = { input in
    if matchesKey(input, Key.ctrl("c")) {
        tui.stop()
        exit(0)
    }
    return false // Return true to consume the input
}
```

## Focus Management

Focus determines which component receives keyboard input. Only one component can have focus at a time.

```swift
// Set focus to a component
tui.setFocus(editor)

// Remove focus
tui.setFocus(nil)
```

When using overlays, focus automatically transfers to the overlay component and restores when the overlay is dismissed.

## Rendering Pipeline

MiniTui uses a three-tier rendering strategy for optimal performance:

### First Render
On the first render, all lines are output to the terminal. This preserves scrollback history.

### Width Change
When the terminal width changes, the TUI clears the screen and performs a full re-render.

### Differential Update
For subsequent renders, only changed lines are updated:
1. The TUI compares new lines with previous lines
2. Only different lines are redrawn
3. Updates are wrapped in CSI 2026 for flicker-free output

### Requesting Renders

After modifying component state, request a render:

```swift
output.setText("New content")
tui.requestRender()
```

For a full redraw, use the force parameter:

```swift
tui.requestRender(force: true)
```

## Terminal Lifecycle

### Starting

Call `start()` to:
- Put the terminal in raw mode
- Enable bracketed paste handling
- Query and enable Kitty keyboard protocol (if supported)
- Begin the render loop

```swift
tui.start()
RunLoop.main.run()
```

### Stopping

Call `stop()` to:
- Restore terminal state
- Move cursor below rendered content
- Show cursor

```swift
tui.stop()
exit(0)
```

## ANSI Handling

MiniTui handles ANSI escape codes throughout the rendering pipeline:

- **Width calculation**: ANSI codes are excluded from width calculations
- **Line resets**: Each line ends with a full SGR and OSC 8 reset
- **Style continuity**: Use `wrapTextWithAnsi()` for multi-line styled text

```swift
// Correct: style is preserved across wrapped lines
let lines = wrapTextWithAnsi("\u{001B}[31mRed text that wraps\u{001B}[0m", width: 20)

// Each line will maintain the red color
```

## Main Actor Requirement

The ``Component`` protocol and ``TUI`` are marked with `@MainActor`. All UI operations must run on the main thread:

```swift
@main
struct App {
    @MainActor
    static func main() {
        // UI code here
    }
}
```

When updating UI from async contexts, use `Task { @MainActor in ... }`:

```swift
Task {
    let result = await fetchData()
    Task { @MainActor in
        output.setText(result)
        tui.requestRender()
    }
}
```

## Topics

### Core Types

- ``Component``
- ``TUI``
- ``Container``
- ``Terminal``
- ``ProcessTerminal``
