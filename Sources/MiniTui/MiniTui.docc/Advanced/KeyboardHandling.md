# Keyboard Handling

Handle keyboard input with support for modern terminal protocols.

@Metadata {
    @PageKind(article)
    @PageColor(orange)
}

## Overview

MiniTui provides robust keyboard handling that works across different terminals, including support for the Kitty keyboard protocol. This guide covers key matching, the `Key` helper, and customizing keybindings.

## Key Matching

Use ``matchesKey(_:_:)`` to detect specific key presses:

```swift
func handleInput(_ data: String) {
    if matchesKey(data, Key.enter) {
        submit()
    } else if matchesKey(data, Key.escape) {
        cancel()
    } else if matchesKey(data, Key.ctrl("c")) {
        quit()
    }
}
```

## The Key Helper

``Key`` provides typed key identifiers with IDE autocomplete support.

### Special Keys

```swift
Key.escape      // or Key.esc
Key.enter       // or Key.return
Key.tab
Key.space
Key.backspace
Key.delete
Key.home
Key.end
Key.pageUp
Key.pageDown
Key.up
Key.down
Key.left
Key.right
```

### Modifier Keys

```swift
// Single modifiers
Key.ctrl("c")       // Ctrl+C
Key.shift("tab")    // Shift+Tab
Key.alt("left")     // Alt+Left

// Combined modifiers
Key.ctrlShift("p")  // Ctrl+Shift+P
Key.ctrlAlt("d")    // Ctrl+Alt+D
Key.shiftAlt("up")  // Shift+Alt+Up

// Triple modifiers
Key.ctrlShiftAlt("x")
```

### Symbol Keys

```swift
Key.backtick      // `
Key.hyphen        // -
Key.equals        // =
Key.leftbracket   // [
Key.rightbracket  // ]
Key.backslash     // \
Key.semicolon     // ;
Key.quote         // '
Key.comma         // ,
Key.period        // .
Key.slash         // /
```

### String Format

You can also use string identifiers:

```swift
matchesKey(data, "enter")
matchesKey(data, "ctrl+c")
matchesKey(data, "shift+tab")
matchesKey(data, "ctrl+shift+p")
```

## Parsing Keys

Use ``parseKey(_:)`` to convert input to a key identifier:

```swift
if let keyId = parseKey(data) {
    print("Pressed: \(keyId)")  // e.g., "ctrl+c", "enter", "a"
}
```

This is useful for key recording or debugging.

## Key Event Types

With the Kitty keyboard protocol, you can detect key release and repeat events:

```swift
// Check for key release
if isKeyRelease(data) {
    // Key was released
    return
}

// Check for key repeat
if isKeyRepeat(data) {
    // Key is being held down
}
```

### Handling Key Release

To receive key release events, set `wantsKeyRelease`:

```swift
@MainActor
final class GameControls: Component {
    var wantsKeyRelease: Bool { true }
    private var isJumping = false

    func handleInput(_ data: String) {
        if matchesKey(data, Key.space) {
            if isKeyRelease(data) {
                isJumping = false
            } else {
                isJumping = true
            }
        }
    }
}
```

## Kitty Protocol

MiniTui automatically detects and enables the Kitty keyboard protocol when available. This provides:

- Key release events
- Key repeat events
- Better modifier detection
- Accurate key identification

Check protocol status:

```swift
if isKittyProtocolActive() {
    // Enhanced keyboard support available
}
```

The protocol is enabled transparently; your key matching code works the same with or without it.

## Editor Keybindings

Customize the ``Editor`` component's keybindings with ``EditorKeybindingsManager``:

```swift
let config = EditorKeybindingsConfig([
    .submit: [Key.ctrl("enter")],
    .newLine: [Key.enter, Key.shift("enter")],
    .cancel: [Key.escape, Key.ctrl("c")],
    .deleteToEnd: [Key.ctrl("k")],
    .deleteToStart: [Key.ctrl("u")],
    .moveToStart: [Key.ctrl("a"), Key.home],
    .moveToEnd: [Key.ctrl("e"), Key.end]
])

