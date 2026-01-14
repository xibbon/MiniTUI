# Input Components

Handle user text input with single-line and multi-line editors.

@Metadata {
    @PageKind(article)
    @PageColor(green)
}

## Overview

MiniTui provides two input components: ``Input`` for single-line text entry and ``Editor`` for multi-line editing with advanced features like autocomplete and history.

## Input

The ``Input`` component provides single-line text input with cursor movement and editing shortcuts.

### Basic Usage

```swift
let input = Input()

input.onSubmit = { text in
    print("User entered: \(text)")
}

tui.addChild(input)
tui.setFocus(input)
```

### Event Handlers

```swift
input.onSubmit = { text in
    // Called when user presses Enter
    processInput(text)
}

input.onEscape = {
    // Called when user presses Escape or Ctrl+C
    cancelInput()
}

input.onEnd = {
    // Called when user presses Ctrl+D on empty input
    quitApplication()
}
```

### Setting Initial Value

```swift
input.setValue("initial text")
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Enter | Submit input |
| Escape / Ctrl+C | Cancel |
| Ctrl+D | End (when empty) |
| Left / Right | Move cursor |
| Home / Ctrl+A | Move to start |
| End / Ctrl+E | Move to end |
| Ctrl+Left / Alt+Left | Move word left |
| Ctrl+Right / Alt+Right | Move word right |
| Backspace | Delete character before cursor |
| Delete | Delete character after cursor |
| Ctrl+W / Alt+Backspace | Delete word backward |
| Ctrl+U | Delete to start of line |
| Ctrl+K | Delete to end of line |

### Horizontal Scrolling

When text exceeds the input width, the view scrolls horizontally to keep the cursor visible. The visible portion updates as the user types or moves the cursor.

## Editor

The ``Editor`` component provides a full-featured multi-line editing experience.

### Basic Usage

```swift
let editor = Editor(theme: editorTheme)

editor.onSubmit = { text in
    print("Submitted:\n\(text)")
}

tui.addChild(editor)
tui.setFocus(editor)
```

### Theming

```swift
let selectListTheme = SelectListTheme(
    selectedPrefix: { $0 },
    selectedText: { $0 },
    description: { "\u{001B}[90m\($0)\u{001B}[0m" },
    scrollInfo: { "\u{001B}[90m\($0)\u{001B}[0m" },
    noMatch: { "\u{001B}[33m\($0)\u{001B}[0m" }
)

let editorTheme = EditorTheme(
    borderColor: { "\u{001B}[90m\($0)\u{001B}[0m" },
    selectList: selectListTheme
)

let editor = Editor(theme: editorTheme)
```

### Event Handlers

```swift
editor.onSubmit = { text in
    // Called when user submits (Enter by default)
    processText(text)
}

editor.onChange = { text in
    // Called on every text change
    updatePreview(text)
}
```

### Controlling Submission

Disable submission to allow Enter for new lines only:

```swift
editor.disableSubmit = true
// Now Enter always creates a new line
// Use Ctrl+D or a button to submit
```

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| Enter | Submit (unless disabled) |
| Shift+Enter | New line |
| Ctrl+Enter | New line |
| Alt+Enter | New line |
| Tab | Trigger autocomplete |
| Escape | Close autocomplete / Cancel |
| Up / Down | Move line / Navigate history |
| Left / Right | Move cursor |
| Home / Ctrl+A | Move to line start |
| End / Ctrl+E | Move to line end |
| Ctrl+K | Delete to end of line |
| Backspace | Delete character before cursor |
| Delete | Delete character after cursor |

### Autocomplete

Configure autocomplete with ``CombinedAutocompleteProvider``:

```swift
let provider = CombinedAutocompleteProvider(
    commands: [
        SlashCommand(name: "help", description: "Show help"),
        SlashCommand(name: "clear", description: "Clear screen"),
        SlashCommand(name: "quit", description: "Exit application")
    ],
    items: [],
    basePath: FileManager.default.currentDirectoryPath
)

editor.setAutocompleteProvider(provider)
```

Autocomplete triggers:
- **Slash commands**: Type `/` to see available commands
- **File paths**: Press Tab to complete file paths
- **Custom items**: Match against provided items

### History Navigation

The editor maintains a history of submitted text. Press Up/Down when at the first/last line to navigate history.

### Paste Handling

Large pastes are handled specially:
- Content over a threshold creates a paste marker
- Markers show line count: `[paste #1 +50 lines]`
- Avoids flooding the editor with massive content

### Word Wrapping

Text wraps automatically at word boundaries to fit the terminal width. ANSI codes are preserved across wrapped lines.

## Custom Keybindings

Customize editor keybindings with ``EditorKeybindingsManager``:

```swift
let config = EditorKeybindingsConfig([
    .submit: [Key.ctrl("enter")],
    .newLine: [Key.enter],
    .cancel: [Key.escape],
    .deleteToEnd: [Key.ctrl("k")],
    .deleteToStart: [Key.ctrl("u")]
])

let manager = EditorKeybindingsManager(config: config)
setEditorKeybindings(manager)
```

Available actions:
- `.submit` - Submit the content
- `.newLine` - Insert a new line
- `.cancel` - Cancel / close autocomplete
- `.deleteToEnd` - Delete from cursor to end of line
- `.deleteToStart` - Delete from cursor to start of line
- `.moveToStart` - Move cursor to line start
- `.moveToEnd` - Move cursor to line end

## Choosing Between Input and Editor

| Feature | Input | Editor |
|---------|-------|--------|
| Lines | Single | Multiple |
| Autocomplete | No | Yes |
| History | No | Yes |
| Paste handling | Basic | Advanced |
| Word wrap | No (scrolls) | Yes |
| Use case | Commands, search | Code, messages |

## Topics

### Components

- ``Input``
- ``Editor``

### Configuration

- ``EditorTheme``
- ``EditorKeybindingsManager``
- ``EditorKeybindingsConfig``
- ``CombinedAutocompleteProvider``
