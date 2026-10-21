import Foundation

let systemCursorMarker = "\u{0000}"

public protocol SystemCursorAware: Component {
    var usesSystemCursor: Bool { get set }
}

let fakeCursorStart = "\u{1b}_pi:fc\u{07}"
let fakeCursorEnd = "\u{1b}_pi:/fc\u{07}"

/// Wrap the text that a component draws as its cursor.
public func renderFakeCursor(_ text: String) -> String {
    fakeCursorStart + text + fakeCursorEnd
}

/// Resolve cursor markers before styles or overlays are applied.
func resolveFakeCursors(_ lines: [String], useSystemCursor: Bool) -> [String] {
    lines.map { line in
        guard line.contains(fakeCursorStart) else { return line }
        var resolved = line
        if useSystemCursor,
           let start = resolved.range(of: systemCursorMarker + fakeCursorStart) {
            let textStart = start.upperBound
            let end = resolved.range(of: fakeCursorEnd, range: textStart..<resolved.endIndex)
            let textEnd = end?.lowerBound ?? resolved.endIndex
            let text = String(resolved[textStart..<textEnd])
            resolved.replaceSubrange(start.lowerBound..<(end?.upperBound ?? resolved.endIndex),
                                     with: systemCursorMarker + text)
        }
        return resolved.replacingOccurrences(of: fakeCursorStart, with: "\u{1b}[7m")
            .replacingOccurrences(of: fakeCursorEnd, with: "\u{1b}[27m")
    }
}
