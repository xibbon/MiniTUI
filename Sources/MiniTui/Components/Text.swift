import Foundation

/// Text component with optional padding and background styling.
public class Text: Component {
    private var text: String
    private let paddingX: Int
    private let paddingY: Int
    private var customBgFn: ((String) -> String)?

    private var cachedText: String?
    private var cachedWidth: Int?
    private var cachedLines: [String]?

    /// Create a text component.
    public init(_ text: String = "", paddingX: Int = 1, paddingY: Int = 1, customBgFn: ((String) -> String)? = nil) {
        self.text = text
        self.paddingX = paddingX
        self.paddingY = paddingY
        self.customBgFn = customBgFn
    }

    /// Update the text content and invalidate cached lines.
    public func setText(_ text: String) {
        self.text = text
        invalidate()
    }

    /// Update the optional background formatter and invalidate cached lines.
    public func setCustomBgFn(_ customBgFn: ((String) -> String)?) {
        self.customBgFn = customBgFn
        invalidate()
    }

    /// Clear cached render state.
    public func invalidate() {
        cachedText = nil
        cachedWidth = nil
        cachedLines = nil
    }

    /// Text does not handle input by default.
    public func handleInput(_ data: String) {}

    /// Render the text with padding and background styling.
    public func render(width: Int) -> [String] {
        if let cachedLines, cachedText == text, cachedWidth == width {
            return cachedLines
        }

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let result: [String] = []
            cachedText = text
            cachedWidth = width
            cachedLines = result
            return result
        }

        let normalizedText = text.replacingOccurrences(of: "\t", with: "   ")
        let contentWidth = max(1, width - paddingX * 2)
        let wrappedLines = wrapTextWithAnsi(normalizedText, width: contentWidth)

        let leftMargin = String(repeating: " ", count: paddingX)
        let rightMargin = String(repeating: " ", count: paddingX)
        var contentLines: [String] = []

        for line in wrappedLines {
            let lineWithMargins = leftMargin + line + rightMargin
            if let bgFn = customBgFn {
                contentLines.append(applyBackgroundToLine(lineWithMargins, width: width, bgFn: bgFn))
            } else {
                let visibleLen = visibleWidth(lineWithMargins)
                let paddingNeeded = max(0, width - visibleLen)
                contentLines.append(lineWithMargins + String(repeating: " ", count: paddingNeeded))
            }
        }

        let emptyLine = String(repeating: " ", count: width)
        var emptyLines: [String] = []
        for _ in 0..<paddingY {
            let line = customBgFn.map { applyBackgroundToLine(emptyLine, width: width, bgFn: $0) } ?? emptyLine
            emptyLines.append(line)
        }

        let result = emptyLines + contentLines + emptyLines
        cachedText = text
        cachedWidth = width
        cachedLines = result

        return result.isEmpty ? [""] : result
    }
}
