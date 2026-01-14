# MiniTui

Terminal UI components for Swift.

## Origin

MiniTui is a machine Swift port of `pi-mono/packages/tui` by Mario Zechner.

## Features

- Differential rendering with synchronized output (CSI 2026) for flicker-free updates
- Bracketed paste handling and Kitty keyboard protocol support
- Component-based API with theme hooks and caching
- Built-in components: Text, TruncatedText, Input, Editor, Markdown, Loader, CancellableLoader, SelectList, SettingsList, Spacer, Image, Box, Container
- Inline images via Kitty or iTerm2 protocols, with fallback text
- Autocomplete for slash commands and file paths
- Fuzzy matching helpers for lists and autocomplete

## Build

```sh
swift build
```

## Run

```sh
swift run MiniTuiDemo
```

Press Ctrl-D on empty input to exit.

## Test

```sh
swift test
```

## Usage

```swift
import Foundation
import Darwin
import MiniTui

@main
struct Demo {
    @MainActor
    static func main() {
        let tui = TUI(terminal: ProcessTerminal())
        let header = Text("MiniTui demo", paddingX: 1, paddingY: 0)
        let output = Text("Type something and press Enter. Ctrl-D exits on empty input.", paddingX: 1, paddingY: 0)
        let input = Input()

        input.onSubmit = { @MainActor [weak tui, weak output] text in
            output?.setText("You typed: \(text)")
            tui?.requestRender()
        }
        input.onEnd = { [weak tui] in
            tui?.stop()
            exit(0)
        }

        tui.addChild(header)
        tui.addChild(Spacer(1))
        tui.addChild(output)
        tui.addChild(Spacer(1))
        tui.addChild(input)

        tui.setFocus(input)
        tui.start()

        RunLoop.main.run()
    }
}
```

## Core API

### TUI

Main container that manages components and rendering.

```swift
let tui = TUI(terminal: ProcessTerminal())

tui.onDebug = {
    print("Debug")
}

tui.onGlobalInput = { input in
    if matchesKey(input, Key.ctrl("c")) {
        return true
    }
    return false
}

tui.addChild(Text("Hello"))
tui.setFocus(input)
tui.start()
```

Useful calls and properties:
- `addChild(_:)`, `removeChild(_:)`, `clear()` via `Container`
- `setFocus(_:)` to route input to a component
- `requestRender()` after state changes
- `start()` and `stop()` for terminal lifecycle
- `useSystemCursor` to show the terminal cursor instead of a custom cursor

### Component Protocol

```swift
@MainActor
public protocol Component: AnyObject {
    func render(width: Int) -> [String]
    func handleInput(_ data: String)
    var wantsKeyRelease: Bool { get }
    func invalidate()
}
```

Rendering notes:
- Each rendered line should fit within `width`. The TUI truncates overflow, but layout is more predictable when components keep lines within bounds.
- The TUI appends a full SGR and OSC 8 reset at the end of each line. If you emit multi-line styled text, reapply styles per line or use `wrapTextWithAnsi()`.

## Overlays

Overlays render a component on top of existing content for menus, dialogs, or transient UI.
`showOverlay` returns a handle for hiding or removing the overlay.

```swift
let menu = Box(paddingX: 1, paddingY: 1)
menu.addChild(Text("Overlay menu"))

let handle = tui.showOverlay(menu, options: OverlayOptions(
    width: .percent(60),
    minWidth: 40,
    maxHeight: .percent(50),
    anchor: .bottomRight,
    offsetX: -2,
    offsetY: -1,
    margin: OverlayMargin(all: 1),
    visible: { termWidth, _ in termWidth >= 80 }
))

handle.setHidden(true)  // Temporarily hide
handle.setHidden(false) // Show again
handle.hide()           // Remove permanently
```

You can also call `tui.hideOverlay()` to remove the topmost overlay.

`OverlayOptions` supports `row`/`col` positioning as absolute values or percent values:

```swift
let options = OverlayOptions(row: .percent(25), col: 10)
```

