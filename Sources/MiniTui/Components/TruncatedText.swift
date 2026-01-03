import Foundation

/// Single-line text that truncates to fit the available width.
public final class TruncatedText: Component {
    private var text: String
    private let paddingX: Int
    private let paddingY: Int

    /// Create a truncated text component.
    public init(_ text: String, paddingX: Int = 0, paddingY: Int = 0) {
        self.text = text
        self.paddingX = paddingX
        self.paddingY = paddingY
    }

    /// Render the first line of text with truncation and padding.
    public func render(width: Int) -> [String] {
        var result: [String] = []
        let emptyLine = String(repeating: " ", count: width)

        for _ in 0..<paddingY {
            result.append(emptyLine)
        }

        let availableWidth = max(1, width - paddingX * 2)
        let singleLineText: String
        if let newlineRange = text.range(of: "\n") {
            singleLineText = String(text[..<newlineRange.lowerBound])
        } else {
            singleLineText = text
        }

        let displayText = truncateToWidth(singleLineText, maxWidth: availableWidth)
        let leftPadding = String(repeating: " ", count: paddingX)
        let rightPadding = String(repeating: " ", count: paddingX)
        let lineWithPadding = leftPadding + displayText + rightPadding
        let lineVisibleWidth = visibleWidth(lineWithPadding)
        let paddingNeeded = max(0, width - lineVisibleWidth)
        let finalLine = lineWithPadding + String(repeating: " ", count: paddingNeeded)

        result.append(finalLine)

        for _ in 0..<paddingY {
            result.append(emptyLine)
        }

        return result
    }
}