let manager = EditorKeybindingsManager(config: config)
setEditorKeybindings(manager)
```

### Available Actions

| Action | Default Keys | Description |
|--------|--------------|-------------|
| `.submit` | Enter | Submit content |
| `.newLine` | Shift+Enter, Ctrl+Enter, Alt+Enter | Insert new line |
| `.cancel` | Escape | Cancel / close autocomplete |
| `.deleteToEnd` | Ctrl+K | Delete to end of line |
| `.deleteToStart` | Ctrl+U | Delete to start of line |
| `.moveToStart` | Ctrl+A, Home | Move to line start |
| `.moveToEnd` | Ctrl+E, End | Move to line end |

### Getting Current Bindings

```swift
let bindings = getEditorKeybindings()
if let submitKeys = bindings.keys(for: .submit) {
    print("Submit bound to: \(submitKeys)")
}
```

## Global Input Handling

Intercept input before it reaches the focused component:

```swift
tui.onGlobalInput = { [weak self] input in
    // Ctrl+Q always quits
    if matchesKey(input, Key.ctrl("q")) {
        self?.quit()
        return true  // Consume the input
    }

    // Ctrl+/ toggles help
    if matchesKey(input, Key.ctrl("/")) {
        self?.toggleHelp()
        return true
    }

    return false  // Let focused component handle it
}
```

Return `true` to consume the input (prevent it from reaching the focused component).

## Bracketed Paste

MiniTui handles bracketed paste mode automatically. Paste content is wrapped with markers:

```swift
func handleInput(_ data: String) {
    if data.contains("\u{001B}[200~") {
        // This is pasted content
        let content = data
            .replacingOccurrences(of: "\u{001B}[200~", with: "")
            .replacingOccurrences(of: "\u{001B}[201~", with: "")
        handlePaste(content)
        return
    }

    // Normal keyboard input
    handleKeyboard(data)
}
```

The built-in ``Input`` and ``Editor`` components handle paste automatically.

## Common Patterns

### Vim-style Navigation

```swift
func handleInput(_ data: String) {
    if matchesKey(data, "h") || matchesKey(data, Key.left) {
        moveLeft()
    } else if matchesKey(data, "j") || matchesKey(data, Key.down) {
        moveDown()
    } else if matchesKey(data, "k") || matchesKey(data, Key.up) {
        moveUp()
    } else if matchesKey(data, "l") || matchesKey(data, Key.right) {
        moveRight()
    }
}
```

### Mode-based Input

```swift
enum Mode {
    case normal
    case insert
    case command
}

var mode: Mode = .normal

func handleInput(_ data: String) {
    switch mode {
    case .normal:
        handleNormalMode(data)
    case .insert:
        handleInsertMode(data)
    case .command:
        handleCommandMode(data)
    }
}

func handleNormalMode(_ data: String) {
    if matchesKey(data, "i") {
        mode = .insert
    } else if matchesKey(data, ":") {
        mode = .command
    }
}
```

### Key Combinations

```swift
func handleInput(_ data: String) {
    // Multi-key sequence support
    if awaitingSecondKey {
        handleSecondKey(data)
        return
    }

    if matchesKey(data, Key.ctrl("x")) {
        awaitingSecondKey = true
        pendingPrefix = "ctrl+x"
    }
}

func handleSecondKey(_ data: String) {
    awaitingSecondKey = false

    if pendingPrefix == "ctrl+x" {
        if matchesKey(data, Key.ctrl("s")) {
            save()
        } else if matchesKey(data, Key.ctrl("c")) {
            quit()
        }
    }
}
```

## Topics

### Functions

- ``matchesKey(_:_:)``
- ``parseKey(_:)``
- ``isKeyRelease(_:)``
- ``isKeyRepeat(_:)``
- ``isKittyProtocolActive()``

### Types

- ``Key``
- ``KeyId``
- ``KeyEventType``

### Configuration

- ``EditorKeybindingsManager``
- ``EditorKeybindingsConfig``
- ``EditorAction``
- ``setEditorKeybindings(_:)``
- ``getEditorKeybindings()``
