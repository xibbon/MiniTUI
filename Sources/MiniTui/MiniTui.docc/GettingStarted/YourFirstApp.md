# Building Your First App

Create a complete interactive terminal application step by step.

@Metadata {
    @PageKind(article)
    @PageColor(blue)
}

## Overview

In this guide, we'll build a simple note-taking application that demonstrates core MiniTui patterns: components, input handling, state management, and overlays.

## Project Setup

Create a new Swift package:

```bash
mkdir NotesApp
cd NotesApp
swift package init --type executable
```

Update `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotesApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../MiniTui")  // Adjust path as needed
    ],
    targets: [
        .executableTarget(
            name: "NotesApp",
            dependencies: ["MiniTui"]
        )
    ]
)
```

## Application Structure

Our notes app will have:
- A header showing the app title
- A list of notes
- An input field for adding new notes
- Keyboard shortcuts for navigation

### Basic Scaffold

Create `Sources/NotesApp/main.swift`:

```swift
import MiniTui

@main
struct NotesApp {
    @MainActor
    static func main() {
        let app = App()
        app.run()
    }
}

@MainActor
final class App {
    private let tui: TUI
    private let header: Text
    private let notesList: Text
    private let input: Input
    private var notes: [String] = []

    init() {
        tui = TUI(terminal: ProcessTerminal())

        // Create components
        header = Text("Notes App - Press Ctrl+D to exit", paddingX: 1, paddingY: 1)
        notesList = Text("No notes yet", paddingX: 1, paddingY: 0)
        input = Input()

        setupInput()
        setupGlobalInput()
        buildUI()
    }

    private func setupInput() {
        input.onSubmit = { [weak self] text in
            guard let self, !text.isEmpty else { return }
            self.addNote(text)
        }

        input.onEnd = { [weak self] in
            self?.quit()
        }
    }

    private func setupGlobalInput() {
        tui.onGlobalInput = { [weak self] data in
            if matchesKey(data, Key.ctrl("c")) {
                self?.quit()
                return true
            }
            return false
        }
    }

    private func buildUI() {
        tui.addChild(header)
        tui.addChild(Spacer(1))
        tui.addChild(notesList)
        tui.addChild(Spacer(1))
        tui.addChild(Text("Add note:", paddingX: 1, paddingY: 0))
        tui.addChild(input)

        tui.setFocus(input)
    }

    private func addNote(_ text: String) {
        notes.append(text)
        updateNotesList()
        tui.requestRender()
    }

    private func updateNotesList() {
        if notes.isEmpty {
            notesList.setText("No notes yet")
        } else {
            let numbered = notes.enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")
            notesList.setText(numbered)
        }
    }

    private func quit() {
        tui.stop()
        exit(0)
    }

    func run() {
        tui.start()
        RunLoop.main.run()
    }
}
```

## Adding Note Deletion

Let's add the ability to delete notes with a confirmation dialog using overlays:

