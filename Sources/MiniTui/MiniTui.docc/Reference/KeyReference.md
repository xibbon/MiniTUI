# Key Reference

Complete reference for keyboard input identifiers and escape sequences.

@Metadata {
    @PageKind(article)
    @PageColor(teal)
}

## Overview

This reference documents all key identifiers supported by MiniTui, their escape sequences, and how to use them with ``matchesKey(_:_:)``.

## Special Keys

| Key ID | Escape Sequence | Key Helper |
|--------|-----------------|------------|
| `escape` / `esc` | `\u{001B}` | `Key.escape` |
| `enter` / `return` | `\r` | `Key.enter` |
| `tab` | `\t` | `Key.tab` |
| `space` | ` ` | `Key.space` |
| `backspace` | `\u{007F}` | `Key.backspace` |
| `delete` | `\u{001B}[3~` | `Key.delete` |

## Navigation Keys

| Key ID | Escape Sequence | Key Helper |
|--------|-----------------|------------|
| `up` | `\u{001B}[A` | `Key.up` |
| `down` | `\u{001B}[B` | `Key.down` |
| `right` | `\u{001B}[C` | `Key.right` |
| `left` | `\u{001B}[D` | `Key.left` |
| `home` | `\u{001B}[H` | `Key.home` |
| `end` | `\u{001B}[F` | `Key.end` |
| `pageUp` | `\u{001B}[5~` | `Key.pageUp` |
| `pageDown` | `\u{001B}[6~` | `Key.pageDown` |

## Modifier Combinations

### Ctrl+Key

| Key ID | Common Use |
|--------|------------|
| `ctrl+a` | Move to start of line |
| `ctrl+b` | Move backward |
| `ctrl+c` | Cancel / interrupt |
| `ctrl+d` | EOF / delete forward |
| `ctrl+e` | Move to end of line |
| `ctrl+f` | Move forward |
| `ctrl+k` | Delete to end of line |
| `ctrl+l` | Clear screen |
| `ctrl+n` | Next item |
| `ctrl+p` | Previous item |
| `ctrl+u` | Delete to start of line |
| `ctrl+w` | Delete word backward |

### Shift+Key

| Key ID | Escape Sequence |
|--------|-----------------|
| `shift+tab` | `\u{001B}[Z` |
| `shift+enter` | Varies by terminal |
| `shift+up` | `\u{001B}[1;2A` |
| `shift+down` | `\u{001B}[1;2B` |

### Alt+Key

| Key ID | Escape Sequence |
|--------|-----------------|
| `alt+left` | `\u{001B}[1;3D` or `\u{001B}b` |
| `alt+right` | `\u{001B}[1;3C` or `\u{001B}f` |
| `alt+backspace` | `\u{001B}\u{007F}` |
| `alt+enter` | `\u{001B}\r` (legacy) |

### Ctrl+Shift+Key

| Key ID | Escape Sequence |
|--------|-----------------|
| `ctrl+shift+p` | Kitty protocol only |
| `ctrl+shift+c` | Kitty protocol only |

## Symbol Keys

| Key ID | Character | Key Helper |
|--------|-----------|------------|
| `\`` | Backtick | `Key.backtick` |
| `-` | Hyphen | `Key.hyphen` |
| `=` | Equals | `Key.equals` |
| `[` | Left bracket | `Key.leftbracket` |
| `]` | Right bracket | `Key.rightbracket` |
| `\` | Backslash | `Key.backslash` |
| `;` | Semicolon | `Key.semicolon` |
| `'` | Quote | `Key.quote` |
| `,` | Comma | `Key.comma` |
| `.` | Period | `Key.period` |
| `/` | Slash | `Key.slash` |

### Shifted Symbols

