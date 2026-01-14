# MiniTui

A minimal, high-performance Terminal User Interface framework for Swift.

[![CI](https://github.com/user/MiniTui/actions/workflows/ci.yml/badge.svg)](https://github.com/user/MiniTui/actions/workflows/ci.yml)
[![Documentation](https://github.com/user/MiniTui/actions/workflows/docs.yml/badge.svg)](https://user.github.io/MiniTui/)

## Features

- **Differential rendering** with synchronized output (CSI 2026) for flicker-free updates
- **Component-based architecture** with simple protocol-based API
- **Kitty keyboard protocol** support with legacy fallback
- **Built-in components**: Text, Input, Editor, Markdown, SelectList, SettingsList, Loader, Image, and more
- **Inline images** via Kitty or iTerm2 protocols
- **Autocomplete** for slash commands and file paths
- **Theming** with customizable styling functions

## Requirements

- Swift 6.2+
- macOS 13.0+

## Installation

Add MiniTui to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/user/MiniTui.git", from: "1.0.0")
]
```

Then add it to your target:

```swift
.target(
    name: "MyApp",
    dependencies: ["MiniTui"]
)
```

## Quick Start

```swift
import MiniTui

@main
struct Demo {
    @MainActor
    static func main() {
        let tui = TUI(terminal: ProcessTerminal())
        let output = Text("Type something and press Enter.", paddingX: 1, paddingY: 1)
        let input = Input()

        input.onSubmit = { text in
            output.setText("You typed: \(text)")
            tui.requestRender()
        }

        input.onEnd = {
            tui.stop()
            exit(0)
        }

        tui.addChild(output)
        tui.addChild(input)
        tui.setFocus(input)
        tui.start()

        RunLoop.main.run()
    }
}
```

## Build

```sh
swift build
```

## Run Demo

```sh
swift run MiniTuiDemo
```

Press Ctrl+D on empty input to exit.

## Test

```sh
swift test
```

## Documentation

Full documentation is available at **[MiniTui Documentation](https://user.github.io/MiniTui/)**.

The documentation includes:

- **Getting Started** - Installation, core concepts, your first app
- **Component Guide** - All built-in components with examples
- **Tutorials** - Build a chat interface, file browser, settings panel
- **Advanced Topics** - Custom components, overlays, keyboard handling, performance
- **Reference** - Themes, keys, terminal compatibility

## License

MIT
