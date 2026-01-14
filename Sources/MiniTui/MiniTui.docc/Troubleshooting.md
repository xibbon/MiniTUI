# Troubleshooting

Solutions to common MiniTui issues.

@Metadata {
    @PageKind(article)
    @PageColor(red)
}

## Overview

This guide addresses common issues when developing with MiniTui and provides solutions.

## Display Issues

### Screen Flickering

**Symptoms**: Content flickers or blinks during updates.

**Causes**:
1. Terminal doesn't support synchronized output (CSI 2026)
2. Too many render requests
3. Full-screen clears instead of differential updates

**Solutions**:

1. Use a modern terminal (Kitty, WezTerm, Ghostty, Alacritty 0.13+)

2. Batch state changes before rendering:
   ```swift
   // Instead of:
   component1.update()
   tui.requestRender()
   component2.update()
   tui.requestRender()

   // Do:
   component1.update()
   component2.update()
   tui.requestRender()
   ```

3. Avoid force renders:
   ```swift
   // Only use when necessary:
   tui.requestRender(force: true)
   ```

### Garbled Output / Misaligned Text

**Symptoms**: Text appears in wrong positions, lines overlap.

**Causes**:
1. ANSI codes counted in width calculations
2. Wide characters (emojis, CJK) miscalculated
3. Lines exceed terminal width

**Solutions**:

1. Use `visibleWidth()` for width calculations:
   ```swift
   let width = visibleWidth(styledText)  // Excludes ANSI codes
   ```

2. Use `truncateToWidth()` to fit content:
   ```swift
   let line = truncateToWidth(text, maxWidth: width)
   ```

3. Respect the width parameter in `render()`:
   ```swift
   func render(width: Int) -> [String] {
       return lines.map { truncateToWidth($0, maxWidth: width) }
   }
   ```

### Colors Not Appearing

**Symptoms**: Text appears without colors.

**Causes**:
1. `NO_COLOR` environment variable set
2. Terminal doesn't support colors
3. `TERM` variable set incorrectly

**Solutions**:

1. Check environment:
   ```bash
   echo $NO_COLOR
   echo $TERM
   ```

2. Force color in supported terminals:
   ```bash
   export FORCE_COLOR=1
   ```

3. Verify terminal supports colors:
   ```bash
   tput colors  # Should show 256 or higher
   ```

### Images Not Displaying

**Symptoms**: Images show fallback text instead of actual image.

**Causes**:
1. Terminal doesn't support Kitty or iTerm2 graphics
2. Running in SSH without graphics forwarding
3. Image format not supported

**Solutions**:

1. Check terminal support:
   ```swift
   let caps = getCapabilities()
   print("Image support: \(String(describing: caps.images))")
   ```

2. Use a supported terminal:
   - Kitty (Kitty protocol)
   - iTerm2 (iTerm2 protocol)
   - WezTerm (both protocols)
   - Ghostty (Kitty protocol)

3. Provide meaningful fallback:
   ```swift
   let theme = ImageTheme(fallbackColor: { "[\($0)]" })
   ```

## Input Issues

### Keys Not Detected

**Symptoms**: Certain key combinations don't work.

**Causes**:
1. Terminal intercepts keys (Ctrl+C, Ctrl+Z, etc.)
2. Kitty protocol not active
3. SSH modifying sequences

**Solutions**:

1. Check Kitty protocol status:
   ```swift
   print("Kitty active: \(isKittyProtocolActive())")
   ```

2. Use alternative key bindings:
   ```swift
   // Instead of Ctrl+C (often intercepted):
   if matchesKey(data, Key.escape) || matchesKey(data, Key.ctrl("c")) {
       cancel()
   }
   ```

3. Test with key tester:
   ```bash
   swift run MiniTuiKeyTester
   ```

### Input Lag

**Symptoms**: Typing feels delayed, especially over SSH.

**Causes**:
1. Network latency
2. Escape sequence buffering
3. Rapid render requests

**Solutions**:

1. MiniTui uses `StdinBuffer` to handle this automatically

2. If building custom input handling:
   ```swift
   let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
   ```

3. Reduce render frequency during rapid input

### Paste Not Working

**Symptoms**: Pasted text appears character by character or is corrupted.

**Causes**:
1. Bracketed paste not enabled
2. Large paste overwhelming buffer
3. Custom input handler not checking for paste

**Solutions**:

