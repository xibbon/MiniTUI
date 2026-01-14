# Terminal Compatibility

Feature support across different terminal emulators.

@Metadata {
    @PageKind(article)
    @PageColor(teal)
}

## Overview

MiniTui works across many terminal emulators, but advanced features like Kitty keyboard protocol and inline images require specific terminal support. This guide documents compatibility.

## Feature Matrix

### Core Features

| Feature | All Terminals |
|---------|---------------|
| Basic rendering | Yes |
| ANSI colors (16) | Yes |
| Cursor movement | Yes |
| Line clearing | Yes |
| Bracketed paste | Most |

### Advanced Features

| Feature | Kitty | iTerm2 | WezTerm | Ghostty | Terminal.app |
|---------|-------|--------|---------|---------|--------------|
| Kitty keyboard | Yes | No | Yes | Yes | No |
| Key release events | Yes | No | Yes | Yes | No |
| Inline images | Yes (Kitty) | Yes (iTerm2) | Yes (Kitty) | Yes (Kitty) | No |
| 256 colors | Yes | Yes | Yes | Yes | Yes |
| True color (24-bit) | Yes | Yes | Yes | Yes | Limited |
| Synchronized output | Yes | Yes | Yes | Yes | No |

## Kitty Keyboard Protocol

The Kitty keyboard protocol provides:
- Accurate key identification
- Modifier detection
- Key release events
- Key repeat events

### Supported Terminals

- **Kitty** - Full support
- **WezTerm** - Full support
- **Ghostty** - Full support
- **foot** - Full support

### Detection

MiniTui automatically detects and enables the protocol:

```swift
if isKittyProtocolActive() {
    // Enhanced keyboard features available
}
```

### Fallback Behavior

When unavailable, MiniTui falls back to legacy sequences. Most functionality works, but:
- Key release events not available
- Some modifier combinations may not be detected
- Shift+Enter may not be distinguishable from Enter

## Inline Images

### Kitty Graphics Protocol

Supported by:
- Kitty
- WezTerm
- Ghostty
- Konsole (partial)

### iTerm2 Protocol

Supported by:
- iTerm2
- Mintty
- WezTerm (also supports Kitty)

### Detection

```swift
let caps = getCapabilities()

switch caps.images {
case .kitty:
    print("Kitty graphics available")
case .iterm2:
    print("iTerm2 graphics available")
case nil:
    print("No image support - using fallback")
}
```

### Fallback

When images aren't supported, ``Image`` displays fallback text:

```
[Image: filename.png]
```

## Synchronized Output

CSI 2026 synchronized output prevents screen flicker by buffering output:

```
\u{001B}[?2026h  // Begin synchronized
... output ...
\u{001B}[?2026l  // End synchronized
```

### Support

- **Full support**: Kitty, WezTerm, Ghostty, Alacritty (0.13+)
- **No support**: Terminal.app, older terminals

Without synchronized output, complex renders may show brief flicker.

## Color Support

### 16 Colors (Standard)

```swift
"\u{001B}[31m"  // Red foreground
"\u{001B}[44m"  // Blue background
```

Universally supported.

### 256 Colors

```swift
"\u{001B}[38;5;208m"  // Foreground color 208
"\u{001B}[48;5;236m"  // Background color 236
```

Supported by most modern terminals.

### True Color (24-bit)

```swift
"\u{001B}[38;2;255;128;0m"  // RGB foreground
"\u{001B}[48;2;40;44;52m"   // RGB background
```

| Terminal | Support |
|----------|---------|
| Kitty | Yes |
| iTerm2 | Yes |
| WezTerm | Yes |
| Ghostty | Yes |
| Alacritty | Yes |
| Terminal.app | Limited |
| VS Code | Yes |
| Hyper | Yes |

## Terminal.app Limitations

macOS Terminal.app has limited feature support:

- No Kitty keyboard protocol
- No inline images
- No synchronized output
- Limited true color support
- Basic modifier detection

Workarounds:
- Use iTerm2 or Kitty for full features
- Design UI to work without images
- Accept some visual flicker

## SSH Considerations

Over SSH, terminal capabilities depend on:
- Local terminal emulator
- SSH client configuration
- `TERM` environment variable

### Tips

1. Set `TERM` appropriately:
   ```bash
   export TERM=xterm-256color
   ```

2. Enable Kitty keyboard forwarding:
   ```bash
   kitty +kitten ssh user@host
   ```

3. High latency may affect input handling - MiniTui's `StdinBuffer` helps with buffering.

## Environment Detection

### Check TERM Variable

```swift
let term = ProcessInfo.processInfo.environment["TERM"] ?? ""
let hasColorSupport = term.contains("256color") || term.contains("truecolor")
```

### Check Terminal Program

```swift
let termProgram = ProcessInfo.processInfo.environment["TERM_PROGRAM"]
let isITerm = termProgram == "iTerm.app"
let isVSCode = termProgram == "vscode"
```

### Check Kitty

```swift
let isKitty = ProcessInfo.processInfo.environment["KITTY_WINDOW_ID"] != nil
```

## Recommendations

### For Maximum Compatibility

1. Test in Terminal.app (baseline)
2. Use 16 or 256 colors
3. Provide image fallbacks
4. Don't rely on key release events

### For Best Experience

1. Recommend Kitty, WezTerm, or Ghostty
2. Use true color
3. Enable inline images
4. Take advantage of Kitty keyboard protocol

### Feature Detection

```swift
func configureForTerminal() {
    let caps = getCapabilities()

    // Configure image support
    imageComponent.useFallback = caps.images == nil

    // Configure keyboard handling
    if !isKittyProtocolActive() {
        // Use simpler key bindings
        disableKeyReleaseFeatures()
    }
}
```

## Topics

### Detection Functions

- ``getCapabilities()``
- ``detectCapabilities()``
- ``isKittyProtocolActive()``

### Types

- ``TerminalCapabilities``
- ``ImageProtocol``
