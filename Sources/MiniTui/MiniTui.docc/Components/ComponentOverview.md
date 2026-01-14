# Component Overview

Explore MiniTui's built-in components for building terminal interfaces.

@Metadata {
    @PageKind(article)
    @PageColor(green)
}

## Overview

MiniTui provides a rich set of built-in components for common terminal UI patterns. Each component implements the ``Component`` protocol and can be composed to create complex interfaces.

## Text Display Components

### Text

``Text`` displays multi-line wrapped text with optional padding and background styling.

```swift
let message = Text("Hello, World!", paddingX: 1, paddingY: 1)
message.setText("Updated message")
```

### TruncatedText

``TruncatedText`` displays single-line text that truncates with an ellipsis when it exceeds the available width.

```swift
let status = TruncatedText("Long status message...", paddingX: 0, paddingY: 0)
```

### Markdown

``Markdown`` renders Markdown content with syntax highlighting and theming.

```swift
let content = Markdown("# Hello\n\nThis is **bold** text.", paddingX: 1, paddingY: 1, theme: theme)
```

## Input Components

### Input

``Input`` provides single-line text input with cursor movement and editing shortcuts.

```swift
let input = Input()
input.onSubmit = { text in print("Submitted: \(text)") }
input.onEscape = { print("Cancelled") }
```

### Editor

``Editor`` is a full-featured multi-line editor with autocomplete, history, and paste handling.

```swift
let editor = Editor(theme: editorTheme)
editor.onSubmit = { text in print(text) }
editor.setAutocompleteProvider(provider)
```

## Selection Components

### SelectList

``SelectList`` presents a navigable list of options with filtering support.

```swift
let list = SelectList(
    items: [
        SelectItem(value: "1", label: "Option 1"),
        SelectItem(value: "2", label: "Option 2")
    ],
    maxVisible: 5,
    theme: theme
)
list.onSelect = { item in print("Selected: \(item.value)") }
```

### SettingsList

``SettingsList`` displays configurable settings with value cycling and submenus.

```swift
let settings = SettingsList(
    items: [
        SettingItem(id: "theme", label: "Theme", currentValue: "dark", values: ["dark", "light"])
    ],
    maxVisible: 8,
    theme: theme,
    onChange: { id, value in print("\(id) = \(value)") }
)
```

## Feedback Components

### Loader

``Loader`` displays an animated spinner with a message.

```swift
let loader = Loader(
    ui: tui,
    spinnerColorFn: { $0 },
    messageColorFn: { $0 },
    message: "Loading..."
)
```

### CancellableLoader

``CancellableLoader`` extends Loader with cancellation support via Escape key.

```swift
let loader = CancellableLoader(ui: tui, message: "Processing...")
loader.onAbort = { print("Cancelled") }
```

### Image

``Image`` displays inline images in terminals that support Kitty or iTerm2 protocols.

```swift
let image = Image(
    base64Data: pngData,
    mimeType: "image/png",
    theme: imageTheme,
    options: ImageOptions(maxWidthCells: 40)
)
```

## Layout Components

### Container

``Container`` groups child components vertically.

```swift
let section = Container()
section.addChild(Text("Title"))
section.addChild(content)
```

### Box

``Box`` wraps children with padding and optional background styling.

```swift
let box = Box(paddingX: 2, paddingY: 1, bgFn: { $0 })
box.addChild(Text("Boxed content"))
```

### Spacer

``Spacer`` adds vertical space between components.

```swift
tui.addChild(header)
tui.addChild(Spacer(2))  // Two empty lines
tui.addChild(content)
```

## Component Comparison

| Component | Lines | Input | Use Case |
|-----------|-------|-------|----------|
| Text | Multi | No | Static or dynamic text display |
| TruncatedText | Single | No | Status bars, headers |
| Markdown | Multi | No | Rich formatted content |
| Input | Single | Yes | Form fields, commands |
| Editor | Multi | Yes | Code, long-form text |
| SelectList | Multi | Yes | Menus, option selection |
| SettingsList | Multi | Yes | Configuration panels |
| Loader | Single | No | Progress indication |
| CancellableLoader | Single | Yes | Cancellable operations |
| Image | Multi | No | Visual content |
| Container | Multi | No | Grouping |
| Box | Multi | No | Styled grouping |
| Spacer | Multi | No | Vertical spacing |

## Theming

Most components accept theme objects for customization:

```swift
let theme = SelectListTheme(
    selectedPrefix: { "\u{001B}[32m>\u{001B}[0m " + $0 },  // Green arrow
    selectedText: { "\u{001B}[1m\($0)\u{001B}[0m" },       // Bold
    description: { "\u{001B}[90m\($0)\u{001B}[0m" },       // Gray
    scrollInfo: { $0 },
    noMatch: { "\u{001B}[33m\($0)\u{001B}[0m" }            // Yellow
)
```

Theme functions transform text strings, allowing you to apply ANSI styling codes.

## Topics

### Text Display

- ``Text``
- ``TruncatedText``
- ``Markdown``

### Input

- ``Input``
- ``Editor``

### Selection

- ``SelectList``
- ``SettingsList``

### Feedback

- ``Loader``
- ``CancellableLoader``
- ``Image``

### Layout

- ``Container``
- ``Box``
- ``Spacer``