Anchor values: `center`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight`,
`topCenter`, `bottomCenter`, `leftCenter`, `rightCenter`.

Sizing and positioning notes:
- `SizeValue` accepts integer literals for absolute values, or `.percent(50)` for percentages.
- `minWidth` is applied after width calculation.
- Positioning order is `row`/`col` (absolute or percent) first, then `anchor`.
- `margin` clamps the overlay to the terminal bounds.
- `visible` is evaluated every render to toggle visibility.

## Built-in Components

### Container

Groups child components.

```swift
let container = Container()
let child = Text("Child")
container.addChild(child)
container.removeChild(child)
```

### Box

Container with padding and optional background styling.

```swift
let box = Box(paddingX: 1, paddingY: 1, bgFn: { $0 })
box.addChild(Text("Content"))
box.setBgFn { text in text }
```

### Text

Wrapped, multi-line text with padding and optional background styling.

```swift
let text = Text("Hello World", paddingX: 1, paddingY: 1)
text.setText("Updated")
text.setCustomBgFn { $0 }
```

### TruncatedText

Single-line text that truncates to fit the available width.

```swift
let truncated = TruncatedText("Long line", paddingX: 0, paddingY: 0)
```

### Input

Single-line input with cursor and editing shortcuts.

```swift
let input = Input()
input.onSubmit = { value in print(value) }
input.onEscape = { print("cancel") }
input.onEnd = { print("end") }
input.setValue("initial")
```

Key bindings:
- `Enter` submit
- `Esc` or `Ctrl+C` cancel
- `Ctrl+D` end when empty
- `Ctrl+A` / `Ctrl+E` line start/end
- `Ctrl+W` or `Alt+Backspace` delete word backward
- `Ctrl+U` delete to start of line
- `Ctrl+K` delete to end of line
- `Ctrl+Left` / `Ctrl+Right` or `Alt+Left` / `Alt+Right` word navigation
- Arrow keys, Backspace, Delete

### Editor

Multi-line editor with history, autocomplete, and paste handling.

```swift
let listTheme = SelectListTheme(
    selectedPrefix: { $0 },
    selectedText: { $0 },
    description: { $0 },
    scrollInfo: { $0 },
    noMatch: { $0 }
)
let editorTheme = EditorTheme(borderColor: { $0 }, selectList: listTheme)
let editor = Editor(theme: editorTheme)

