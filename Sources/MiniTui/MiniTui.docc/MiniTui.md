# ``MiniTui``

A minimal, high-performance Terminal User Interface framework for Swift.

@Metadata {
    @DisplayName("MiniTui")
    @TitleHeading("Framework")
}

## Overview

MiniTui is a component-based TUI framework designed for building interactive command-line applications with:

- **Differential rendering** - Only updates changed screen regions for optimal performance
- **Flicker-free output** - Uses CSI 2026 synchronized output for atomic screen updates
- **Component-based architecture** - Simple protocol-based system for building UI elements
- **Rich input handling** - Supports modern terminal protocols including Kitty keyboard protocol
- **Image rendering** - Inline image support for Kitty, Ghostty, WezTerm, and iTerm2 terminals
- **Extensive text handling** - Proper width calculation for Unicode, emojis, and East Asian characters

### Quick Example

```swift
import MiniTui

@main
struct Demo {
    @MainActor
    static func main() {
        let tui = TUI(terminal: ProcessTerminal())
        let input = Input()

        input.onSubmit = { text in
            print("You typed: \(text)")
        }

        tui.addChild(Text("Type something:"))
        tui.addChild(input)
        tui.setFocus(input)
        tui.start()

        RunLoop.main.run()
    }
}
```

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:CoreConcepts>
- <doc:YourFirstApp>

### Core Types

- ``TUI``
- ``Component``
- ``Terminal``
- ``ProcessTerminal``
- ``Container``

### Built-in Components

- <doc:ComponentOverview>
- ``Text``
- ``TruncatedText``
- ``Input``
- ``Editor``
- ``Markdown``
- ``SelectList``
- ``SettingsList``
- ``Image``
- ``Loader``
- ``CancellableLoader``
- ``Box``
- ``Spacer``

### Overlays

- <doc:WorkingWithOverlays>
- ``OverlayOptions``
- ``OverlayAnchor``
- ``OverlayMargin``
- ``OverlayHandle``
- ``SizeValue``

### Keyboard Input

- <doc:KeyboardHandling>
- ``Key``
- ``matchesKey(_:_:)``
- ``parseKey(_:)``
- ``isKeyRelease(_:)``
- ``isKeyRepeat(_:)``

### Autocomplete

- <doc:AutocompleteSystem>
- ``CombinedAutocompleteProvider``
- ``AutocompleteProvider``
- ``AutocompleteItem``
- ``SlashCommand``

### Theming

- <doc:ThemeReference>
- ``EditorTheme``
- ``MarkdownTheme``
- ``SelectListTheme``
- ``SettingsListTheme``
- ``ImageTheme``

### Utilities

- ``visibleWidth(_:)``
- ``truncateToWidth(_:maxWidth:ellipsis:pad:)``
- ``wrapTextWithAnsi(_:width:)``
- ``fuzzyMatch(_:_:)``
- ``fuzzyFilter(items:query:)``

### Tutorials

- <doc:BuildingAChatInterface>
- <doc:BuildingAFileBrowser>
- <doc:BuildingASettingsPanel>

### Advanced Topics

- <doc:CustomComponents>
- <doc:Performance>
- <doc:Testing>
- <doc:TerminalCompatibility>

### Troubleshooting

- <doc:Troubleshooting>
- <doc:Recipes>
