# Text Display Components

Display static and dynamic text content in your terminal interface.

@Metadata {
    @PageKind(article)
    @PageColor(green)
}

## Overview

MiniTui provides three components for displaying text: ``Text`` for wrapped multi-line content, ``TruncatedText`` for single-line status displays, and ``Markdown`` for rich formatted content.

## Text

The ``Text`` component displays text with automatic word wrapping and configurable padding.

### Basic Usage

```swift
let message = Text("Hello, World!")
tui.addChild(message)
```

### With Padding

```swift
let padded = Text("Padded content", paddingX: 2, paddingY: 1)
```

- `paddingX`: Horizontal padding (spaces on left and right)
- `paddingY`: Vertical padding (empty lines above and below)

### Updating Content

```swift
message.setText("New content")
tui.requestRender()
```

### Background Styling

Apply a background style function for the entire text area:

```swift
let styled = Text("Highlighted", paddingX: 1, paddingY: 0)
styled.setCustomBgFn { line in
    "\u{001B}[44m\(line)\u{001B}[0m"  // Blue background
}
```

The background function receives each line and should return the styled line.

### Multi-line Content

Text automatically wraps at word boundaries:

```swift
let paragraph = Text("""
    This is a long paragraph that will automatically wrap
    to fit within the terminal width. Word boundaries are
    respected for readability.
    """, paddingX: 1, paddingY: 1)
```

## TruncatedText

``TruncatedText`` displays a single line that truncates with an ellipsis when too long.

### Basic Usage

```swift
let status = TruncatedText("Current status: Processing file.txt")
```

### With Padding

```swift
let header = TruncatedText("Application Title", paddingX: 1, paddingY: 0)
```

### Truncation Behavior

When content exceeds the available width:
- The text is truncated
- An ellipsis (...) is appended
- ANSI codes are properly handled

```swift
// If terminal is 20 chars wide:
// "Very long status message" becomes "Very long status..."
```

### Use Cases

- Status bars
- Headers and titles
- Single-line notifications
- File paths

## Markdown

``Markdown`` renders Markdown content with syntax support for common elements.

### Basic Usage

```swift
let content = Markdown("""
    # Welcome

    This is **bold** and this is *italic*.

    - List item 1
    - List item 2
    """)
```

### Supported Syntax

- **Headings**: `# H1`, `## H2`, etc.
- **Emphasis**: `**bold**`, `*italic*`, `~~strikethrough~~`
- **Code**: `` `inline` `` and fenced code blocks
- **Lists**: Unordered (`-`, `*`) and ordered (`1.`)
- **Links**: `[text](url)`
- **Block quotes**: `> quoted text`
- **Horizontal rules**: `---`

### Theming

Customize Markdown rendering with ``MarkdownTheme``:

```swift
let theme = MarkdownTheme(
    heading: { "\u{001B}[1;34m\($0)\u{001B}[0m" },      // Bold blue headings
    link: { "\u{001B}[4m\($0)\u{001B}[0m" },            // Underlined links
    linkUrl: { "\u{001B}[90m\($0)\u{001B}[0m" },        // Gray URLs
    code: { "\u{001B}[33m\($0)\u{001B}[0m" },           // Yellow inline code
    codeBlock: { $0 },                                   // Code block content
    codeBlockBorder: { "\u{001B}[90m\($0)\u{001B}[0m" }, // Gray borders
    quote: { "\u{001B}[3m\($0)\u{001B}[0m" },           // Italic quotes
    quoteBorder: { "\u{001B}[90m\($0)\u{001B}[0m" },    // Gray quote border
    hr: { "\u{001B}[90m\($0)\u{001B}[0m" },             // Gray horizontal rule
    listBullet: { "\u{001B}[34m\($0)\u{001B}[0m" },     // Blue bullets
    bold: { "\u{001B}[1m\($0)\u{001B}[0m" },            // Bold
    italic: { "\u{001B}[3m\($0)\u{001B}[0m" },          // Italic
    strikethrough: { "\u{001B}[9m\($0)\u{001B}[0m" },   // Strikethrough
    underline: { "\u{001B}[4m\($0)\u{001B}[0m" }        // Underline
)

let md = Markdown(content, paddingX: 1, paddingY: 1, theme: theme)
```

### Updating Content

```swift
md.setText("# Updated\n\nNew markdown content.")
tui.requestRender()
```

### Code Syntax Highlighting

Fenced code blocks support language hints:

~~~markdown
```swift
let greeting = "Hello"
print(greeting)
```
~~~

## Choosing the Right Component

| Need | Component | Why |
|------|-----------|-----|
| Multi-line text | ``Text`` | Handles wrapping automatically |
| Status line | ``TruncatedText`` | Truncates gracefully |
| Rich content | ``Markdown`` | Full formatting support |
| Long path display | ``TruncatedText`` | Shows beginning with ellipsis |
| Documentation | ``Markdown`` | Headings, lists, code blocks |

## Topics

### Components

- ``Text``
- ``TruncatedText``
- ``Markdown``

### Theming

- ``MarkdownTheme``
