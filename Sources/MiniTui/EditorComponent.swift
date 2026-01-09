import Foundation

/// Interface for custom editor components.
public protocol EditorComponent: Component {
    /// Return the current text content.
    func getText() -> String
    /// Set the editor text content.
    func setText(_ text: String)

    /// Called when user submits (e.g., Enter key).
    var onSubmit: ((String) -> Void)? { get set }
    /// Called when text changes.
    var onChange: ((String) -> Void)? { get set }

    /// Add text to history for up/down navigation.
    func addToHistory(_ text: String)
    /// Insert text at the current cursor position.
    func insertTextAtCursor(_ text: String)
    /// Get text with any markers expanded (e.g., paste markers).
    func getExpandedText() -> String
    /// Set the autocomplete provider.
    func setAutocompleteProvider(_ provider: AutocompleteProvider)

    /// Border color function.
    var borderColor: @Sendable (String) -> String { get }
}

public extension EditorComponent {
    var onSubmit: ((String) -> Void)? {
        get { nil }
        set {}
    }

    var onChange: ((String) -> Void)? {
        get { nil }
        set {}
    }

    func addToHistory(_ text: String) {}

    func insertTextAtCursor(_ text: String) {}

    func getExpandedText() -> String {
        return getText()
    }

    func setAutocompleteProvider(_ provider: AutocompleteProvider) {}

    var borderColor: @Sendable (String) -> String {
        { $0 }
    }
}
