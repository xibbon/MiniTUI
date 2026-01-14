# Theme Reference

Comprehensive guide to styling MiniTui components with themes.

@Metadata {
    @PageKind(article)
    @PageColor(teal)
}

## Overview

MiniTui components accept theme objects that customize their appearance through styling functions. Each function receives a string and returns a styled version, typically using ANSI escape codes.

## ANSI Styling Basics

ANSI escape codes style terminal text:

```swift
// Basic format: \u{001B}[<code>m<text>\u{001B}[0m
let red = "\u{001B}[31mRed text\u{001B}[0m"
let bold = "\u{001B}[1mBold text\u{001B}[0m"
let combined = "\u{001B}[1;31mBold red\u{001B}[0m"
```

### Common Codes

| Code | Effect |
|------|--------|
| 0 | Reset all |
| 1 | Bold |
| 2 | Dim |
| 3 | Italic |
| 4 | Underline |
| 7 | Inverse |
| 9 | Strikethrough |

### Foreground Colors

| Code | Color | Code | Bright Color |
|------|-------|------|--------------|
| 30 | Black | 90 | Bright Black (Gray) |
| 31 | Red | 91 | Bright Red |
| 32 | Green | 92 | Bright Green |
| 33 | Yellow | 93 | Bright Yellow |
| 34 | Blue | 94 | Bright Blue |
| 35 | Magenta | 95 | Bright Magenta |
| 36 | Cyan | 96 | Bright Cyan |
| 37 | White | 97 | Bright White |

### Background Colors

| Code | Color | Code | Bright Color |
|------|-------|------|--------------|
| 40 | Black | 100 | Bright Black |
| 41 | Red | 101 | Bright Red |
| 42 | Green | 102 | Bright Green |
| 43 | Yellow | 103 | Bright Yellow |
| 44 | Blue | 104 | Bright Blue |
| 45 | Magenta | 105 | Bright Magenta |
| 46 | Cyan | 106 | Bright Cyan |
| 47 | White | 107 | Bright White |

### 256-Color Mode

```swift
// Foreground: \u{001B}[38;5;<n>m
let orange = "\u{001B}[38;5;208m"

// Background: \u{001B}[48;5;<n>m
let grayBg = "\u{001B}[48;5;236m"
```

### True Color (24-bit)

```swift
// Foreground: \u{001B}[38;2;<r>;<g>;<b>m
let customRed = "\u{001B}[38;2;255;100;100m"

// Background: \u{001B}[48;2;<r>;<g>;<b>m
let customBg = "\u{001B}[48;2;40;44;52m"
```

## EditorTheme

Styles the ``Editor`` component:

```swift
let theme = EditorTheme(
    borderColor: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"  // Gray borders
    },
    selectList: selectListTheme
)
```

| Property | Purpose |
|----------|---------|
| `borderColor` | Editor border styling |
| `selectList` | Theme for autocomplete dropdown |

## SelectListTheme

Styles the ``SelectList`` component:

```swift
let theme = SelectListTheme(
    selectedPrefix: { text in
        "\u{001B}[32m> \u{001B}[0m" + text  // Green arrow
    },
    selectedText: { text in
        "\u{001B}[1m\(text)\u{001B}[0m"      // Bold selected item
    },
    description: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"     // Gray descriptions
    },
    scrollInfo: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"     // Gray scroll indicator
    },
    noMatch: { text in
        "\u{001B}[33m\(text)\u{001B}[0m"     // Yellow "no matches"
    }
)
```

| Property | Purpose | Example Output |
|----------|---------|----------------|
| `selectedPrefix` | Prefix for selected item | `> Option` |
| `selectedText` | Selected item text | `**Option**` |
| `description` | Item description text | `(helper text)` |
| `scrollInfo` | Scroll position indicator | `(1-5 of 10)` |
| `noMatch` | No results message | `No matches` |

## SettingsListTheme

Styles the ``SettingsList`` component:

```swift
let theme = SettingsListTheme(
    label: { text, isSelected in
        isSelected ? "\u{001B}[1m\(text)\u{001B}[0m" : text
    },
    value: { text, isSelected in
        "\u{001B}[36m\(text)\u{001B}[0m"    // Cyan values
    },
    description: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"    // Gray descriptions
    },
    cursor: "\u{001B}[33m▸\u{001B}[0m ",    // Yellow cursor
    hint: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"    // Gray hints
    }
)
```

| Property | Purpose | Parameters |
|----------|---------|------------|
| `label` | Setting label | `(text, isSelected)` |
| `value` | Current value | `(text, isSelected)` |
| `description` | Setting description | `(text)` |
| `cursor` | Selection indicator | String literal |
| `hint` | Keyboard hints | `(text)` |

## MarkdownTheme

Styles the ``Markdown`` component:

