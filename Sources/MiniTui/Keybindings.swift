import Foundation

/// Editor actions that can be bound to keys.
public enum EditorAction: String, Sendable {
    // Cursor movement
    case cursorUp
    case cursorDown
    case cursorLeft
    case cursorRight
    case cursorWordLeft
    case cursorWordRight
    case cursorLineStart
    case cursorLineEnd
    // Deletion
    case deleteCharBackward
    case deleteCharForward
    case deleteWordBackward
    case deleteToLineStart
    case deleteToLineEnd
    // Text input
    case newLine
    case submit
    case tab
    // Selection/autocomplete
    case selectUp
    case selectDown
    case selectPageUp
    case selectPageDown
    case selectConfirm
    case selectCancel
    // Clipboard
    case copy
}

/// Editor keybindings configuration.
public struct EditorKeybindingsConfig: Sendable {
    public var bindings: [EditorAction: [KeyId]]

    public init(_ bindings: [EditorAction: [KeyId]] = [:]) {
        self.bindings = bindings
    }

    public init(_ bindings: [EditorAction: KeyId]) {
        var expanded: [EditorAction: [KeyId]] = [:]
        for (action, key) in bindings {
            expanded[action] = [key]
        }
        self.bindings = expanded
    }
}

/// Default editor keybindings.
public let DEFAULT_EDITOR_KEYBINDINGS: [EditorAction: [KeyId]] = [
    // Cursor movement
    .cursorUp: [Key.up],
    .cursorDown: [Key.down],
    .cursorLeft: [Key.left],
    .cursorRight: [Key.right],
    .cursorWordLeft: [Key.alt("left"), Key.ctrl("left")],
    .cursorWordRight: [Key.alt("right"), Key.ctrl("right")],
    .cursorLineStart: [Key.home, Key.ctrl("a")],
    .cursorLineEnd: [Key.end, Key.ctrl("e")],
    // Deletion
    .deleteCharBackward: [Key.backspace],
    .deleteCharForward: [Key.delete],
    .deleteWordBackward: [Key.ctrl("w"), Key.alt("backspace")],
    .deleteToLineStart: [Key.ctrl("u")],
    .deleteToLineEnd: [Key.ctrl("k")],
    // Text input
    .newLine: [Key.shift("enter")],
    .submit: [Key.enter],
    .tab: [Key.tab],
    // Selection/autocomplete
    .selectUp: [Key.up],
    .selectDown: [Key.down],
    .selectPageUp: [Key.pageUp],
    .selectPageDown: [Key.pageDown],
    .selectConfirm: [Key.enter],
    .selectCancel: [Key.escape, Key.ctrl("c")],
    // Clipboard
    .copy: [Key.ctrl("c")],
]

/// Manages keybindings for editor-related components.
public final class EditorKeybindingsManager {
    private var actionToKeys: [EditorAction: [KeyId]] = [:]

    public init(config: EditorKeybindingsConfig = EditorKeybindingsConfig()) {
        buildMaps(config: config)
    }

    private func buildMaps(config: EditorKeybindingsConfig) {
        actionToKeys = DEFAULT_EDITOR_KEYBINDINGS
        for (action, keys) in config.bindings {
            actionToKeys[action] = keys
        }
    }

    /// Return true when input matches the binding for an action.
    public func matches(_ data: String, _ action: EditorAction) -> Bool {
        guard let keys = actionToKeys[action] else { return false }
        for key in keys {
            if matchesKey(data, key) { return true }
        }
        return false
    }

    /// Return the keys bound to an action.
    public func getKeys(_ action: EditorAction) -> [KeyId] {
        return actionToKeys[action] ?? []
    }

    /// Update configuration.
    public func setConfig(_ config: EditorKeybindingsConfig) {
        buildMaps(config: config)
    }
}

private final class LockedKeybindings: @unchecked Sendable {
    private let lock = NSLock()
    private var value: EditorKeybindingsManager

    init(_ value: EditorKeybindingsManager) {
        self.value = value
    }

    func get() -> EditorKeybindingsManager {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: EditorKeybindingsManager) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private let globalEditorKeybindings = LockedKeybindings(EditorKeybindingsManager())

public func setEditorKeybindings(_ manager: EditorKeybindingsManager) {
    globalEditorKeybindings.set(manager)
}

public func getEditorKeybindings() -> EditorKeybindingsManager {
    return globalEditorKeybindings.get()
}
