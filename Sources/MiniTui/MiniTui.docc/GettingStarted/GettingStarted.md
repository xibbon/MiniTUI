# Getting Started with MiniTui

Build your first terminal user interface application with MiniTui.

@Metadata {
    @PageKind(article)
    @PageColor(blue)
}

## Overview

MiniTui is a Swift framework for building interactive terminal applications. It provides a component-based architecture that handles the complexities of terminal rendering, input handling, and cursor management.

This guide walks you through setting up MiniTui in your project and building your first application.

## Adding MiniTui to Your Project

Add MiniTui as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/MiniTui.git", from: "1.0.0")
]
```

Then add it to your target's dependencies:

```swift
.target(
    name: "MyApp",
    dependencies: ["MiniTui"]
)
```

### Requirements

- Swift 6.2 or later
- macOS 13.0 or later
- A terminal emulator (Terminal.app, iTerm2, Kitty, WezTerm, etc.)

## Your First TUI Application

Create a simple "Hello World" application:

```swift
import MiniTui

@main
struct HelloTUI {
    @MainActor
    static func main() {
        // Create the main TUI container with a terminal
        let tui = TUI(terminal: ProcessTerminal())

        // Add a text component
        let greeting = Text("Hello, MiniTui!", paddingX: 1, paddingY: 1)
        tui.addChild(greeting)

        // Add instructions
        let instructions = Text("Press Ctrl+C to exit", paddingX: 1, paddingY: 0)
        tui.addChild(instructions)

        // Handle Ctrl+C to exit
        tui.onGlobalInput = { input in
            if matchesKey(input, Key.ctrl("c")) {
                tui.stop()
                exit(0)
            }
            return false
        }

        // Start the TUI
        tui.start()

        // Keep the application running
        RunLoop.main.run()
    }
}
```

Build and run:

```bash
swift build
swift run MyApp
```

## Adding Interactivity

Let's enhance the application with an input field:

```swift
import MiniTui

@main
struct InteractiveTUI {
    @MainActor
    static func main() {
        let tui = TUI(terminal: ProcessTerminal())

        let output = Text("Type something and press Enter", paddingX: 1, paddingY: 1)
        let input = Input()

        // Handle submission
        input.onSubmit = { text in
            output.setText("You typed: \(text)")
            tui.requestRender()
        }

        // Handle Ctrl+D on empty input
        input.onEnd = {
            tui.stop()
            exit(0)
        }

        tui.addChild(output)
        tui.addChild(Spacer(1))
        tui.addChild(input)

        // Set focus to the input
        tui.setFocus(input)
        tui.start()

        RunLoop.main.run()
    }
}
```

## Key Concepts

### Components

MiniTui uses a component-based architecture. Every UI element is a ``Component`` that knows how to:
- Render itself to an array of terminal lines
- Handle keyboard input when focused
- Invalidate cached state when content changes

### The TUI Container

The ``TUI`` class is the main container that:
- Manages child components
- Routes keyboard input to the focused component
- Handles differential rendering for optimal performance
- Manages overlays for menus and dialogs

### Focus Management

Only one component receives keyboard input at a time. Use ``TUI/setFocus(_:)`` to direct input to a specific component.

### Rendering

Components render to an array of strings, where each string is one terminal line. The TUI automatically:
- Handles terminal width constraints
- Applies differential updates (only redraws changed lines)
- Manages cursor positioning

## Next Steps

- <doc:CoreConcepts> - Understand the component model in depth
- <doc:YourFirstApp> - Build a complete interactive application
- <doc:ComponentOverview> - Explore all built-in components

## Topics

### Essentials

- <doc:CoreConcepts>
- <doc:YourFirstApp>
- ``TUI``
- ``Component``