1. Check for bracketed paste markers:
   ```swift
   if data.contains("\u{001B}[200~") {
       // This is pasted content
       let content = data
           .replacingOccurrences(of: "\u{001B}[200~", with: "")
           .replacingOccurrences(of: "\u{001B}[201~", with: "")
       handlePaste(content)
   }
   ```

2. Use built-in ``Input`` or ``Editor`` which handle paste automatically

## Performance Issues

### Slow Rendering

**Symptoms**: UI feels sluggish, high CPU usage.

**Causes**:
1. Expensive computations in `render()`
2. No caching
3. Rendering too frequently

**Solutions**:

1. Implement caching:
   ```swift
   private var cachedLines: [String]?

   func render(width: Int) -> [String] {
       if let cached = cachedLines { return cached }
       let lines = computeExpensiveRender(width: width)
       cachedLines = lines
       return lines
   }

   func invalidate() {
       cachedLines = nil
   }
   ```

2. Profile render time:
   ```swift
   func render(width: Int) -> [String] {
       let start = CFAbsoluteTimeGetCurrent()
       let result = actualRender(width)
       print("Render time: \((CFAbsoluteTimeGetCurrent() - start) * 1000)ms")
       return result
   }
   ```

### Memory Growth

**Symptoms**: Memory usage increases over time.

**Causes**:
1. Retain cycles in closures
2. Unbounded history/cache
3. Components not removed

**Solutions**:

1. Use weak references:
   ```swift
   button.onClick = { [weak self] in
       self?.handleClick()
   }
   ```

2. Limit collections:
   ```swift
   if messages.count > 1000 {
       messages.removeFirst(messages.count - 1000)
   }
   ```

3. Clean up components:
   ```swift
   loader.stop()
   tui.removeChild(loader)
   ```

## Terminal State Issues

### Terminal Not Restored After Crash

**Symptoms**: Terminal stays in raw mode after crash, input echoes weirdly.

**Solutions**:

1. Reset terminal:
   ```bash
   reset
   # or
   stty sane
   ```

2. Add cleanup handler:
   ```swift
   signal(SIGINT) { _ in
       tui.stop()
       exit(0)
   }
   ```

### Cursor Invisible After Exit

**Symptoms**: Cursor disappears after application exits.

**Causes**: `stop()` not called properly.

**Solutions**:

1. Always call `stop()`:
   ```swift
   func quit() {
       tui.stop()
       exit(0)
   }
   ```

2. Manual cursor restore:
   ```bash
   printf '\e[?25h'
   ```

## Overlay Issues

### Overlay Not Visible

**Symptoms**: `showOverlay` called but nothing appears.

**Causes**:
1. Overlay positioned off-screen
2. `visible` callback returning false
3. Width/height too small

**Solutions**:

1. Check positioning:
   ```swift
   // Use center for debugging
   tui.showOverlay(dialog, options: OverlayOptions(
       anchor: .center,
       width: .percent(50)
   ))
   ```

2. Check visibility callback:
   ```swift
   visible: { width, height in
       print("Terminal: \(width)x\(height)")
       return true  // Force visible for debugging
   }
   ```

### Focus Not Moving to Overlay

**Symptoms**: Overlay visible but doesn't receive input.

**Solutions**:

1. Explicitly set focus:
   ```swift
   let handle = tui.showOverlay(dialog)
   tui.setFocus(interactiveComponent)
   ```

2. Check that the overlay component handles input:
   ```swift
   func handleInput(_ data: String) {
       print("Received: \(data)")  // Debug
   }
   ```

## Common Error Messages

### "Main actor-isolated" Errors

**Symptoms**: Compiler errors about main actor isolation.

**Solutions**:

Always run TUI code on main actor:
```swift
@MainActor
static func main() {
    // TUI code
}

// From async context:
Task { @MainActor in
    tui.requestRender()
}
```

### "Cannot find type" Errors

**Symptoms**: Compiler can't find MiniTui types.

**Solutions**:

1. Check import:
   ```swift
   import MiniTui
   ```

2. Verify Package.swift dependency:
   ```swift
   dependencies: [
       .package(path: "../MiniTui")
   ]
   ```

3. Clean and rebuild:
   ```bash
   swift package clean
   swift build
   ```

## Getting Help

If issues persist:

1. Create a minimal reproduction case
2. Check the MiniTui test files for examples
3. Verify terminal capabilities with `MiniTuiKeyTester`
4. Test in multiple terminals to isolate terminal-specific issues

## Topics

### Debugging Tools

- ``visibleWidth(_:)``
- ``getCapabilities()``
- ``isKittyProtocolActive()``
- ``parseKey(_:)``
