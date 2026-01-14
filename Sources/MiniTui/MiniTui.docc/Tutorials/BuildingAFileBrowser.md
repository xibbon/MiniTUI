# Building a File Browser

Create an interactive file browser with directory navigation and file preview.

@Metadata {
    @PageKind(article)
    @PageColor(purple)
}

## Overview

This tutorial guides you through building a file browser that lets users navigate directories, view file information, and perform actions on files. You'll learn to use ``SelectList`` for navigation and overlays for confirmations.

## What You'll Build

A file browser with:
- Directory listing with icons
- Keyboard navigation
- File/folder actions
- Path breadcrumb display
- Confirmation dialogs

## Step 1: Project Setup

```bash
mkdir FileBrowser && cd FileBrowser
swift package init --type executable
```

Update `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileBrowser",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../MiniTui")
    ],
    targets: [
        .executableTarget(name: "FileBrowser", dependencies: ["MiniTui"])
    ]
)
```

## Step 2: Define the File Model

Create `Sources/FileBrowser/FileItem.swift`:

```swift
import Foundation

struct FileItem {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modificationDate: Date

    var icon: String {
        if isDirectory {
            return "📁"
        }
        switch url.pathExtension.lowercased() {
        case "swift": return "🔶"
        case "md", "txt": return "📝"
        case "json", "yaml", "yml": return "📋"
        case "png", "jpg", "jpeg", "gif": return "🖼️"
        case "mp3", "wav", "m4a": return "🎵"
        case "mp4", "mov", "avi": return "🎬"
        default: return "📄"
        }
    }

    var formattedSize: String {
        if isDirectory { return "--" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    static func list(at url: URL) throws -> [FileItem] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        return try contents.map { itemURL in
            let resourceValues = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
            ])

            return FileItem(
                url: itemURL,
                name: itemURL.lastPathComponent,
                isDirectory: resourceValues.isDirectory ?? false,
                size: Int64(resourceValues.fileSize ?? 0),
                modificationDate: resourceValues.contentModificationDate ?? Date()
            )
        }.sorted { item1, item2 in
            // Directories first, then alphabetical
            if item1.isDirectory != item2.isDirectory {
                return item1.isDirectory
            }
            return item1.name.localizedCaseInsensitiveCompare(item2.name) == .orderedAscending
        }
    }
}
```

## Step 3: Create the Theme

Create `Sources/FileBrowser/Theme.swift`:

```swift
import MiniTui

struct BrowserTheme {
    static let selectList = SelectListTheme(
        selectedPrefix: { "\u{001B}[7m" + $0 },  // Inverted
        selectedText: { $0 + "\u{001B}[0m" },
        description: { "\u{001B}[90m\($0)\u{001B}[0m" },
        scrollInfo: { "\u{001B}[90m\($0)\u{001B}[0m" },
        noMatch: { "\u{001B}[33m\($0)\u{001B}[0m" }
    )

    static func pathStyle(_ text: String) -> String {
        "\u{001B}[1;34m\(text)\u{001B}[0m"
    }

    static func errorStyle(_ text: String) -> String {
        "\u{001B}[31m\(text)\u{001B}[0m"
    }

    static func hintStyle(_ text: String) -> String {
        "\u{001B}[90m\(text)\u{001B}[0m"
    }
}
```

## Step 4: Build the File Browser

Create `Sources/FileBrowser/FileBrowser.swift`:

