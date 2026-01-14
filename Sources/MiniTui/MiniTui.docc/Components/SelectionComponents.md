# Selection Components

Present choices and configuration options to users.

@Metadata {
    @PageKind(article)
    @PageColor(green)
}

## Overview

MiniTui provides two selection components: ``SelectList`` for choosing from a list of options, and ``SettingsList`` for configuring application settings with cycling values and submenus.

## SelectList

``SelectList`` displays a navigable list of options with optional filtering.

### Basic Usage

```swift
let items = [
    SelectItem(value: "opt1", label: "Option 1"),
    SelectItem(value: "opt2", label: "Option 2"),
    SelectItem(value: "opt3", label: "Option 3")
]

let list = SelectList(items: items, maxVisible: 5, theme: theme)

list.onSelect = { item in
    print("Selected: \(item.value)")
}

list.onCancel = {
    print("Selection cancelled")
}

tui.addChild(list)
tui.setFocus(list)
```

### SelectItem Structure

```swift
let item = SelectItem(
    value: "unique-id",           // Internal identifier
    label: "Display Text",        // Shown to user
    description: "Optional help"  // Additional context
)
```

### Theming

```swift
let theme = SelectListTheme(
    selectedPrefix: { text in
        "\u{001B}[32m> \u{001B}[0m" + text  // Green arrow
    },
    selectedText: { text in
        "\u{001B}[1m\(text)\u{001B}[0m"      // Bold
    },
    description: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"     // Gray
    },
    scrollInfo: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"     // Gray scroll indicator
    },
    noMatch: { text in
        "\u{001B}[33m\(text)\u{001B}[0m"     // Yellow "no matches"
    }
)
```

### Filtering

Filter the list programmatically:

```swift
list.setFilter("opt")  // Shows items matching "opt"
list.setFilter("")     // Show all items
```

Filtering uses fuzzy matching, so "opt1" matches "Option 1".

### Selection Change Handler

React to highlight changes (not just selection):

```swift
list.onSelectionChange = { item in
    // Called when user navigates up/down
    showPreview(for: item)
}
```

### Keyboard Controls

| Key | Action |
|-----|--------|
| Up | Move selection up |
| Down | Move selection down |
| Page Up | Move up one page |
| Page Down | Move down one page |
| Home | Jump to first item |
| End | Jump to last item |
| Enter | Select current item |
| Escape / Ctrl+C | Cancel selection |

### Scroll Indicator

When items exceed `maxVisible`, a scroll indicator appears:

```
  Option 1
> Option 2
  Option 3
  (1-3 of 10)
```

## SettingsList

``SettingsList`` presents configuration options with value cycling and submenu support.

### Basic Usage

```swift
let items = [
    SettingItem(
        id: "theme",
        label: "Theme",
        currentValue: "dark",
        values: ["dark", "light", "auto"]
    ),
    SettingItem(
        id: "fontSize",
        label: "Font Size",
        currentValue: "14",
        values: ["12", "14", "16", "18"]
    )
]

let settings = SettingsList(
    items: items,
    maxVisible: 8,
    theme: theme,
    onChange: { id, newValue in
        print("\(id) changed to \(newValue)")
        saveSettings(id: id, value: newValue)
    },
    onCancel: {
        dismissSettings()
    }
)
```

### Theming

```swift
let theme = SettingsListTheme(
    label: { text, isSelected in
        isSelected ? "\u{001B}[1m\(text)\u{001B}[0m" : text
    },
    value: { text, isSelected in
        "\u{001B}[36m\(text)\u{001B}[0m"  // Cyan values
    },
    description: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"  // Gray descriptions
    },
    cursor: "> ",                          // Selection indicator
    hint: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"  // Gray hints
    }
)
```

### Value Cycling

When the user presses Enter or Space on a setting with `values`, the value cycles to the next option:

```swift
// dark -> light -> auto -> dark -> ...
```

### Submenus

For complex settings, use a submenu:

```swift
let item = SettingItem(
    id: "model",
    label: "AI Model",
    currentValue: "gpt-4",
    submenu: { settingsList, item in
        // Return a component to display as submenu
        let modelList = SelectList(items: modelOptions, ...)
        modelList.onSelect = { selected in
            settingsList.updateValue(id: item.id, newValue: selected.value)
            // Close submenu
        }
        return modelList
    }
)
```

### Search Support

Enable search to filter settings:

```swift
let options = SettingsListOptions(enableSearch: true)

let settings = SettingsList(
    items: items,
    maxVisible: 8,
    theme: theme,
    onChange: onChange,
    onCancel: onCancel,
    options: options
)
```

With search enabled:
- Type to filter settings by label
- Filtering uses fuzzy matching
- Space-separated terms must all match

### Updating Values Programmatically

```swift
settings.updateValue(id: "theme", newValue: "light")
```

### Keyboard Controls

| Key | Action |
|-----|--------|
| Up | Move selection up |
| Down | Move selection down |
| Enter / Space | Cycle value or open submenu |
| Escape / Ctrl+C | Cancel / close submenu |
| (typing) | Filter settings (if search enabled) |

## Common Patterns

### Menu in Overlay

```swift
func showMenu() {
    let items = [
        SelectItem(value: "new", label: "New File"),
        SelectItem(value: "open", label: "Open..."),
        SelectItem(value: "save", label: "Save"),
        SelectItem(value: "quit", label: "Quit")
    ]

    let menu = SelectList(items: items, maxVisible: 10, theme: menuTheme)

    menu.onSelect = { [weak self] item in
        self?.tui.hideOverlay()
        self?.handleMenuAction(item.value)
    }

    menu.onCancel = { [weak self] in
        self?.tui.hideOverlay()
    }

    let box = Box(paddingX: 1, paddingY: 1)
    box.addChild(menu)

    tui.showOverlay(box, options: OverlayOptions(
        width: .absolute(30),
        anchor: .topLeft,
        offsetX: 2,
        offsetY: 1
    ))
    tui.setFocus(menu)
}
```

### Dynamic Item Updates

```swift
func refreshFileList() {
    let files = listFiles()
    let items = files.map { file in
        SelectItem(value: file.path, label: file.name, description: file.size)
    }

    // Create new list with updated items
    let newList = SelectList(items: items, maxVisible: 10, theme: theme)
    // ... configure handlers ...

    // Replace in UI
    container.removeChild(oldList)
    container.addChild(newList)
    tui.setFocus(newList)
    tui.requestRender()
}
```

## Topics

### Components

- ``SelectList``
- ``SettingsList``

### Data Types

- ``SelectItem``
- ``SettingItem``

### Theming

- ``SelectListTheme``
- ``SettingsListTheme``
- ``SettingsListOptions``