```swift
@MainActor
final class App {
    // ... existing properties ...
    private var selectedNoteIndex: Int = 0

    private func setupGlobalInput() {
        tui.onGlobalInput = { [weak self] data in
            guard let self else { return false }

            if matchesKey(data, Key.ctrl("c")) {
                self.quit()
                return true
            }

            // Navigate notes with Ctrl+Up/Down
            if matchesKey(data, Key.ctrl("up")) {
                self.selectPreviousNote()
                return true
            }
            if matchesKey(data, Key.ctrl("down")) {
                self.selectNextNote()
                return true
            }

            // Delete with Ctrl+X
            if matchesKey(data, Key.ctrl("x")) {
                self.confirmDelete()
                return true
            }

            return false
        }
    }

    private func selectPreviousNote() {
        guard !notes.isEmpty else { return }
        selectedNoteIndex = max(0, selectedNoteIndex - 1)
        updateNotesList()
        tui.requestRender()
    }

    private func selectNextNote() {
        guard !notes.isEmpty else { return }
        selectedNoteIndex = min(notes.count - 1, selectedNoteIndex + 1)
        updateNotesList()
        tui.requestRender()
    }

    private func updateNotesList() {
        if notes.isEmpty {
            notesList.setText("No notes yet")
            selectedNoteIndex = 0
        } else {
            let numbered = notes.enumerated()
                .map { index, note in
                    let prefix = index == selectedNoteIndex ? "> " : "  "
                    return "\(prefix)\(index + 1). \(note)"
                }
                .joined(separator: "\n")
            notesList.setText(numbered)
        }
    }

    private func confirmDelete() {
        guard !notes.isEmpty else { return }

        let dialog = Box(paddingX: 2, paddingY: 1)
        let message = Text("Delete note \(selectedNoteIndex + 1)?", paddingX: 0, paddingY: 0)
        let hint = Text("[Enter] Yes  [Escape] No", paddingX: 0, paddingY: 1)

        dialog.addChild(message)
        dialog.addChild(hint)

        let handle = tui.showOverlay(dialog, options: OverlayOptions(
            width: .absolute(30),
            anchor: .center
        ))

        // Create a temporary component to handle dialog input
        let dialogHandler = DialogHandler(
            onConfirm: { [weak self] in
                handle.hide()
                self?.deleteSelectedNote()
            },
            onCancel: {
                handle.hide()
            }
        )

        tui.setFocus(dialogHandler)
    }

    private func deleteSelectedNote() {
        guard selectedNoteIndex < notes.count else { return }
        notes.remove(at: selectedNoteIndex)
        if selectedNoteIndex >= notes.count && selectedNoteIndex > 0 {
            selectedNoteIndex -= 1
        }
        updateNotesList()
        tui.setFocus(input)
        tui.requestRender()
    }
}

@MainActor
final class DialogHandler: Component {
    var onConfirm: () -> Void
    var onCancel: () -> Void

    init(onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    func render(width: Int) -> [String] { [] }

    func handleInput(_ data: String) {
        if matchesKey(data, Key.enter) {
            onConfirm()
        } else if matchesKey(data, Key.escape) {
            onCancel()
        }
    }
}
```

## Using SelectList for Note Selection

For a better selection experience, use the built-in ``SelectList`` component:

```swift
private func showNoteSelector() {
    guard !notes.isEmpty else { return }

    let items = notes.enumerated().map { index, note in
        SelectItem(value: String(index), label: note, description: nil)
    }

    let theme = SelectListTheme(
        selectedPrefix: { "> " + $0 },
        selectedText: { $0 },
        description: { $0 },
        scrollInfo: { $0 },
        noMatch: { $0 }
    )

    let list = SelectList(items: items, maxVisible: 8, theme: theme)

    list.onSelect = { [weak self] item in
        self?.tui.hideOverlay()
        if let index = Int(item.value) {
            self?.selectedNoteIndex = index
            self?.updateNotesList()
        }
        self?.tui.setFocus(self?.input)
        self?.tui.requestRender()
    }

    list.onCancel = { [weak self] in
        self?.tui.hideOverlay()
        self?.tui.setFocus(self?.input)
        self?.tui.requestRender()
    }

    let box = Box(paddingX: 1, paddingY: 1)
    box.addChild(Text("Select a note:", paddingX: 0, paddingY: 0))
    box.addChild(Spacer(1))
    box.addChild(list)

    tui.showOverlay(box, options: OverlayOptions(
        width: .percent(60),
        maxHeight: .percent(50),
        anchor: .center
    ))
    tui.setFocus(list)
}
```

## Running the App

```bash
swift build
swift run NotesApp
```

### Controls

- Type text and press Enter to add a note
- Ctrl+Up/Down to select notes
- Ctrl+X to delete selected note
- Ctrl+D on empty input or Ctrl+C to exit

## Next Steps

You've built a functional notes application! Explore more:

- <doc:ComponentOverview> - Learn about all available components
- <doc:WorkingWithOverlays> - Master the overlay system
- <doc:KeyboardHandling> - Handle complex keyboard input
- <doc:CustomComponents> - Create your own components

## Topics

### Building Blocks

- ``TUI``
- ``Text``
- ``Input``
- ``SelectList``
- ``Box``
- ``Spacer``
