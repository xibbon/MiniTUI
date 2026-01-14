# Layout Components

Organize and structure your terminal interface.

@Metadata {
    @PageKind(article)
    @PageColor(green)
}

## Overview

MiniTui provides layout components to organize your interface: ``Container`` for grouping, ``Box`` for styled containers, and ``Spacer`` for vertical spacing.

## Container

``Container`` groups child components and renders them vertically in order.

### Basic Usage

```swift
let section = Container()
section.addChild(Text("Section Title", paddingX: 1, paddingY: 0))
section.addChild(Text("Section content goes here.", paddingX: 1, paddingY: 0))

tui.addChild(section)
```

### Managing Children

```swift
// Add a child
container.addChild(component)

// Remove a specific child
container.removeChild(component)

// Remove all children
container.clear()
```

### Nesting Containers

Create complex layouts by nesting containers:

```swift
let app = Container()

let header = Container()
header.addChild(Text("My Application", paddingX: 1, paddingY: 1))

let content = Container()
content.addChild(Text("Main content area", paddingX: 1, paddingY: 0))

let footer = Container()
footer.addChild(Text("Status: Ready", paddingX: 1, paddingY: 0))

app.addChild(header)
app.addChild(content)
app.addChild(footer)

tui.addChild(app)
```

### TUI as Container

``TUI`` itself extends ``Container``, so you can use the same methods:

```swift
tui.addChild(header)
tui.addChild(content)
tui.clear()  // Remove all children
```

## Box

``Box`` wraps its children with configurable padding and optional background styling.

### Basic Usage

```swift
let box = Box(paddingX: 2, paddingY: 1)
box.addChild(Text("Boxed content"))

tui.addChild(box)
```

This renders:

```

  Boxed content

```

### Padding

- `paddingX`: Horizontal padding (spaces on left and right of each line)
- `paddingY`: Vertical padding (empty lines above and below content)

```swift
// Horizontal padding only
let box1 = Box(paddingX: 2, paddingY: 0)

// Vertical padding only
let box2 = Box(paddingX: 0, paddingY: 1)

// Both
let box3 = Box(paddingX: 2, paddingY: 1)
```

### Background Styling

Apply a background color or style to the entire box area:

```swift
let box = Box(paddingX: 1, paddingY: 1, bgFn: { line in
    "\u{001B}[44m\(line)\u{001B}[0m"  // Blue background
})
box.addChild(Text("Highlighted content"))
```

Update the background function dynamically:

```swift
box.setBgFn { line in
    "\u{001B}[41m\(line)\u{001B}[0m"  // Red background
}
tui.requestRender()
```

### Multiple Children

Box can contain multiple children:

```swift
let dialog = Box(paddingX: 2, paddingY: 1)
dialog.addChild(Text("Confirm Action", paddingX: 0, paddingY: 0))
dialog.addChild(Spacer(1))
dialog.addChild(Text("Are you sure you want to proceed?", paddingX: 0, paddingY: 0))
dialog.addChild(Spacer(1))
dialog.addChild(Text("[Enter] Yes  [Escape] No", paddingX: 0, paddingY: 0))
```

### Box for Overlays

Box is commonly used to create styled overlay dialogs:

```swift
let menu = Box(paddingX: 1, paddingY: 1, bgFn: { line in
    "\u{001B}[48;5;236m\(line)\u{001B}[0m"  // Dark gray background
})
menu.addChild(Text("Menu"))
menu.addChild(Spacer(1))
menu.addChild(selectList)

tui.showOverlay(menu, options: OverlayOptions(
    width: .absolute(30),
    anchor: .center
))
```

## Spacer

``Spacer`` adds empty lines for vertical spacing between components.

### Basic Usage

```swift
tui.addChild(header)
tui.addChild(Spacer(2))  // Two empty lines
tui.addChild(content)
tui.addChild(Spacer(1))  // One empty line
tui.addChild(footer)
```

### Dynamic Spacing

Create spacers with different heights based on context:

```swift
let compactMode = terminalHeight < 30
let spacing = compactMode ? 1 : 2

tui.addChild(header)
tui.addChild(Spacer(spacing))
tui.addChild(content)
```

## Layout Patterns

### Application Layout

```swift
func buildLayout() {
    // Header section
    let header = Box(paddingX: 1, paddingY: 0, bgFn: headerBg)
    header.addChild(TruncatedText("My App v1.0"))

    // Main content area
    let content = Container()
    content.addChild(Text("Welcome!", paddingX: 1, paddingY: 1))
    content.addChild(mainComponent)

    // Footer with status
    let footer = Box(paddingX: 1, paddingY: 0, bgFn: footerBg)
    footer.addChild(TruncatedText("Ready | Ctrl+C to exit"))

    // Assemble
    tui.addChild(header)
    tui.addChild(Spacer(1))
    tui.addChild(content)
    tui.addChild(Spacer(1))
    tui.addChild(footer)
}
```

### Section Grouping

```swift
func createSection(title: String, content: Component) -> Container {
    let section = Container()
    section.addChild(Text("── \(title) ──", paddingX: 1, paddingY: 0))
    section.addChild(content)
    section.addChild(Spacer(1))
    return section
}

tui.addChild(createSection("Settings", settingsList))
tui.addChild(createSection("Actions", actionsList))
```

### Conditional Layout

```swift
func updateLayout(showSidebar: Bool) {
    tui.clear()

    tui.addChild(header)
    tui.addChild(Spacer(1))

    if showSidebar {
        // In terminal UIs, "side by side" is typically
        // implemented with overlays or alternating focus
        tui.addChild(sidebar)
    }

    tui.addChild(mainContent)
    tui.addChild(Spacer(1))
    tui.addChild(footer)

    tui.requestRender()
}
```

### Dynamic Content Area

```swift
class ContentArea {
    private let container = Container()
    private var currentContent: Component?

    func setContent(_ component: Component) {
        container.clear()
        container.addChild(component)
        currentContent = component
    }

    var component: Component { container }
}

let contentArea = ContentArea()
tui.addChild(contentArea.component)

// Later, swap content
contentArea.setContent(newComponent)
tui.requestRender()
```

## Topics

### Components

- ``Container``
- ``Box``
- ``Spacer``
