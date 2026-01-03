import Darwin
import Foundation
import MiniTui

private final class ExitOnCtrlC: Component {
    private let terminal: Terminal

    init(terminal: Terminal) {
        self.terminal = terminal
    }

    func handleInput(_ data: String) {
        if isCtrlC(data) {
            terminal.showCursor()
            terminal.stop()
            Darwin.exit(0)
        }
    }

    func render(width: Int) -> [String] {
        return []
    }
}

@main
struct MiniTuiImageTest {
    @MainActor
    static func main() {
        let args = CommandLine.arguments
        let imagePath = args.count > 1 ? args[1] : "/tmp/test-image.png"

        let caps = getCapabilities()
        print("Terminal capabilities: images=\(caps.images?.rawValue ?? "none"), trueColor=\(caps.trueColor), hyperlinks=\(caps.hyperlinks)")
        print("Loading image from: \(imagePath)")

        let fileUrl = URL(fileURLWithPath: imagePath)
        let data: Data
        do {
            data = try Data(contentsOf: fileUrl)
        } catch {
            fputs("Failed to load image: \(imagePath)\n", stderr)
            fputs("Usage: swift run MiniTuiImageTest [path-to-image.png]\n", stderr)
            Darwin.exit(1)
        }

        let mimeType = mimeTypeForPath(fileUrl.path)
        let base64Data = data.base64EncodedString()
        let dimensions = getImageDimensions(base64Data, mimeType: mimeType)
        print("Image dimensions: \(formatDimensions(dimensions))")
        print("")

        let terminal = ProcessTerminal()
        let tui = TUI(terminal: terminal)

        tui.addChild(Text("Image Rendering Test", paddingX: 1, paddingY: 1))
        tui.addChild(Spacer(1))

        if let dimensions {
            let theme = ImageTheme { text in "\u{001B}[33m\(text)\u{001B}[0m" }
            let options = ImageOptions(maxWidthCells: 60, filename: fileUrl.lastPathComponent)
            tui.addChild(Image(base64Data: base64Data, mimeType: mimeType, theme: theme, options: options, dimensions: dimensions))
        } else {
            tui.addChild(Text("Could not parse image dimensions", paddingX: 1, paddingY: 0))
        }

        tui.addChild(Spacer(1))
        tui.addChild(Text("Press Ctrl+C to exit", paddingX: 1, paddingY: 0))

        let exitHandler = ExitOnCtrlC(terminal: terminal)
        tui.setFocus(exitHandler)
        tui.start()

        RunLoop.main.run()
    }
}

private func mimeTypeForPath(_ path: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    switch ext {
    case "jpg", "jpeg":
        return "image/jpeg"
    case "gif":
        return "image/gif"
    case "webp":
        return "image/webp"
    case "png":
        return "image/png"
    default:
        return "image/png"
    }
}

private func formatDimensions(_ dims: ImageDimensions?) -> String {
    guard let dims else { return "unknown" }
    return "\(dims.widthPx)x\(dims.heightPx)"
}
