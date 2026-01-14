# Working with Overlays

Display menus, dialogs, and floating content above your main interface.

@Metadata {
    @PageKind(article)
    @PageColor(orange)
}

## Overview

Overlays render components on top of existing content, useful for menus, dialogs, tooltips, and any transient UI. MiniTui's overlay system handles positioning, sizing, and proper compositing with ANSI style codes.

## Basic Overlay

Show a simple overlay with `showOverlay(_:options:)`:

```swift
let dialog = Box(paddingX: 2, paddingY: 1)
dialog.addChild(Text("Hello from overlay!"))

tui.showOverlay(dialog)
```

Hide the topmost overlay:

```swift
tui.hideOverlay()
```

## Overlay Handle

`showOverlay` returns an ``OverlayHandle`` for fine-grained control:

```swift
let handle = tui.showOverlay(dialog)

// Temporarily hide
handle.setHidden(true)

// Show again
handle.setHidden(false)

// Check hidden state
if handle.isHidden() {
    print("Overlay is hidden")
}

// Permanently remove
handle.hide()
```

## Positioning Options

### Anchors

Position overlays using ``OverlayAnchor``:

```swift
// Center (default)
tui.showOverlay(dialog, options: OverlayOptions(anchor: .center))

// Corners
tui.showOverlay(dialog, options: OverlayOptions(anchor: .topLeft))
tui.showOverlay(dialog, options: OverlayOptions(anchor: .topRight))
tui.showOverlay(dialog, options: OverlayOptions(anchor: .bottomLeft))
tui.showOverlay(dialog, options: OverlayOptions(anchor: .bottomRight))

// Edges
tui.showOverlay(dialog, options: OverlayOptions(anchor: .topCenter))
tui.showOverlay(dialog, options: OverlayOptions(anchor: .bottomCenter))
tui.showOverlay(dialog, options: OverlayOptions(anchor: .leftCenter))
tui.showOverlay(dialog, options: OverlayOptions(anchor: .rightCenter))
```

### Offsets

Fine-tune position with offsets:

```swift
tui.showOverlay(dialog, options: OverlayOptions(
    anchor: .topRight,
    offsetX: -2,  // 2 columns from right edge
    offsetY: 1    // 1 row down from top
))
```

### Absolute Positioning

Use `row` and `col` for specific positions:

```swift
// Absolute values
tui.showOverlay(dialog, options: OverlayOptions(
    row: .absolute(5),
    col: .absolute(10)
))

// Percentage of terminal size
tui.showOverlay(dialog, options: OverlayOptions(
    row: .percent(25),   // 25% down from top
    col: .percent(50)    // 50% from left
))
```

## Sizing Options

### Width

```swift
// Absolute width
tui.showOverlay(dialog, options: OverlayOptions(
    width: .absolute(40)
))

// Percentage of terminal width
tui.showOverlay(dialog, options: OverlayOptions(
    width: .percent(60)
))

// Minimum width
tui.showOverlay(dialog, options: OverlayOptions(
    width: .percent(50),
    minWidth: 30  // At least 30 columns
))
```

### Height

Limit height with `maxHeight`:

```swift
tui.showOverlay(dialog, options: OverlayOptions(
    maxHeight: .absolute(10)    // Max 10 rows
))

tui.showOverlay(dialog, options: OverlayOptions(
    maxHeight: .percent(50)     // Max half terminal height
))
```

## Margins

Keep overlays away from terminal edges:

```swift
// All sides
tui.showOverlay(dialog, options: OverlayOptions(
    margin: OverlayMargin(all: 2)
))

// Individual sides
tui.showOverlay(dialog, options: OverlayOptions(
    margin: OverlayMargin(top: 1, right: 2, bottom: 1, left: 2)
))
```

## Responsive Visibility

Control visibility based on terminal size:

```swift
tui.showOverlay(dialog, options: OverlayOptions(
    visible: { termWidth, termHeight in
        // Only show if terminal is wide enough
        return termWidth >= 80
    }
))
```

The visibility callback is evaluated on every render, so the overlay automatically shows/hides as the terminal resizes.

## Focus Management

Overlays automatically receive focus when shown:

```swift
let menu = SelectList(items: items, ...)
menu.onSelect = { item in
    tui.hideOverlay()
    handleSelection(item)
}

tui.showOverlay(menu)  // Focus automatically moves to menu
```

When an overlay is hidden, focus returns to the previously focused component.

## Stacked Overlays

