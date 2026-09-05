# MiniTui

A minimal, high-performance Terminal User Interface framework for Swift.

[![CI](https://github.com/user/MiniTui/actions/workflows/ci.yml/badge.svg)](https://github.com/user/MiniTui/actions/workflows/ci.yml)
[![Documentation](https://github.com/user/MiniTui/actions/workflows/docs.yml/badge.svg)](https://user.github.io/MiniTui/)

## Features

- **Differential rendering** with synchronized output (CSI 2026) for flicker-free updates
- **Component-based architecture** with simple protocol-based API
- **Kitty keyboard protocol** support with legacy fallback
- **Built-in components**: Text, Input, Editor, Markdown, SelectList, SettingsList, MouseRegion, Loader, Image, and more
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

## Mouse handling (v0.85.0)

`Component.handleMouse(_:)` has a default implementation that returns `nil`.
Existing components do not need changes. Use `MouseRegion(child:onMouse:)` to add
mouse handling to a component. Use `dispatchMouseEvent(_:_:)` to retain the child
and its coordinate transform. Use `retargetMouseEvent(_:_:)` for later captured events.

`Container` and `Box` route events using the last rendered child heights. A container
that owns keyboard input for its children can conform to `MouseFocusOwner`. This is
an explicit opt-in because Swift cannot detect an overridden default input method.

`OverlayHandle.getBounds()` returns the last rendered rectangle for a visible overlay.
`TUI.dispatchMouseToOverlay(_:)`, `isOverlayFocused()`, and `resolveMouseFocusTarget(_:)`
supply the shared overlay services. Main-screen input stays with the terminal.
`AltScreenRenderer` sends wheel, press, drag, release, move, and click events to
components and overlays. Capture keeps a gesture with its component. A handled
press clears text selection. A click requires press and release in the same cell.
Click counts cycle from 1 to 3. Move and release events do not request a render by
default. Set `render: true` to show a hover change.

Unhandled drags select text. `AltScreenRendererOptions.copyOnSelect` defaults to
true. Set it to false to keep a selection without automatic copy. Use
`hasActiveSelection()` and `await copyActiveSelectionToClipboard()` for explicit
copy. The optional `copySelection` callback takes the text and returns an async
success flag. The renderer shows `Copied!` or `Copy failed`. Without a callback,
it writes OSC 52. `getCopyOnSelect()` and `setCopyOnSelect(_:)` read and change this
setting.

Press Ctrl+Shift+F to open or close transcript search. Enter or Ctrl+G goes to the
next match. Shift+Enter or Ctrl+Shift+G goes to the previous match. Escape closes
search. The bordered panel also has clickable arrow buttons. Configure
`searchMatchStyle`, `searchCurrentMatchStyle`, and `searchNavigationButtonStyle`
in `AltScreenRendererOptions` to change their styles. The navigation style gets
both the button text and its hover state.

Supply `scrollToEndIndicator` to show a clickable label on the last row of a
primary follow-end scroll view when it is away from the end. A click resumes
following. Scrollbars support track clicks, thumb drag, and hover. Use
`scrollbarTrackStyle` and `scrollbarThumbStyle` in `ScrollViewOptions`; these replace
`scrollbarStyle`. Read `followEnd` and `isScrollbarActive` for their current state.
`scrollTo(_:options: ScrollViewScrollToOptions(disableFollow: true))` can hold the
position at the end without enabling follow mode.

`Input(options:)` accepts `InputOptions(prompt:placeholder:placeholderStyle:)`.
`Focusable` supplies optional focus state. The input mouse handler uses the upstream
fixed two-column prompt offset, including when a custom prompt is used.
`Editor(ui:theme:options:)` can use the TUI terminal height to limit visible text rows.
Calls without `ui` retain the existing unbounded layout. Editor border hooks and
`Loader.getRenderedIndicator()` can be overridden outside the package.

Use `SettingItem.submenuWithNavigation` for a submenu callback with
`done(value, options: SettingsSubmenuOptions(navigateTo: id))`. It closes the submenu,
selects the target setting, and activates it. The existing `submenu` closure is retained.

The hardware cursor and clear-on-shrink settings default to false. Set
`showHardwareCursor` in `TUI.init` or use `useSystemCursor`; call `setClearOnShrink(_:)`
to change shrink behavior. Supply `logDirectory` and `PI_TUI_DEBUG_REDRAW=1` for redraw
logs. Crash dumps use that directory or the OS temporary directory.

`StdinBufferOptions` uses seconds: `timeout` defaults to 0.05 and `escapeTimeout` to
0.01. `ProcessTerminal` uses `PI_TUI_ESC_TIMEOUT` in milliseconds, or 100 ms over SSH.
Capability environment overrides are `PI_HYPERLINKS`, `PI_IMAGE_PROTOCOL`, and
`PI_TRUE_COLOR`. `setCapabilityOverrides(_:)` replaces the programmatic override set.
For `TerminalCapabilityOverrides.images`, `nil` means automatic detection and
`.some(nil)` disables images. An unchanged override set retains the cache.
