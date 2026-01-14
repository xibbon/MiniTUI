# Recipes

Common patterns and solutions for terminal UI development.

@Metadata {
    @PageKind(article)
    @PageColor(yellow)
}

## Overview

This cookbook provides ready-to-use code patterns for common TUI scenarios.

## Progress Indicators

### Simple Progress Bar

```swift
@MainActor
final class ProgressBar: Component {
    var progress: Double = 0
    var label: String = ""

    func render(width: Int) -> [String] {
        let barWidth = width - label.count - 10
        let filled = Int(Double(barWidth) * progress)
        let empty = barWidth - filled

        let bar = "\u{001B}[32m" + String(repeating: "█", count: filled) + "\u{001B}[0m" +
                  "\u{001B}[90m" + String(repeating: "░", count: empty) + "\u{001B}[0m"
        let percent = String(format: "%3.0f%%", progress * 100)

        return ["\(label) \(bar) \(percent)"]
    }
}
```

### Multi-step Progress

```swift
@MainActor
final class StepProgress: Component {
    var steps: [String]
    var currentStep: Int = 0

    init(steps: [String]) {
        self.steps = steps
    }

    func render(width: Int) -> [String] {
        return steps.enumerated().map { index, step in
            let status: String
            if index < currentStep {
                status = "\u{001B}[32m✓\u{001B}[0m"
            } else if index == currentStep {
                status = "\u{001B}[33m●\u{001B}[0m"
            } else {
                status = "\u{001B}[90m○\u{001B}[0m"
            }
            return "  \(status) \(step)"
        }
    }
}
```

## Tables

### Simple Table

```swift
@MainActor
final class SimpleTable: Component {
    var headers: [String]
    var rows: [[String]]
    var columnWidths: [Int]

    init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
        self.columnWidths = headers.enumerated().map { index, header in
            max(header.count, rows.map { $0[safe: index]?.count ?? 0 }.max() ?? 0)
        }
    }

    func render(width: Int) -> [String] {
        var lines: [String] = []

        // Header
        let headerLine = headers.enumerated().map { index, header in
            header.padding(toLength: columnWidths[index], withPad: " ", startingAt: 0)
        }.joined(separator: " │ ")
        lines.append("\u{001B}[1m\(headerLine)\u{001B}[0m")

        // Separator
        let separator = columnWidths.map { String(repeating: "─", count: $0) }.joined(separator: "─┼─")
        lines.append(separator)

        // Rows
        for row in rows {
            let rowLine = row.enumerated().map { index, cell in
                cell.padding(toLength: columnWidths[safe: index] ?? cell.count, withPad: " ", startingAt: 0)
            }.joined(separator: " │ ")
            lines.append(rowLine)
        }

        return lines
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

## Tab Navigation

### Tab Bar

```swift
@MainActor
final class TabBar: Component {
    var tabs: [String]
    var selectedIndex: Int = 0
    var onChange: ((Int) -> Void)?

    func render(width: Int) -> [String] {
        let tabStrings = tabs.enumerated().map { index, tab in
            if index == selectedIndex {
                return "\u{001B}[7m \(tab) \u{001B}[0m"
            } else {
                return " \(tab) "
            }
        }
        return [tabStrings.joined(separator: "│")]
    }

    func handleInput(_ data: String) {
        if matchesKey(data, Key.left) {
            selectedIndex = max(0, selectedIndex - 1)
            onChange?(selectedIndex)
        } else if matchesKey(data, Key.right) {
            selectedIndex = min(tabs.count - 1, selectedIndex + 1)
            onChange?(selectedIndex)
        }
    }
}
```

## Split View Pattern

### Horizontal Split (Simulated)

```swift
@MainActor
final class SplitView: Component {
    var leftContent: Component
    var rightContent: Component
    var splitRatio: Double = 0.5

    init(left: Component, right: Component) {
        leftContent = left
        rightContent = right
    }

    func render(width: Int) -> [String] {
        let leftWidth = Int(Double(width - 1) * splitRatio)
        let rightWidth = width - leftWidth - 1

        let leftLines = leftContent.render(width: leftWidth)
        let rightLines = rightContent.render(width: rightWidth)

        let maxLines = max(leftLines.count, rightLines.count)
        var lines: [String] = []

        for i in 0..<maxLines {
            let left = (i < leftLines.count ? leftLines[i] : "")
                .padding(toLength: leftWidth, withPad: " ", startingAt: 0)
            let right = i < rightLines.count ? rightLines[i] : ""
            lines.append("\(left)│\(right)")
        }

        return lines
    }
}
```

## Form Pattern

### Form with Validation

```swift
@MainActor
final class FormField: Component {
    let label: String
    let input: Input
    var error: String?
    var validate: ((String) -> String?)?

    init(label: String) {
        self.label = label
        self.input = Input()

        input.onSubmit = { [weak self] text in
            self?.error = self?.validate?(text)
        }
    }

    func render(width: Int) -> [String] {
        var lines: [String] = []
        lines.append("\(label):")
        lines.append(contentsOf: input.render(width: width))
        if let error {
            lines.append("\u{001B}[31m  ⚠ \(error)\u{001B}[0m")
        }
        return lines
    }

    func handleInput(_ data: String) {
        input.handleInput(data)
    }
}