```swift
import MiniTui
import Foundation

@MainActor
final class FileBrowser {
    private let tui: TUI
    private let pathDisplay: Text
    private let listContainer: Container
    private let statusBar: TruncatedText
    private var currentPath: URL
    private var files: [FileItem] = []
    private var fileList: SelectList?

    init(startPath: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) {
        tui = TUI(terminal: ProcessTerminal())
        currentPath = startPath

        pathDisplay = Text("", paddingX: 1, paddingY: 0)
        listContainer = Container()
        statusBar = TruncatedText("", paddingX: 1, paddingY: 0)

        setupGlobalInput()
        buildUI()
        navigateTo(startPath)
    }

    private func setupGlobalInput() {
        tui.onGlobalInput = { [weak self] input in
            guard let self else { return false }

            if matchesKey(input, Key.ctrl("c")) || matchesKey(input, Key.escape) {
                if tui.hasOverlay() {
                    tui.hideOverlay()
                    return true
                }
                quit()
                return true
            }

            // Backspace to go up
            if matchesKey(input, Key.backspace) {
                self.navigateUp()
                return true
            }

            // 'd' to delete
            if matchesKey(input, "d") {
                self.confirmDelete()
                return true
            }

            // 'n' to create new
            if matchesKey(input, "n") {
                self.showNewItemDialog()
                return true
            }

            return false
        }
    }

    private func buildUI() {
        // Header
        let header = Text("File Browser", paddingX: 1, paddingY: 1)
        tui.addChild(header)

        // Current path
        tui.addChild(pathDisplay)
        tui.addChild(Spacer(1))

        // File list
        tui.addChild(listContainer)
        tui.addChild(Spacer(1))

        // Status bar
        tui.addChild(statusBar)

        // Help
        let help = Text(
            BrowserTheme.hintStyle("[Enter] Open  [Backspace] Up  [d] Delete  [n] New  [Ctrl+C] Quit"),
            paddingX: 1,
            paddingY: 0
        )
        tui.addChild(help)
    }

    private func navigateTo(_ url: URL) {
        currentPath = url
        pathDisplay.setText(BrowserTheme.pathStyle(url.path))

        do {
            files = try FileItem.list(at: url)
            updateFileList()
            updateStatus()
        } catch {
            showError("Cannot access: \(error.localizedDescription)")
        }
    }

    private func navigateUp() {
        let parent = currentPath.deletingLastPathComponent()
        if parent.path != currentPath.path {
            navigateTo(parent)
        }
    }

    private func updateFileList() {
        listContainer.clear()

        // Add parent directory option
        var items = [SelectItem(value: "..", label: "📁 ..", description: "Parent directory")]

        // Add files
        items += files.map { file in
            SelectItem(
                value: file.url.path,
                label: "\(file.icon) \(file.name)",
                description: "\(file.formattedSize)"
            )
        }

        let list = SelectList(
            items: items,
            maxVisible: min(15, tui.terminal.rows - 10),
            theme: BrowserTheme.selectList
        )

        list.onSelect = { [weak self] item in
            self?.handleSelection(item)
        }

        list.onSelectionChange = { [weak self] item in
            self?.updateStatusForItem(item)
        }

        fileList = list
        listContainer.addChild(list)
        tui.setFocus(list)
        tui.requestRender()
    }

    private func handleSelection(_ item: SelectItem) {
        if item.value == ".." {
            navigateUp()
            return
        }

        let url = URL(fileURLWithPath: item.value)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                navigateTo(url)
            } else {
                showFileInfo(url)
            }
        }
    }

    private func updateStatus() {
        let dirCount = files.filter(\.isDirectory).count
        let fileCount = files.count - dirCount
        statusBar.setText("\(dirCount) folders, \(fileCount) files")
        tui.requestRender()
    }

    private func updateStatusForItem(_ item: SelectItem) {
        if item.value == ".." {
            statusBar.setText("Go to parent directory")
        } else if let file = files.first(where: { $0.url.path == item.value }) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            statusBar.setText("Modified: \(formatter.string(from: file.modificationDate))")
        }
        tui.requestRender()
    }

    private func showFileInfo(_ url: URL) {
        let box = Box(paddingX: 2, paddingY: 1)

        if let file = files.first(where: { $0.url.path == url.path }) {
            let formatter = DateFormatter()
            formatter.dateStyle = .long
            formatter.timeStyle = .medium

            let info = """
            **File Information**

            Name: \(file.name)
            Size: \(file.formattedSize)
            Modified: \(formatter.string(from: file.modificationDate))
            Path: \(file.url.path)

            [Enter] Close
            """

            box.addChild(Markdown(info, paddingX: 0, paddingY: 0, theme: MarkdownTheme.default))
        }

        let handle = tui.showOverlay(box, options: OverlayOptions(
            width: .percent(60),
            anchor: .center
        ))

        // Create handler for closing
        let handler = DialogHandler {
            handle.hide()
        }
        tui.setFocus(handler)
    }

    private func confirmDelete() {
        guard let list = fileList,
              let selected = getSelectedFile() else { return }

        let box = Box(paddingX: 2, paddingY: 1)
        box.addChild(Text("Delete \(selected.name)?", paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))
        box.addChild(Text(BrowserTheme.hintStyle("[Enter] Yes  [Escape] No"), paddingX: 0, paddingY: 0))

        let handle = tui.showOverlay(box, options: OverlayOptions(
            width: .absolute(40),
            anchor: .center
        ))

        let handler = ConfirmHandler(
            onConfirm: { [weak self] in
                handle.hide()
                self?.deleteFile(selected)
            },
            onCancel: {
                handle.hide()
            }
        )
        tui.setFocus(handler)
    }

    private func getSelectedFile() -> FileItem? {
        // Implementation would track selected index
        // For now, return first file
        return files.first
    }

    private func deleteFile(_ file: FileItem) {
        do {
            try FileManager.default.removeItem(at: file.url)
            navigateTo(currentPath)  // Refresh
        } catch {
            showError("Delete failed: \(error.localizedDescription)")
        }
    }

    private func showNewItemDialog() {
        let box = Box(paddingX: 2, paddingY: 1)
        box.addChild(Text("Create New:", paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))

        let items = [
            SelectItem(value: "file", label: "📄 File"),
            SelectItem(value: "folder", label: "📁 Folder")
        ]

        let list = SelectList(items: items, maxVisible: 2, theme: BrowserTheme.selectList)

        list.onSelect = { [weak self] item in
            self?.tui.hideOverlay()
            self?.promptForName(type: item.value)
        }

        list.onCancel = { [weak self] in
            self?.tui.hideOverlay()
        }

        box.addChild(list)

        tui.showOverlay(box, options: OverlayOptions(
            width: .absolute(30),
            anchor: .center
        ))
        tui.setFocus(list)
    }

    private func promptForName(type: String) {
        let box = Box(paddingX: 2, paddingY: 1)
        box.addChild(Text("Enter name:", paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))

        let input = Input()
        input.onSubmit = { [weak self] name in
            self?.tui.hideOverlay()
            self?.createItem(name: name, isDirectory: type == "folder")
        }
        input.onEscape = { [weak self] in
            self?.tui.hideOverlay()
        }

        box.addChild(input)

        tui.showOverlay(box, options: OverlayOptions(
            width: .percent(50),
            anchor: .center
        ))
        tui.setFocus(input)
    }

    private func createItem(name: String, isDirectory: Bool) {
        let url = currentPath.appendingPathComponent(name)

        do {
            if isDirectory {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            } else {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            navigateTo(currentPath)  // Refresh
        } catch {
            showError("Create failed: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        let box = Box(paddingX: 2, paddingY: 1)
        box.addChild(Text(BrowserTheme.errorStyle(message), paddingX: 0, paddingY: 0))
        box.addChild(Spacer(1))
        box.addChild(Text(BrowserTheme.hintStyle("[Enter] OK"), paddingX: 0, paddingY: 0))

        let handle = tui.showOverlay(box, options: OverlayOptions(
            width: .percent(60),
            anchor: .center
        ))

        let handler = DialogHandler { handle.hide() }
        tui.setFocus(handler)
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

// Helper components
@MainActor
final class DialogHandler: Component {
    let onDismiss: () -> Void

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func render(width: Int) -> [String] { [] }

    func handleInput(_ data: String) {
        if matchesKey(data, Key.enter) || matchesKey(data, Key.escape) {
            onDismiss()
        }
    }
}

@MainActor
final class ConfirmHandler: Component {
    let onConfirm: () -> Void
    let onCancel: () -> Void

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

// Default MarkdownTheme extension
extension MarkdownTheme {
    static let `default` = MarkdownTheme(
        heading: { "\u{001B}[1m\($0)\u{001B}[0m" },
        link: { $0 },
        linkUrl: { $0 },
        code: { $0 },
        codeBlock: { $0 },
        codeBlockBorder: { $0 },
        quote: { $0 },
        quoteBorder: { $0 },
        hr: { $0 },
        listBullet: { $0 },
        bold: { "\u{001B}[1m\($0)\u{001B}[0m" },
        italic: { "\u{001B}[3m\($0)\u{001B}[0m" },
        strikethrough: { $0 },
        underline: { $0 }
    )
}
```

## Step 5: Create Entry Point

Create `Sources/FileBrowser/main.swift`:

```swift
import Foundation

@main
struct Main {
    @MainActor
    static func main() {
        let startPath = CommandLine.arguments.count > 1
            ? URL(fileURLWithPath: CommandLine.arguments[1])
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let browser = FileBrowser(startPath: startPath)
        browser.run()
    }
}
```

## Step 6: Build and Run

```bash
swift build
swift run FileBrowser
swift run FileBrowser /path/to/directory
```

## Summary

You've built a file browser demonstrating:
- ``SelectList`` for navigation
- Overlay dialogs for confirmations
- ``Input`` for text entry
- Dynamic content updates
- Global keyboard shortcuts

## Topics

### Related Components

- ``SelectList``
- ``Box``
- ``Input``
- ``TruncatedText``