| Key ID | Character | Key Helper |
|--------|-----------|------------|
| `!` | Exclamation | `Key.exclamation` |
| `@` | At | `Key.at` |
| `#` | Hash | `Key.hash` |
| `$` | Dollar | `Key.dollar` |
| `%` | Percent | `Key.percent` |
| `^` | Caret | `Key.caret` |
| `&` | Ampersand | `Key.ampersand` |
| `*` | Asterisk | `Key.asterisk` |
| `(` | Left paren | `Key.leftparen` |
| `)` | Right paren | `Key.rightparen` |
| `_` | Underscore | `Key.underscore` |
| `+` | Plus | `Key.plus` |
| `\|` | Pipe | `Key.pipe` |
| `~` | Tilde | `Key.tilde` |
| `{` | Left brace | `Key.leftbrace` |
| `}` | Right brace | `Key.rightbrace` |
| `:` | Colon | `Key.colon` |
| `<` | Less than | `Key.lessthan` |
| `>` | Greater than | `Key.greaterthan` |
| `?` | Question | `Key.question` |

## Key Helper Methods

### Single Modifiers

```swift
Key.ctrl("c")      // "ctrl+c"
Key.shift("tab")   // "shift+tab"
Key.alt("left")    // "alt+left"
```

### Combined Modifiers

```swift
Key.ctrlShift("p")     // "ctrl+shift+p"
Key.shiftCtrl("p")     // "shift+ctrl+p" (equivalent)
Key.ctrlAlt("d")       // "ctrl+alt+d"
Key.altCtrl("d")       // "alt+ctrl+d" (equivalent)
Key.shiftAlt("up")     // "shift+alt+up"
Key.altShift("up")     // "alt+shift+up" (equivalent)
```

### Triple Modifiers

```swift
Key.ctrlShiftAlt("x")  // "ctrl+shift+alt+x"
```

## Kitty Protocol

When Kitty keyboard protocol is active, MiniTui receives enhanced key information:

### Key Event Format

```
\u{001B}[<codepoint>;<modifier>u
\u{001B}[<codepoint>;<modifier>:<event>u
```

Where:
- `codepoint`: Unicode codepoint of the key
- `modifier`: Modifier flags (1=shift, 2=alt, 4=ctrl)
- `event`: 1=press, 2=repeat, 3=release

### Event Detection

```swift
// Check event type
if isKeyRelease(data) {
    // Key was released
}

if isKeyRepeat(data) {
    // Key is being held
}
```

### Protocol Status

```swift
if isKittyProtocolActive() {
    // Enhanced key support available
}
```

## Escape Sequence Patterns

### CSI Sequences

```
\u{001B}[<params><final>
```

Examples:
- `\u{001B}[A` - Up arrow
- `\u{001B}[1;5C` - Ctrl+Right
- `\u{001B}[3~` - Delete

### SS3 Sequences

```
\u{001B}O<final>
```

Examples:
- `\u{001B}OM` - Keypad Enter

### Legacy Alt Sequences

```
\u{001B}<char>
```

Examples:
- `\u{001B}b` - Alt+B (word back)
- `\u{001B}f` - Alt+F (word forward)

## Usage Examples

### Basic Key Matching

```swift
func handleInput(_ data: String) {
    if matchesKey(data, Key.enter) {
        submit()
    }
}
```

### Multiple Keys for Same Action

```swift
if matchesKey(data, Key.escape) || matchesKey(data, Key.ctrl("c")) {
    cancel()
}
```

### Navigation with Modifiers

```swift
if matchesKey(data, Key.ctrl("left")) || matchesKey(data, Key.alt("left")) {
    moveWordBack()
}
```

### Key Parsing

```swift
if let key = parseKey(data) {
    log("Key pressed: \(key)")
}
```

## Topics

### Types

- ``Key``
- ``KeyId``
- ``KeyEventType``

### Functions

- ``matchesKey(_:_:)``
- ``parseKey(_:)``
- ``isKeyRelease(_:)``
- ``isKeyRepeat(_:)``
- ``isKittyProtocolActive()``
