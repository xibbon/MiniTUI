import Foundation

/// Vertical spacer that renders blank lines.
public final class Spacer: Component {
    private var lines: Int

    /// Create a spacer with a number of empty lines.
    public init(_ lines: Int = 1) {
        self.lines = lines
    }

    /// Update the number of empty lines.
    public func setLines(_ lines: Int) {
        self.lines = lines
    }

    /// Render the requested number of empty lines.
    public func render(width: Int) -> [String] {
        return Array(repeating: "", count: max(0, lines))
    }
}
