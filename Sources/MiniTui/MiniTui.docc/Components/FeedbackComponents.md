# Feedback Components

Display progress indicators and visual content to users.

@Metadata {
    @PageKind(article)
    @PageColor(green)
}

## Overview

MiniTui provides components for giving users feedback during operations: ``Loader`` for animated spinners, ``CancellableLoader`` for interruptible operations, and ``Image`` for displaying visual content.

## Loader

``Loader`` displays an animated spinner with a customizable message.

### Basic Usage

```swift
let loader = Loader(
    ui: tui,
    spinnerColorFn: { $0 },
    messageColorFn: { $0 },
    message: "Loading..."
)

tui.addChild(loader)
```

The loader automatically animates by requesting renders on a timer.

### Theming

```swift
let loader = Loader(
    ui: tui,
    spinnerColorFn: { "\u{001B}[36m\($0)\u{001B}[0m" },  // Cyan spinner
    messageColorFn: { "\u{001B}[90m\($0)\u{001B}[0m" },  // Gray message
    message: "Processing..."
)
```

### Updating the Message

```swift
loader.setMessage("Processing file 1 of 10...")
loader.setMessage("Processing file 2 of 10...")
```

### Stopping the Loader

```swift
loader.stop()
tui.removeChild(loader)
tui.requestRender()
```

Always stop the loader when the operation completes to prevent unnecessary render cycles.

### Usage Pattern

```swift
func performLongOperation() async {
    // Show loader
    let loader = Loader(ui: tui, ..., message: "Working...")
    tui.addChild(loader)
    tui.requestRender()

    // Do work
    await Task {
        for i in 1...10 {
            await processItem(i)
            Task { @MainActor in
                loader.setMessage("Processing \(i) of 10...")
            }
        }
    }.value

    // Remove loader
    Task { @MainActor in
        loader.stop()
        tui.removeChild(loader)
        tui.addChild(Text("Done!"))
        tui.requestRender()
    }
}
```

## CancellableLoader

``CancellableLoader`` extends ``Loader`` with cancellation support via the Escape key.

### Basic Usage

```swift
let loader = CancellableLoader(
    ui: tui,
    spinnerColorFn: { $0 },
    messageColorFn: { $0 },
    message: "Downloading..."
)

loader.onAbort = {
    print("User cancelled the operation")
}

tui.addChild(loader)
tui.setFocus(loader)  // Required to receive Escape key
```

### Cancellation Signal

Access the cancellation signal for cooperative cancellation:

```swift
let loader = CancellableLoader(ui: tui, message: "Fetching data...")

loader.signal.onCancel {
    print("Cancellation requested")
}

// Pass signal to async operations
Task {
    await fetchData(signal: loader.signal)
}
```

Check cancellation status:

```swift
if loader.signal.isCancelled {
    return  // Stop operation
}
```

### Complete Example

```swift
func downloadFile(url: URL) async {
    let loader = CancellableLoader(
        ui: tui,
        spinnerColorFn: { "\u{001B}[33m\($0)\u{001B}[0m" },
        messageColorFn: { $0 },
        message: "Downloading \(url.lastPathComponent)..."
    )

    var cancelled = false
    loader.onAbort = { cancelled = true }

    tui.addChild(loader)
    tui.setFocus(loader)
    tui.requestRender()

    // Simulate download with cancellation check
    for progress in stride(from: 0, to: 100, by: 10) {
        if cancelled {
            break
        }
        loader.setMessage("Downloading... \(progress)%")
        try? await Task.sleep(nanoseconds: 500_000_000)
    }

    Task { @MainActor in
        loader.stop()
        tui.removeChild(loader)
        tui.addChild(Text(cancelled ? "Download cancelled" : "Download complete"))
        tui.requestRender()
    }
}
```

## Image

``Image`` displays inline images in terminals that support the Kitty or iTerm2 graphics protocols.

### Basic Usage

```swift
let imageData = try! Data(contentsOf: URL(fileURLWithPath: "photo.png"))
let base64 = imageData.base64EncodedString()

let image = Image(
    base64Data: base64,
    mimeType: "image/png",
    theme: ImageTheme(fallbackColor: { $0 }),
    options: ImageOptions()
)

tui.addChild(image)
```

### Supported Formats

- PNG (`image/png`)
- JPEG (`image/jpeg`)
- GIF (`image/gif`)
- WebP (`image/webp`)

### Image Options

```swift
let options = ImageOptions(
    maxWidthCells: 40,      // Maximum width in terminal cells
    maxHeightCells: 20,     // Maximum height in terminal cells
    filename: "photo.png"   // Optional filename for display
)
```

### Theming

```swift
let theme = ImageTheme(
    fallbackColor: { "\u{001B}[90m\($0)\u{001B}[0m" }  // Gray fallback text
)
```

### Fallback Behavior

When the terminal doesn't support image protocols, a fallback message is displayed:

```
[Image: photo.png]
```

### Terminal Support

| Terminal | Protocol | Support |
|----------|----------|---------|
| Kitty | Kitty | Full |
| iTerm2 | iTerm2 | Full |
| WezTerm | Kitty | Full |
| Ghostty | Kitty | Full |
| Terminal.app | - | Fallback only |
| VS Code | - | Fallback only |

### Detecting Capabilities

```swift
let caps = getCapabilities()

if let imageProtocol = caps.images {
    switch imageProtocol {
    case .kitty:
        print("Kitty graphics supported")
    case .iterm2:
        print("iTerm2 graphics supported")
    }
} else {
    print("No image support - will show fallback")
}
```

### Sizing Images

Images are automatically sized based on:
1. The `maxWidthCells` and `maxHeightCells` options
2. The terminal's cell dimensions (queried automatically)
3. The image's aspect ratio (preserved)

```swift
// Calculate how many rows an image will occupy
let rows = calculateImageRows(
    imageWidth: 800,
    imageHeight: 600,
    maxWidthCells: 40,
    maxHeightCells: nil
)
```

## Common Patterns

### Loading State Management

```swift
enum LoadingState {
    case idle
    case loading(Loader)
    case error(String)
    case success
}

var state: LoadingState = .idle

func startLoading() {
    let loader = Loader(ui: tui, ..., message: "Loading...")
    state = .loading(loader)
    tui.addChild(loader)
    tui.requestRender()
}

func finishLoading(error: String? = nil) {
    if case .loading(let loader) = state {
        loader.stop()
        tui.removeChild(loader)
    }

    if let error {
        state = .error(error)
        tui.addChild(Text("Error: \(error)"))
    } else {
        state = .success
        tui.addChild(Text("Complete!"))
    }
    tui.requestRender()
}
```

### Image Gallery

```swift
func showImageGallery(images: [URL]) {
    let container = Container()

    for url in images {
        if let data = try? Data(contentsOf: url) {
            let image = Image(
                base64Data: data.base64EncodedString(),
                mimeType: mimeType(for: url),
                theme: imageTheme,
                options: ImageOptions(maxWidthCells: 30, filename: url.lastPathComponent)
            )
            container.addChild(image)
            container.addChild(Spacer(1))
        }
    }

    tui.showOverlay(container, options: OverlayOptions(
        width: .percent(80),
        maxHeight: .percent(80),
        anchor: .center
    ))
}
```

## Topics

### Components

- ``Loader``
- ``CancellableLoader``
- ``Image``

### Configuration

- ``ImageTheme``
- ``ImageOptions``

### Utilities

- ``getCapabilities()``
- ``calculateImageRows(imageWidth:imageHeight:maxWidthCells:maxHeightCells:)``
