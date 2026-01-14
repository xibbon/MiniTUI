# Building a Chat Interface

Create an interactive chat application with message display, input handling, and loading states.

@Metadata {
    @PageKind(article)
    @PageColor(purple)
}

## Overview

This tutorial walks through building a chat interface that displays messages with Markdown formatting, handles user input, and shows loading states during responses. You'll learn to compose multiple components and manage application state.

## What You'll Build

A chat application with:
- Message history with Markdown rendering
- Multi-line input with autocomplete
- Loading spinner during "thinking" time
- Scroll management for long conversations

## Step 1: Project Setup

Create a new Swift package:

```bash
mkdir ChatApp && cd ChatApp
swift package init --type executable
```

Update `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ChatApp",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../MiniTui")
    ],
    targets: [
        .executableTarget(name: "ChatApp", dependencies: ["MiniTui"])
    ]
)
```

## Step 2: Define the Data Model

Create `Sources/ChatApp/Message.swift`:

```swift
import Foundation

struct Message: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }

    init(role: Role, content: String) {
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}
```

## Step 3: Create Theme Configuration

Create `Sources/ChatApp/Theme.swift`:

```swift
import MiniTui

struct AppTheme {
    // Message styling
    static func userMessage(_ text: String) -> String {
        "\u{001B}[36m\(text)\u{001B}[0m"  // Cyan
    }

    static func assistantMessage(_ text: String) -> String {
        text  // Default color
    }

    static func timestamp(_ text: String) -> String {
        "\u{001B}[90m\(text)\u{001B}[0m"  // Gray
    }

    // Markdown theme
    static let markdown = MarkdownTheme(
        heading: { "\u{001B}[1;34m\($0)\u{001B}[0m" },
        link: { "\u{001B}[4;34m\($0)\u{001B}[0m" },
        linkUrl: { "\u{001B}[90m\($0)\u{001B}[0m" },
        code: { "\u{001B}[33m\($0)\u{001B}[0m" },
        codeBlock: { $0 },
        codeBlockBorder: { "\u{001B}[90m\($0)\u{001B}[0m" },
        quote: { "\u{001B}[3m\($0)\u{001B}[0m" },
        quoteBorder: { "\u{001B}[90m\($0)\u{001B}[0m" },
        hr: { "\u{001B}[90m\($0)\u{001B}[0m" },
        listBullet: { "\u{001B}[34m\($0)\u{001B}[0m" },
        bold: { "\u{001B}[1m\($0)\u{001B}[0m" },
        italic: { "\u{001B}[3m\($0)\u{001B}[0m" },
        strikethrough: { "\u{001B}[9m\($0)\u{001B}[0m" },
        underline: { "\u{001B}[4m\($0)\u{001B}[0m" }
    )

    // Editor theme
    static let selectList = SelectListTheme(
        selectedPrefix: { "\u{001B}[32m> \u{001B}[0m" + $0 },
        selectedText: { "\u{001B}[1m\($0)\u{001B}[0m" },
        description: { "\u{001B}[90m\($0)\u{001B}[0m" },
        scrollInfo: { "\u{001B}[90m\($0)\u{001B}[0m" },
        noMatch: { "\u{001B}[33m\($0)\u{001B}[0m" }
    )

    static let editor = EditorTheme(
        borderColor: { "\u{001B}[90m\($0)\u{001B}[0m" },
        selectList: selectList
    )
}
```

## Step 4: Create the Message Component

Create `Sources/ChatApp/MessageView.swift`:

```swift
import MiniTui

@MainActor
final class MessageView: Component {
    private let message: Message
    private let markdown: Markdown
    private let header: String

    init(message: Message) {
        self.message = message

        let formatter = DateFormatter()
        formatter.timeStyle = .short

        let roleLabel = message.role == .user ? "You" : "Assistant"
        let time = formatter.string(from: message.timestamp)
        self.header = AppTheme.timestamp("[\(time)] ") +
                     (message.role == .user
                         ? AppTheme.userMessage(roleLabel)
                         : AppTheme.assistantMessage(roleLabel))

        self.markdown = Markdown(
            message.content,
            paddingX: 2,
            paddingY: 0,
            theme: AppTheme.markdown
        )
    }

    func render(width: Int) -> [String] {
        var lines: [String] = []
        lines.append(header)
        lines.append(contentsOf: markdown.render(width: width))
        lines.append("")  // Spacing after message
        return lines
    }

    func handleInput(_ data: String) {}
    func invalidate() { markdown.invalidate() }
}
```

## Step 5: Build the Main Application

Create `Sources/ChatApp/ChatApp.swift`:

```swift
import MiniTui
import Foundation

@MainActor
final class ChatApp {
    private let tui: TUI
    private let messagesContainer: Container
    private let editor: Editor
    private var loader: Loader?
    private var messages: [Message] = []

    init() {
        tui = TUI(terminal: ProcessTerminal())
        messagesContainer = Container()
        editor = Editor(theme: AppTheme.editor)

        setupEditor()
        setupGlobalInput()
        buildUI()
    }

    private func setupEditor() {
        // Configure autocomplete
        let provider = CombinedAutocompleteProvider(
            commands: [
                SlashCommand(name: "clear", description: "Clear chat history"),
                SlashCommand(name: "help", description: "Show help"),
                SlashCommand(name: "quit", description: "Exit application")
            ],
            items: [],
            basePath: FileManager.default.currentDirectoryPath
        )
        editor.setAutocompleteProvider(provider)

        // Handle submission
        editor.onSubmit = { [weak self] text in
            self?.handleInput(text)
        }
    }

    private func setupGlobalInput() {
        tui.onGlobalInput = { [weak self] input in
            if matchesKey(input, Key.ctrl("c")) {
                self?.quit()
                return true
            }
            return false
        }
    }

    private func buildUI() {
        // Header
        let header = Text("Chat Demo - Type /help for commands", paddingX: 1, paddingY: 1)
        tui.addChild(header)

        // Messages area
        tui.addChild(messagesContainer)

        // Separator
        tui.addChild(Spacer(1))

        // Editor
        tui.addChild(editor)

        tui.setFocus(editor)
    }

    private func handleInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Handle slash commands
        if trimmed.hasPrefix("/") {
            handleCommand(trimmed)
            return
        }

        // Add user message
        addMessage(Message(role: .user, content: trimmed))

        // Show loader and simulate response
        showLoader()
        simulateResponse(to: trimmed)
    }

    private func handleCommand(_ command: String) {
        switch command {
        case "/clear":
            messages.removeAll()
            messagesContainer.clear()
            tui.requestRender()

        case "/help":
            let help = """
            **Available Commands:**
            - `/clear` - Clear chat history
            - `/help` - Show this help
            - `/quit` - Exit application

            **Keyboard Shortcuts:**
            - `Enter` - Send message
            - `Shift+Enter` - New line
            - `Tab` - Autocomplete
            - `Ctrl+C` - Quit
            """
            addMessage(Message(role: .assistant, content: help))

        case "/quit":
            quit()

        default:
            addMessage(Message(role: .assistant, content: "Unknown command: \(command)"))
        }
    }

    private func addMessage(_ message: Message) {
        messages.append(message)
        messagesContainer.addChild(MessageView(message: message))
        tui.requestRender()
    }

    private func showLoader() {
        let newLoader = Loader(
            ui: tui,
            spinnerColorFn: { "\u{001B}[33m\($0)\u{001B}[0m" },
            messageColorFn: { "\u{001B}[90m\($0)\u{001B}[0m" },
            message: "Thinking..."
        )
        loader = newLoader
        tui.addChild(newLoader)
        tui.requestRender()
    }

    private func hideLoader() {
        if let loader {
            loader.stop()
            tui.removeChild(loader)
            self.loader = nil
            tui.requestRender()
        }
    }

    private func simulateResponse(to input: String) {
        // Simulate network delay
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            await MainActor.run {
                hideLoader()

                // Generate a simple response
                let response = generateResponse(to: input)
                addMessage(Message(role: .assistant, content: response))
            }
        }
    }

    private func generateResponse(to input: String) -> String {
        // Simple echo response for demo
        return """
        You said: *\(input)*

        This is a demo response. In a real application, you would:
        1. Send the input to an AI API
        2. Stream the response
        3. Display it incrementally

        Try `/help` for available commands.
        """
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

## Step 6: Create the Entry Point

Create `Sources/ChatApp/main.swift`:

```swift
import MiniTui

@main
struct Main {
    @MainActor
    static func main() {
        let app = ChatApp()
        app.run()
    }
}
```

## Step 7: Build and Run

```bash
swift build
swift run ChatApp
```

## Enhancements

### Streaming Responses

For real AI integration, you'd stream responses:

```swift
private func streamResponse(_ response: AsyncStream<String>) async {
    var content = ""
    let messageView = StreamingMessageView()
    messagesContainer.addChild(messageView)

    for await chunk in response {
        content += chunk
        messageView.updateContent(content)
        tui.requestRender()
    }

    // Finalize message
    messages.append(Message(role: .assistant, content: content))
}
```

### Cancellable Responses

Use `CancellableLoader` for interruptible operations:

```swift
let loader = CancellableLoader(ui: tui, message: "Thinking...")
loader.onAbort = { [weak self] in
    self?.cancelCurrentRequest()
}
```

### Message Actions

Add context menus for messages:

```swift
func showMessageActions(for message: Message) {
    let items = [
        SelectItem(value: "copy", label: "Copy"),
        SelectItem(value: "delete", label: "Delete"),
        SelectItem(value: "retry", label: "Retry")
    ]
    // Show as overlay...
}
```

## Summary

You've built a functional chat interface with:
- Component composition (Container, Markdown, Editor)
- State management (messages array)
- Async operations (simulated responses)
- User feedback (Loader)

## Next Steps

- <doc:WorkingWithOverlays> - Add menus and dialogs
- <doc:AutocompleteSystem> - Enhance autocomplete
- <doc:CustomComponents> - Create reusable components

## Topics

### Related Components

- ``Editor``
- ``Markdown``
- ``Loader``
- ``Container``
