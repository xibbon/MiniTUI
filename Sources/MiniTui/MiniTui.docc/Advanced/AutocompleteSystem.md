# Autocomplete System

Provide intelligent suggestions for slash commands and file paths.

@Metadata {
    @PageKind(article)
    @PageColor(orange)
}

## Overview

MiniTui's autocomplete system provides suggestions for slash commands and file paths in the ``Editor`` component. You can configure built-in providers or create custom ones.

## CombinedAutocompleteProvider

The ``CombinedAutocompleteProvider`` handles both slash commands and file path completion:

```swift
let provider = CombinedAutocompleteProvider(
    commands: [
        SlashCommand(name: "help", description: "Show help"),
        SlashCommand(name: "clear", description: "Clear screen"),
        SlashCommand(name: "quit", description: "Exit application")
    ],
    items: [],
    basePath: FileManager.default.currentDirectoryPath
)

editor.setAutocompleteProvider(provider)
```

## Slash Commands

Define commands that appear when users type `/`:

```swift
let commands = [
    SlashCommand(name: "help", description: "Show available commands"),
    SlashCommand(name: "clear", description: "Clear conversation history"),
    SlashCommand(name: "model", description: "Change AI model"),
    SlashCommand(name: "settings", description: "Open settings panel"),
    SlashCommand(name: "export", description: "Export conversation")
]

let provider = CombinedAutocompleteProvider(
    commands: commands,
    items: [],
    basePath: nil
)
```

### Command Matching

Commands use fuzzy matching, so typing `/hlp` matches "help" and `/mdl` matches "model".

## Autocomplete Items

Add general autocomplete items that aren't slash commands:

```swift
let items = [
    AutocompleteItem(value: "gpt-4", label: "GPT-4", description: "Most capable model"),
    AutocompleteItem(value: "gpt-3.5", label: "GPT-3.5", description: "Faster, less capable"),
    AutocompleteItem(value: "claude", label: "Claude", description: "Anthropic's model")
]

let provider = CombinedAutocompleteProvider(
    commands: [],
    items: items,
    basePath: nil
)
```

## File Path Completion

Enable file path completion by providing a `basePath`:

```swift
let provider = CombinedAutocompleteProvider(
    commands: commands,
    items: [],
    basePath: FileManager.default.currentDirectoryPath,
    fdPath: "/opt/homebrew/bin/fd"  // Optional: use fd for faster searches
)
```

### Path Triggers

File completion triggers on:
- `./` - Relative paths
- `../` - Parent directory paths
- `~/` - Home directory paths
- `@` - Attachment prefix (filters to attachable file types)

### Tab to Complete

Press Tab in the editor to trigger file path completion when the cursor is after a path-like pattern.

## Custom Autocomplete Provider

Create custom providers by implementing ``AutocompleteProvider``:

```swift
@MainActor
final class CustomProvider: AutocompleteProvider {
    func getCompletions(
        text: String,
        cursorPosition: Int
    ) async -> [AutocompleteItem] {
        // Extract word at cursor
        let word = extractWordAtCursor(text, position: cursorPosition)

        // Return matching items
        return dictionary.filter { $0.hasPrefix(word) }
            .map { AutocompleteItem(value: $0, label: $0, description: nil) }
    }

    private func extractWordAtCursor(_ text: String, position: Int) -> String {
        // Implementation to extract current word
    }
}
```

### Combining Providers

You can chain providers:

```swift
@MainActor
final class ChainedProvider: AutocompleteProvider {
    private let providers: [AutocompleteProvider]

    init(providers: [AutocompleteProvider]) {
        self.providers = providers
    }

    func getCompletions(text: String, cursorPosition: Int) async -> [AutocompleteItem] {
        var results: [AutocompleteItem] = []
        for provider in providers {
            let items = await provider.getCompletions(text: text, cursorPosition: cursorPosition)
            results.append(contentsOf: items)
        }
        return results
    }
}
```

## Autocomplete UI

The ``Editor`` displays autocomplete suggestions in a dropdown. The appearance is controlled by the ``SelectListTheme`` in ``EditorTheme``:

```swift
let selectListTheme = SelectListTheme(
    selectedPrefix: { "\u{001B}[32m> \u{001B}[0m" + $0 },
    selectedText: { "\u{001B}[1m\($0)\u{001B}[0m" },
    description: { "\u{001B}[90m\($0)\u{001B}[0m" },
    scrollInfo: { "\u{001B}[90m\($0)\u{001B}[0m" },
    noMatch: { "\u{001B}[33m\($0)\u{001B}[0m" }
)

let editorTheme = EditorTheme(
    borderColor: { $0 },
    selectList: selectListTheme
)
```

## Fuzzy Matching

MiniTui includes fuzzy matching utilities:

```swift
// Check if query matches target
if let match = fuzzyMatch("hlp", "help") {
    print("Match score: \(match.score)")
    print("Matched indices: \(match.indices)")
}

// Filter a list
let results = fuzzyFilter(items: items, query: "mdl") { $0.label }
// Returns items sorted by match quality
```

### FuzzyMatch Result

```swift
struct FuzzyMatch {
    let score: Int       // Higher is better
    let indices: [Int]   // Matched character positions
}
```

## Integration Example

Complete example with slash commands and dynamic items:

```swift
@MainActor
final class ChatApp {
    private let editor: Editor
    private var availableModels: [String] = ["gpt-4", "gpt-3.5", "claude"]

    init() {
        editor = Editor(theme: theme)
        updateAutocomplete()
    }

    func updateAutocomplete() {
        let commands = [
            SlashCommand(name: "help", description: "Show help"),
            SlashCommand(name: "clear", description: "Clear history"),
            SlashCommand(name: "model", description: "Select model: " + availableModels.joined(separator: ", ")),
            SlashCommand(name: "settings", description: "Open settings")
        ]

        // Dynamic items based on context
        let modelItems = availableModels.map {
            AutocompleteItem(value: "/model \($0)", label: $0, description: "Switch to \($0)")
        }

        let provider = CombinedAutocompleteProvider(
            commands: commands,
            items: modelItems,
            basePath: FileManager.default.currentDirectoryPath
        )

        editor.setAutocompleteProvider(provider)
    }

    func handleSubmit(_ text: String) {
        if text.hasPrefix("/model ") {
            let model = String(text.dropFirst(7))
            selectModel(model)
        } else if text == "/help" {
            showHelp()
        } else if text == "/clear" {
            clearHistory()
        } else {
            sendMessage(text)
        }
    }
}
```

## Topics

### Types

- ``CombinedAutocompleteProvider``
- ``AutocompleteProvider``
- ``AutocompleteItem``
- ``SlashCommand``

### Fuzzy Matching

- ``fuzzyMatch(_:_:)``
- ``fuzzyFilter(items:query:)``
- ``FuzzyMatch``