Multiple overlays stack on top of each other:

```swift
// First overlay
let menu = Box(paddingX: 1, paddingY: 1)
menu.addChild(menuList)
tui.showOverlay(menu)

// Second overlay (confirmation dialog)
let confirm = Box(paddingX: 2, paddingY: 1)
confirm.addChild(Text("Are you sure?"))
tui.showOverlay(confirm)  // Appears on top of menu

// Hide top overlay
tui.hideOverlay()  // Removes confirm, menu still visible

// Hide remaining overlay
tui.hideOverlay()  // Removes menu
```

## Common Patterns

### Menu Overlay

```swift
func showMenu() {
    let items = [
        SelectItem(value: "new", label: "New File"),
        SelectItem(value: "open", label: "Open..."),
        SelectItem(value: "save", label: "Save")
    ]

    let list = SelectList(items: items, maxVisible: 10, theme: menuTheme)

    list.onSelect = { [weak self] item in
        self?.tui.hideOverlay()
        self?.handleMenuAction(item.value)
    }

    list.onCancel = { [weak self] in
        self?.tui.hideOverlay()
    }

    let menu = Box(paddingX: 1, paddingY: 1)
    menu.addChild(list)

    tui.showOverlay(menu, options: OverlayOptions(
        width: .absolute(25),
        anchor: .topLeft,
        offsetX: 1,
        offsetY: 2
    ))
    tui.setFocus(list)
}
```

### Confirmation Dialog

```swift
func confirmAction(_ message: String, onConfirm: @escaping () -> Void) {
    let dialog = Box(paddingX: 2, paddingY: 1)
    dialog.addChild(Text(message))
    dialog.addChild(Spacer(1))
    dialog.addChild(Text("[Enter] Yes  [Escape] No"))

    let handle = tui.showOverlay(dialog, options: OverlayOptions(
        width: .absolute(40),
        anchor: .center
    ))

    let handler = ConfirmHandler(
        onConfirm: {
            handle.hide()
            onConfirm()
        },
        onCancel: {
            handle.hide()
        }
    )
    tui.setFocus(handler)
}

// Usage
confirmAction("Delete this file?") {
    deleteFile()
}
```

### Toast Notification

```swift
func showToast(_ message: String, duration: TimeInterval = 3) {
    let toast = Box(paddingX: 2, paddingY: 0)
    toast.addChild(Text(message))

    let handle = tui.showOverlay(toast, options: OverlayOptions(
        anchor: .bottomCenter,
        offsetY: -2,
        margin: OverlayMargin(bottom: 1)
    ))

    // Auto-dismiss
    Task {
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        await MainActor.run {
            handle.hide()
        }
    }
}
```

### Modal Input

```swift
func promptForInput(title: String, onSubmit: @escaping (String) -> Void) {
    let dialog = Box(paddingX: 2, paddingY: 1)
    dialog.addChild(Text(title))
    dialog.addChild(Spacer(1))

    let input = Input()
    input.onSubmit = { [weak self] text in
        self?.tui.hideOverlay()
        onSubmit(text)
    }
    input.onEscape = { [weak self] in
        self?.tui.hideOverlay()
    }

    dialog.addChild(input)

    tui.showOverlay(dialog, options: OverlayOptions(
        width: .percent(50),
        minWidth: 30,
        anchor: .center
    ))
    tui.setFocus(input)
}

// Usage
promptForInput(title: "Enter filename:") { name in
    createFile(named: name)
}
```

### Autocomplete Popup

```swift
func showAutocomplete(items: [String], at position: Int) {
    let selectItems = items.map { SelectItem(value: $0, label: $0) }
    let list = SelectList(items: selectItems, maxVisible: 5, theme: autocompleteTheme)

    list.onSelect = { [weak self] item in
        self?.tui.hideOverlay()
        self?.insertCompletion(item.value)
    }

    list.onCancel = { [weak self] in
        self?.tui.hideOverlay()
    }

    tui.showOverlay(list, options: OverlayOptions(
        width: .absolute(30),
        maxHeight: .absolute(6),
        row: .absolute(position + 1),
        col: .absolute(2)
    ))
    tui.setFocus(list)
}
```

## Topics

### Types

- ``OverlayOptions``
- ``OverlayAnchor``
- ``OverlayMargin``
- ``OverlayHandle``
- ``SizeValue``

### Methods

- ``TUI/showOverlay(_:options:)``
- ``TUI/hideOverlay()``
- ``TUI/hasOverlay()``