editor.onSubmit = { text in print(text) }
editor.onChange = { text in print("Changed: \(text)") }
editor.disableSubmit = false
```

Features:
- Multi-line editing with word wrap
- Slash command autocomplete (type `/`)
- File path autocomplete (press `Tab`)
- Large paste handling with markers like `[paste #1 +50 lines]`
- History navigation with Up/Down

Key bindings:
- `Enter` submit
- `Shift+Enter`, `Ctrl+Enter`, or `Alt+Enter` new line (terminal-dependent)
- `Tab` autocomplete
- `Ctrl+K` delete to end of line
- `Ctrl+A` / `Ctrl+E` line start/end
- Arrow keys, Backspace, Delete

### Markdown

Renders Markdown with theming support.

```swift
let theme = MarkdownTheme(
    heading: { $0 },
    link: { $0 },
    linkUrl: { $0 },
    code: { $0 },
    codeBlock: { $0 },
    codeBlockBorder: { $0 },
    quote: { $0 },
    quoteBorder: { $0 },
    hr: { $0 },
    listBullet: { $0 },
    bold: { $0 },
    italic: { $0 },
    strikethrough: { $0 },
    underline: { $0 }
)

let md = Markdown("# Hello", paddingX: 1, paddingY: 1, theme: theme)
md.setText("Updated markdown")
```

### Loader

Animated spinner that re-renders on a timer.

```swift
let loader = Loader(
    ui: tui,
    spinnerColorFn: { $0 },
    messageColorFn: { $0 },
    message: "Loading..."
)
loader.setMessage("Still loading...")
loader.stop()
```

### CancellableLoader

Loader that cancels on Escape and exposes a cancellation signal.

```swift
let loader = CancellableLoader(
    ui: tui,
    spinnerColorFn: { $0 },
    messageColorFn: { $0 },
    message: "Working..."
)
loader.onAbort = { print("aborted") }
loader.signal.onCancel { print("cancelled") }
```

### SelectList

Interactive selection list with keyboard navigation.

```swift
let list = SelectList(
    items: [
        SelectItem(value: "opt1", label: "Option 1"),
        SelectItem(value: "opt2", label: "Option 2")
    ],
    maxVisible: 5,
    theme: listTheme
)

list.onSelect = { item in print(item.value) }
list.onCancel = { print("cancel") }
list.onSelectionChange = { item in print("highlight: \(item.value)") }
list.setFilter("opt")
```

Controls:
- Up/Down to navigate
- Enter to select
- Escape or Ctrl+C to cancel

### SettingsList

Settings panel with value cycling, submenus, and optional search.

```swift
let settingsTheme = SettingsListTheme(
    label: { text, _ in text },
    value: { text, _ in text },
    description: { $0 },
    cursor: "> ",
    hint: { $0 }
)

let settings = SettingsList(
    items: [
        SettingItem(id: "theme", label: "Theme", currentValue: "dark", values: ["dark", "light"]),
        SettingItem(id: "model", label: "Model", currentValue: "gpt-4", submenu: { _, _ in
            return Text("Select model")
        })
    ],
    maxVisible: 8,
    theme: settingsTheme,
    onChange: { id, newValue in print("\(id) -> \(newValue)") },
    onCancel: { print("cancel") },
    options: SettingsListOptions(enableSearch: true)
)

settings.updateValue(id: "theme", newValue: "light")
```

Controls:
- Up/Down to navigate
- Enter or Space to activate (cycle value or open submenu)
- Escape or Ctrl+C to cancel

Search filters by `label` with fuzzy matching. Space-separated tokens must all match.

### Spacer

Empty lines for vertical spacing.

```swift
let spacer = Spacer(2)
```

### Image

Inline images for terminals that support Kitty or iTerm2 protocols, with fallback text otherwise.

```swift
let image = Image(
    base64Data: pngData,
    mimeType: "image/png",
    theme: ImageTheme(fallbackColor: { $0 }),
    options: ImageOptions(maxWidthCells: 40, maxHeightCells: 10, filename: "sample.png")
)
```

Supported formats: PNG, JPEG, GIF, WebP.

## Autocomplete

Use `CombinedAutocompleteProvider` for slash commands and file paths.

```swift
let provider = CombinedAutocompleteProvider(
    commands: [
        SlashCommand(name: "help", description: "Show help"),
        SlashCommand(name: "clear", description: "Clear screen")
    ],
    items: [
        AutocompleteItem(value: "status", label: "status", description: "Show status")
    ],
    basePath: FileManager.default.currentDirectoryPath,
    fdPath: "/opt/homebrew/bin/fd"
)

editor.setAutocompleteProvider(provider)
```

Features:
- Type `/` to see slash commands
- Press `Tab` for file path completion
- Works with `~/`, `./`, `../`, and `@` prefix
- Filters to attachable files for `@` prefix

## Key Detection

Use `matchesKey()` with the `Key` helper for keyboard input (legacy and Kitty keyboard protocol).

```swift
if matchesKey(data, Key.ctrl("c")) {
    exit(0)
}

if matchesKey(data, Key.enter) {
    submit()
} else if matchesKey(data, Key.escape) {
    cancel()
}
```

Key identifiers:
- Basic keys: `Key.enter`, `Key.escape`, `Key.tab`, `Key.space`, `Key.backspace`, `Key.delete`, `Key.home`, `Key.end`, `Key.pageUp`, `Key.pageDown`
- Arrow keys: `Key.up`, `Key.down`, `Key.left`, `Key.right`
- Modifiers: `Key.ctrl("c")`, `Key.shift("tab")`, `Key.alt("left")`, `Key.ctrlShift("p")`
- String format also works: `"enter"`, `"ctrl+c"`, `"shift+tab"`

To customize editor keybindings:

```swift
let manager = EditorKeybindingsManager(config: EditorKeybindingsConfig([
    .submit: [Key.ctrl("enter")]
]))
setEditorKeybindings(manager)
```

## Utilities

```swift
let width = visibleWidth("\u{001B}[31mHello\u{001B}[0m")
let truncated = truncateToWidth("Hello World", maxWidth: 8)
let truncatedNoEllipsis = truncateToWidth("Hello World", maxWidth: 8, ellipsis: "")
let padded = truncateToWidth("Hi", maxWidth: 6, ellipsis: "", pad: true)

let lines = wrapTextWithAnsi("This is a long line that needs wrapping", width: 20)
```

## Creating Custom Components

When creating custom components, render lines that fit the provided width. Use the utilities to handle ANSI codes and truncation.

```swift
final class MyComponent: Component {
    private var items = ["Option 1", "Option 2", "Option 3"]
    private var selectedIndex = 0

    func handleInput(_ data: String) {
        if matchesKey(data, Key.up) {
            selectedIndex = max(0, selectedIndex - 1)
        } else if matchesKey(data, Key.down) {
            selectedIndex = min(items.count - 1, selectedIndex + 1)
        }
    }

    func render(width: Int) -> [String] {
        return items.enumerated().map { index, item in
            let prefix = index == selectedIndex ? "> " : "  "
            return truncateToWidth(prefix + item, maxWidth: width)
        }
    }

    func invalidate() {}
}
```

## Terminal Interface

The TUI works with any object implementing `Terminal`:

```swift
public protocol Terminal: AnyObject {
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void)
    func stop()
    func write(_ data: String)
    var columns: Int { get }
    var rows: Int { get }
    var kittyProtocolActive: Bool { get }
    func moveBy(lines: Int)
    func hideCursor()
    func showCursor()
    func clearLine()
    func clearFromCursor()
    func clearScreen()
    func setTitle(_ title: String)
}
```

Built-in implementation:
- `ProcessTerminal` uses stdin/stdout and enables raw mode.
