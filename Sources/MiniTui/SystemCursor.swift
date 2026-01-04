import Foundation

let systemCursorMarker = "\u{0000}"

public protocol SystemCursorAware: Component {
    var usesSystemCursor: Bool { get set }
}