// Usage
let emailField = FormField(label: "Email")
emailField.validate = { text in
    text.contains("@") ? nil : "Invalid email address"
}
```

## Status Bar

### Application Status Bar

```swift
@MainActor
final class StatusBar: Component {
    var leftText: String = ""
    var rightText: String = ""

    func render(width: Int) -> [String] {
        let leftWidth = visibleWidth(leftText)
        let rightWidth = visibleWidth(rightText)
        let padding = max(0, width - leftWidth - rightWidth)

        let line = "\u{001B}[7m" + leftText +
                   String(repeating: " ", count: padding) +
                   rightText + "\u{001B}[0m"
        return [line]
    }
}

// Usage
statusBar.leftText = " MyApp v1.0"
statusBar.rightText = "Ln 42, Col 8 "
```

## Notification Toast

### Auto-dismissing Toast

```swift
@MainActor
final class ToastManager {
    private weak var tui: TUI?
    private var currentHandle: OverlayHandle?

    init(tui: TUI) {
        self.tui = tui
    }

    func show(_ message: String, type: ToastType = .info, duration: TimeInterval = 3) {
        currentHandle?.hide()

        let color: String
        let icon: String
        switch type {
        case .info:
            color = "34"  // Blue
            icon = "ℹ"
        case .success:
            color = "32"  // Green
            icon = "✓"
        case .warning:
            color = "33"  // Yellow
            icon = "⚠"
        case .error:
            color = "31"  // Red
            icon = "✗"
        }

        let toast = Text(
            "\u{001B}[\(color)m\(icon) \(message)\u{001B}[0m",
            paddingX: 2,
            paddingY: 0
        )

        let handle = tui?.showOverlay(toast, options: OverlayOptions(
            anchor: .bottomCenter,
            offsetY: -2
        ))
        currentHandle = handle

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run {
                handle?.hide()
            }
        }
    }

    enum ToastType {
        case info, success, warning, error
    }
}
```

## Keyboard Shortcuts Help

### Help Overlay

```swift
@MainActor
func showKeyboardHelp() {
    let shortcuts = [
        ("Ctrl+S", "Save"),
        ("Ctrl+Q", "Quit"),
        ("Ctrl+F", "Find"),
        ("Ctrl+G", "Go to line"),
        ("Ctrl+Z", "Undo"),
        ("Ctrl+Y", "Redo"),
        ("F1", "Help")
    ]

    let maxKeyLen = shortcuts.map { $0.0.count }.max() ?? 0

    let content = shortcuts.map { key, desc in
        let paddedKey = key.padding(toLength: maxKeyLen, withPad: " ", startingAt: 0)
        return "\u{001B}[33m\(paddedKey)\u{001B}[0m  \(desc)"
    }.joined(separator: "\n")

    let box = Box(paddingX: 2, paddingY: 1)
    box.addChild(Text("\u{001B}[1mKeyboard Shortcuts\u{001B}[0m\n\n\(content)"))

    let handle = tui.showOverlay(box, options: OverlayOptions(
        width: .absolute(35),
        anchor: .center
    ))

    // Close on any key
    let closer = KeyPressHandler { handle.hide() }
    tui.setFocus(closer)
}

@MainActor
final class KeyPressHandler: Component {
    let onKey: () -> Void

    init(onKey: @escaping () -> Void) {
        self.onKey = onKey
    }

    func render(width: Int) -> [String] { [] }

    func handleInput(_ data: String) {
        onKey()
    }
}
```

## Confirmation Dialog

### Reusable Confirm Function

```swift
@MainActor
func confirm(
    _ message: String,
    onConfirm: @escaping () -> Void,
    onCancel: (() -> Void)? = nil
) {
    let box = Box(paddingX: 2, paddingY: 1)
    box.addChild(Text(message))
    box.addChild(Spacer(1))
    box.addChild(Text("\u{001B}[90m[Y]es  [N]o\u{001B}[0m"))

    let handle = tui.showOverlay(box, options: OverlayOptions(
        width: .percent(50),
        minWidth: 30,
        anchor: .center
    ))

    let handler = ConfirmDialogHandler(
        onConfirm: {
            handle.hide()
            onConfirm()
        },
        onCancel: {
            handle.hide()
            onCancel?()
        }
    )
    tui.setFocus(handler)
}

@MainActor
final class ConfirmDialogHandler: Component {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    func render(width: Int) -> [String] { [] }

    func handleInput(_ data: String) {
        if matchesKey(data, "y") || matchesKey(data, Key.enter) {
            onConfirm()
        } else if matchesKey(data, "n") || matchesKey(data, Key.escape) {
            onCancel()
        }
    }
}
```

## Countdown Timer

```swift
@MainActor
final class CountdownTimer: Component {
    private var secondsRemaining: Int
    private var timer: Task<Void, Never>?
    private weak var tui: TUI?
    var onComplete: (() -> Void)?

    init(seconds: Int, tui: TUI) {
        self.secondsRemaining = seconds
        self.tui = tui
    }

    func start() {
        timer = Task { @MainActor in
            while secondsRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                secondsRemaining -= 1
                tui?.requestRender()
            }
            onComplete?()
        }
    }

    func stop() {
        timer?.cancel()
    }

    func render(width: Int) -> [String] {
        let mins = secondsRemaining / 60
        let secs = secondsRemaining % 60
        return [String(format: "Time remaining: %02d:%02d", mins, secs)]
    }
}
```

## Topics

### Components Used

- ``Text``
- ``Box``
- ``Input``
- ``SelectList``
- ``Spacer``