```swift
let theme = MarkdownTheme(
    heading: { "\u{001B}[1;34m\($0)\u{001B}[0m" },      // Bold blue
    link: { "\u{001B}[4;34m\($0)\u{001B}[0m" },         // Underlined blue
    linkUrl: { "\u{001B}[90m\($0)\u{001B}[0m" },        // Gray
    code: { "\u{001B}[33m\($0)\u{001B}[0m" },           // Yellow
    codeBlock: { $0 },                                   // No change
    codeBlockBorder: { "\u{001B}[90m\($0)\u{001B}[0m" }, // Gray
    quote: { "\u{001B}[3m\($0)\u{001B}[0m" },           // Italic
    quoteBorder: { "\u{001B}[90m\($0)\u{001B}[0m" },    // Gray
    hr: { "\u{001B}[90m\($0)\u{001B}[0m" },             // Gray
    listBullet: { "\u{001B}[34m\($0)\u{001B}[0m" },     // Blue
    bold: { "\u{001B}[1m\($0)\u{001B}[0m" },            // Bold
    italic: { "\u{001B}[3m\($0)\u{001B}[0m" },          // Italic
    strikethrough: { "\u{001B}[9m\($0)\u{001B}[0m" },   // Strikethrough
    underline: { "\u{001B}[4m\($0)\u{001B}[0m" }        // Underline
)
```

| Property | Markdown Element |
|----------|-----------------|
| `heading` | `# Heading` |
| `link` | Link text `[text]` |
| `linkUrl` | Link URL `(url)` |
| `code` | Inline `` `code` `` |
| `codeBlock` | Fenced code block content |
| `codeBlockBorder` | ``` ``` delimiters |
| `quote` | `> quote` text |
| `quoteBorder` | Quote marker `│` |
| `hr` | `---` horizontal rule |
| `listBullet` | List markers `•`, `1.` |
| `bold` | `**bold**` |
| `italic` | `*italic*` |
| `strikethrough` | `~~strikethrough~~` |
| `underline` | Underlined text |

## ImageTheme

Styles the ``Image`` component fallback:

```swift
let theme = ImageTheme(
    fallbackColor: { text in
        "\u{001B}[90m\(text)\u{001B}[0m"  // Gray fallback text
    }
)
```

| Property | Purpose |
|----------|---------|
| `fallbackColor` | Styles fallback text when images can't display |

## Theme Patterns

### Consistent Color Palette

Define colors once and reuse:

```swift
enum Colors {
    static func primary(_ text: String) -> String {
        "\u{001B}[34m\(text)\u{001B}[0m"  // Blue
    }

    static func secondary(_ text: String) -> String {
        "\u{001B}[90m\(text)\u{001B}[0m"  // Gray
    }

    static func accent(_ text: String) -> String {
        "\u{001B}[33m\(text)\u{001B}[0m"  // Yellow
    }

    static func success(_ text: String) -> String {
        "\u{001B}[32m\(text)\u{001B}[0m"  // Green
    }

    static func error(_ text: String) -> String {
        "\u{001B}[31m\(text)\u{001B}[0m"  // Red
    }
}

let selectTheme = SelectListTheme(
    selectedPrefix: { Colors.accent("> ") + $0 },
    selectedText: { "\u{001B}[1m\($0)\u{001B}[0m" },
    description: Colors.secondary,
    scrollInfo: Colors.secondary,
    noMatch: Colors.accent
)
```

### Dark Theme

```swift
let darkTheme = MarkdownTheme(
    heading: { "\u{001B}[1;38;5;75m\($0)\u{001B}[0m" },   // Light blue
    link: { "\u{001B}[38;5;39m\($0)\u{001B}[0m" },        // Cyan
    linkUrl: { "\u{001B}[38;5;245m\($0)\u{001B}[0m" },    // Gray
    code: { "\u{001B}[38;5;214m\($0)\u{001B}[0m" },       // Orange
    codeBlock: { $0 },
    codeBlockBorder: { "\u{001B}[38;5;240m\($0)\u{001B}[0m" },
    quote: { "\u{001B}[3;38;5;250m\($0)\u{001B}[0m" },
    quoteBorder: { "\u{001B}[38;5;240m\($0)\u{001B}[0m" },
    hr: { "\u{001B}[38;5;240m\($0)\u{001B}[0m" },
    listBullet: { "\u{001B}[38;5;75m\($0)\u{001B}[0m" },
    bold: { "\u{001B}[1m\($0)\u{001B}[0m" },
    italic: { "\u{001B}[3m\($0)\u{001B}[0m" },
    strikethrough: { "\u{001B}[9m\($0)\u{001B}[0m" },
    underline: { "\u{001B}[4m\($0)\u{001B}[0m" }
)
```

### No-Color Theme

For accessibility or plain output:

```swift
let plainTheme = SelectListTheme(
    selectedPrefix: { "> " + $0 },
    selectedText: { $0 },
    description: { "  \($0)" },
    scrollInfo: { $0 },
    noMatch: { $0 }
)
```

## Topics

### Theme Types

- ``EditorTheme``
- ``SelectListTheme``
- ``SettingsListTheme``
- ``MarkdownTheme``
- ``ImageTheme``
