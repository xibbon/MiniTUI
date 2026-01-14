# Testing TUI Applications

Test your terminal applications without a real terminal.

@Metadata {
    @PageKind(article)
    @PageColor(orange)
}

## Overview

MiniTui applications can be tested using a `VirtualTerminal` that simulates terminal behavior without actual stdin/stdout. This enables automated testing of component rendering and input handling.

## VirtualTerminal

Create a virtual terminal for testing:

```swift
import XCTest
@testable import MiniTui

final class MyComponentTests: XCTestCase {
    @MainActor
    func testRender() {
        let terminal = VirtualTerminal(columns: 80, rows: 24)
        let tui = TUI(terminal: terminal)

        let text = Text("Hello, World!", paddingX: 1, paddingY: 0)
        tui.addChild(text)
        tui.start()

        // Get rendered output
        let lines = terminal.getLines()
        XCTAssertTrue(lines.contains { $0.contains("Hello, World!") })
    }
}
```

## Testing Components

### Render Output

Test that components render correctly:

```swift
@MainActor
func testTextWrapping() {
    let terminal = VirtualTerminal(columns: 20, rows: 10)
    let tui = TUI(terminal: terminal)

    let text = Text("This is a long line that should wrap")
    tui.addChild(text)
    tui.start()

    let lines = terminal.getLines()
    XCTAssertGreaterThan(lines.count, 1, "Text should wrap to multiple lines")
}
```

### Input Handling

Test keyboard input processing:

```swift
@MainActor
func testInputSubmit() {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    var submitted = false
    let input = Input()
    input.onSubmit = { text in
        XCTAssertEqual(text, "hello")
        submitted = true
    }

    tui.addChild(input)
    tui.setFocus(input)
    tui.start()

    // Simulate typing
    terminal.sendInput("hello")
    terminal.sendInput("\r")  // Enter

    XCTAssertTrue(submitted)
}
```

### Key Matching

Test key detection:

```swift
@MainActor
func testKeyMatching() {
    var upPressed = false
    var ctrlCPressed = false

    let component = TestComponent(
        onInput: { data in
            if matchesKey(data, Key.up) {
                upPressed = true
            }
            if matchesKey(data, Key.ctrl("c")) {
                ctrlCPressed = true
            }
        }
    )

    // Simulate arrow up
    component.handleInput("\u{001B}[A")
    XCTAssertTrue(upPressed)

    // Simulate Ctrl+C
    component.handleInput("\u{0003}")
    XCTAssertTrue(ctrlCPressed)
}
```

## Testing SelectList

```swift
@MainActor
func testSelectListNavigation() {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    var selectedValue: String?
    let items = [
        SelectItem(value: "1", label: "Option 1"),
        SelectItem(value: "2", label: "Option 2"),
        SelectItem(value: "3", label: "Option 3")
    ]

    let list = SelectList(items: items, maxVisible: 10, theme: testTheme)
    list.onSelect = { item in selectedValue = item.value }

    tui.addChild(list)
    tui.setFocus(list)
    tui.start()

    // Navigate down twice
    terminal.sendInput("\u{001B}[B")  // Down
    terminal.sendInput("\u{001B}[B")  // Down

    // Select
    terminal.sendInput("\r")  // Enter

    XCTAssertEqual(selectedValue, "3")
}
```

## Testing Overlays

```swift
@MainActor
func testOverlayDisplay() {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    tui.addChild(Text("Background"))
    tui.start()

    XCTAssertFalse(tui.hasOverlay())

    // Show overlay
    let overlay = Text("Overlay Content")
    tui.showOverlay(overlay)

    XCTAssertTrue(tui.hasOverlay())

    // Check output contains overlay text
    let lines = terminal.getLines()
    XCTAssertTrue(lines.contains { $0.contains("Overlay Content") })

    // Hide overlay
    tui.hideOverlay()

    XCTAssertFalse(tui.hasOverlay())
}
```

## Test Helpers

### Test Theme

Create a simple theme for testing:

```swift
let testTheme = SelectListTheme(
    selectedPrefix: { "> " + $0 },
    selectedText: { $0 },
    description: { $0 },
    scrollInfo: { $0 },
    noMatch: { $0 }
)
```

### Test Component

A component for testing input handling:

```swift
@MainActor
final class TestComponent: Component {
    let onInput: (String) -> Void

    init(onInput: @escaping (String) -> Void) {
        self.onInput = onInput
    }

    func render(width: Int) -> [String] { [] }
    func handleInput(_ data: String) { onInput(data) }
}
```

### Async Test Helper

For testing async operations:

```swift
@MainActor
func waitForRender(_ tui: TUI, timeout: TimeInterval = 1.0) async {
    let start = Date()
    while Date().timeIntervalSince(start) < timeout {
        tui.requestRender()
        try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
    }
}
```

## Testing Patterns

### Snapshot Testing

Compare rendered output against expected snapshots:

```swift
@MainActor
func testRenderSnapshot() {
    let terminal = VirtualTerminal(columns: 40, rows: 10)
    let tui = TUI(terminal: terminal)

    let component = MyComponent(data: testData)
    tui.addChild(component)
    tui.start()

    let lines = terminal.getLines()
    let snapshot = lines.joined(separator: "\n")

    // Compare with stored snapshot
    XCTAssertEqual(snapshot, expectedSnapshot)
}
```

### Behavior Testing

Test component behavior across sequences:

```swift
@MainActor
func testEditorBehavior() {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    var changes: [String] = []
    let editor = Editor(theme: testEditorTheme)
    editor.onChange = { text in changes.append(text) }

    tui.addChild(editor)
    tui.setFocus(editor)
    tui.start()

    // Type some text
    terminal.sendInput("Hello")
    XCTAssertEqual(changes.last, "Hello")

    // Delete a character
    terminal.sendInput("\u{007F}")  // Backspace
    XCTAssertEqual(changes.last, "Hell")

    // Clear line
    terminal.sendInput("\u{0015}")  // Ctrl+U
    XCTAssertEqual(changes.last, "")
}
```

### Integration Testing

Test full application flows:

```swift
@MainActor
func testApplicationFlow() {
    let app = MyApp(terminal: VirtualTerminal(columns: 80, rows: 24))
    app.start()

    // Navigate to settings
    app.terminal.sendInput("/settings\r")

    // Verify settings view is shown
    let lines = app.terminal.getLines()
    XCTAssertTrue(lines.contains { $0.contains("Settings") })

    // Change a setting
    app.terminal.sendInput("\u{001B}[B")  // Down
    app.terminal.sendInput("\r")          // Select

    // Verify change was applied
    XCTAssertEqual(app.settings.theme, "dark")
}
```

## Best Practices

1. **Use VirtualTerminal** - Never test against real stdin/stdout
2. **Test render output** - Verify components display correctly
3. **Test input handling** - Simulate keyboard input
4. **Test state changes** - Verify callbacks are called
5. **Use @MainActor** - All TUI code runs on main actor
6. **Keep themes simple** - Use plain themes for testing
7. **Test edge cases** - Empty content, extreme widths, rapid input

## Topics

### Testing Types

- ``VirtualTerminal``

### Component Protocol

- ``Component/render(width:)``
- ``Component/handleInput(_:)``
