import Foundation

// MARK: - New keybinding system (v0.61.1)

/// A keybinding identifier, e.g. "tui.editor.cursorUp".
public typealias Keybinding = String

/// Definition of a keybinding: its default keys and optional description.
public struct KeybindingDefinition: Sendable {
    public let defaultKeys: [KeyId]
    public let description: String?

    public init(defaultKeys: [KeyId], description: String? = nil) {
        self.defaultKeys = defaultKeys
        self.description = description
    }

    public init(defaultKey: KeyId, description: String? = nil) {
        self.defaultKeys = [defaultKey]
        self.description = description
    }
}

/// Conflict: multiple keybindings share the same key.
public struct KeybindingConflict: Sendable {
    public let key: KeyId
    public let keybindings: [String]
}

/// Namespaced keybinding IDs for type-safe usage.
public enum TUIKeybinding {
    // Editor navigation and editing
    public static let editorCursorUp = "tui.editor.cursorUp"
    public static let editorCursorDown = "tui.editor.cursorDown"
    public static let editorCursorLeft = "tui.editor.cursorLeft"
    public static let editorCursorRight = "tui.editor.cursorRight"
    public static let editorCursorWordLeft = "tui.editor.cursorWordLeft"
    public static let editorCursorWordRight = "tui.editor.cursorWordRight"
    public static let editorCursorLineStart = "tui.editor.cursorLineStart"
    public static let editorCursorLineEnd = "tui.editor.cursorLineEnd"
    public static let editorJumpForward = "tui.editor.jumpForward"
    public static let editorJumpBackward = "tui.editor.jumpBackward"
    public static let editorPageUp = "tui.editor.pageUp"
    public static let editorPageDown = "tui.editor.pageDown"
    public static let editorDeleteCharBackward = "tui.editor.deleteCharBackward"
    public static let editorDeleteCharForward = "tui.editor.deleteCharForward"
    public static let editorDeleteWordBackward = "tui.editor.deleteWordBackward"
    public static let editorDeleteWordForward = "tui.editor.deleteWordForward"
    public static let editorDeleteToLineStart = "tui.editor.deleteToLineStart"
    public static let editorDeleteToLineEnd = "tui.editor.deleteToLineEnd"
    public static let editorYank = "tui.editor.yank"
    public static let editorYankPop = "tui.editor.yankPop"
    public static let editorUndo = "tui.editor.undo"
    // Generic input actions
    public static let inputNewLine = "tui.input.newLine"
    public static let inputSubmit = "tui.input.submit"
    public static let inputTab = "tui.input.tab"
    public static let inputCopy = "tui.input.copy"
    // Generic selection actions
    public static let selectUp = "tui.select.up"
    public static let selectDown = "tui.select.down"
    public static let selectPageUp = "tui.select.pageUp"
    public static let selectPageDown = "tui.select.pageDown"
    public static let selectConfirm = "tui.select.confirm"
    public static let selectCancel = "tui.select.cancel"
}

/// Global TUI keybinding definitions.
public let TUI_KEYBINDINGS: [String: KeybindingDefinition] = [
    TUIKeybinding.editorCursorUp: KeybindingDefinition(defaultKey: Key.up, description: "Move cursor up"),
    TUIKeybinding.editorCursorDown: KeybindingDefinition(defaultKey: Key.down, description: "Move cursor down"),
    TUIKeybinding.editorCursorLeft: KeybindingDefinition(defaultKeys: [Key.left, Key.ctrl("b")], description: "Move cursor left"),
    TUIKeybinding.editorCursorRight: KeybindingDefinition(defaultKeys: [Key.right, Key.ctrl("f")], description: "Move cursor right"),
    TUIKeybinding.editorCursorWordLeft: KeybindingDefinition(defaultKeys: [Key.alt("left"), Key.ctrl("left"), Key.alt("b")], description: "Move cursor word left"),
    TUIKeybinding.editorCursorWordRight: KeybindingDefinition(defaultKeys: [Key.alt("right"), Key.ctrl("right"), Key.alt("f")], description: "Move cursor word right"),
    TUIKeybinding.editorCursorLineStart: KeybindingDefinition(defaultKeys: [Key.home, Key.ctrl("a")], description: "Move to line start"),
    TUIKeybinding.editorCursorLineEnd: KeybindingDefinition(defaultKeys: [Key.end, Key.ctrl("e")], description: "Move to line end"),
    TUIKeybinding.editorJumpForward: KeybindingDefinition(defaultKey: Key.ctrl("]"), description: "Jump forward to character"),
    TUIKeybinding.editorJumpBackward: KeybindingDefinition(defaultKey: Key.ctrlAlt("]"), description: "Jump backward to character"),
    TUIKeybinding.editorPageUp: KeybindingDefinition(defaultKey: Key.pageUp, description: "Page up"),
    TUIKeybinding.editorPageDown: KeybindingDefinition(defaultKey: Key.pageDown, description: "Page down"),
    TUIKeybinding.editorDeleteCharBackward: KeybindingDefinition(defaultKey: Key.backspace, description: "Delete character backward"),
    TUIKeybinding.editorDeleteCharForward: KeybindingDefinition(defaultKeys: [Key.delete, Key.ctrl("d")], description: "Delete character forward"),
    TUIKeybinding.editorDeleteWordBackward: KeybindingDefinition(defaultKeys: [Key.ctrl("w"), Key.alt("backspace")], description: "Delete word backward"),
    TUIKeybinding.editorDeleteWordForward: KeybindingDefinition(defaultKeys: [Key.alt("d"), Key.alt("delete")], description: "Delete word forward"),
    TUIKeybinding.editorDeleteToLineStart: KeybindingDefinition(defaultKey: Key.ctrl("u"), description: "Delete to line start"),
    TUIKeybinding.editorDeleteToLineEnd: KeybindingDefinition(defaultKey: Key.ctrl("k"), description: "Delete to line end"),
    TUIKeybinding.editorYank: KeybindingDefinition(defaultKey: Key.ctrl("y"), description: "Yank"),
    TUIKeybinding.editorYankPop: KeybindingDefinition(defaultKey: Key.alt("y"), description: "Yank pop"),
    TUIKeybinding.editorUndo: KeybindingDefinition(defaultKey: Key.ctrl(Key.hyphen), description: "Undo"),
    TUIKeybinding.inputNewLine: KeybindingDefinition(defaultKey: Key.shift("enter"), description: "Insert newline"),
    TUIKeybinding.inputSubmit: KeybindingDefinition(defaultKey: Key.enter, description: "Submit input"),
    TUIKeybinding.inputTab: KeybindingDefinition(defaultKey: Key.tab, description: "Tab / autocomplete"),
    TUIKeybinding.inputCopy: KeybindingDefinition(defaultKey: Key.ctrl("c"), description: "Copy selection"),
    TUIKeybinding.selectUp: KeybindingDefinition(defaultKey: Key.up, description: "Move selection up"),
    TUIKeybinding.selectDown: KeybindingDefinition(defaultKey: Key.down, description: "Move selection down"),
    TUIKeybinding.selectPageUp: KeybindingDefinition(defaultKey: Key.pageUp, description: "Selection page up"),
    TUIKeybinding.selectPageDown: KeybindingDefinition(defaultKey: Key.pageDown, description: "Selection page down"),
    TUIKeybinding.selectConfirm: KeybindingDefinition(defaultKey: Key.enter, description: "Confirm selection"),
    TUIKeybinding.selectCancel: KeybindingDefinition(defaultKeys: [Key.escape, Key.ctrl("c")], description: "Cancel selection"),
]

/// Unified keybindings manager with namespaced IDs.
public final class TUIKeybindingsManager {
    private var definitions: [String: KeybindingDefinition]
    private var userBindings: [String: [KeyId]?]
    private var keysById: [String: [KeyId]] = [:]
    private(set) var conflicts: [KeybindingConflict] = []

    public init(definitions: [String: KeybindingDefinition] = TUI_KEYBINDINGS, userBindings: [String: [KeyId]?] = [:]) {
        self.definitions = definitions
        self.userBindings = userBindings
        rebuild()
    }

    private func rebuild() {
        keysById.removeAll()
        conflicts.removeAll()

        // Detect user binding conflicts
        var userClaims: [KeyId: Set<String>] = [:]
        for (keybinding, keys) in userBindings {
            guard definitions[keybinding] != nil else { continue }
            guard let keys else { continue }
            for key in keys {
                var claimants = userClaims[key] ?? Set()
                claimants.insert(keybinding)
                userClaims[key] = claimants
            }
        }

        for (key, keybindings) in userClaims where keybindings.count > 1 {
            conflicts.append(KeybindingConflict(key: key, keybindings: Array(keybindings)))
        }

        // Resolve effective keys for each keybinding
        for (id, definition) in definitions {
            if let userKeys = userBindings[id] {
                keysById[id] = userKeys ?? []
            } else {
                keysById[id] = definition.defaultKeys
            }
        }
    }

    /// Return true when input matches the binding for a keybinding.
    public func matches(_ data: String, _ keybinding: String) -> Bool {
        guard let keys = keysById[keybinding] else { return false }
        for key in keys {
            if matchesKey(data, key) { return true }
        }
        return false
    }

    /// Return the keys bound to a keybinding.
    public func getKeys(_ keybinding: String) -> [KeyId] {
        keysById[keybinding] ?? []
    }

    /// Return the definition for a keybinding.
    public func getDefinition(_ keybinding: String) -> KeybindingDefinition? {
        definitions[keybinding]
    }

    /// Return detected conflicts.
    public func getConflicts() -> [KeybindingConflict] {
        conflicts
    }

    /// Update user bindings and rebuild.
    public func setUserBindings(_ userBindings: [String: [KeyId]?]) {
        self.userBindings = userBindings
        rebuild()
    }

    /// Add additional definitions (for downstream extension).
    public func addDefinitions(_ newDefinitions: [String: KeybindingDefinition]) {
        for (id, def) in newDefinitions {
            definitions[id] = def
        }
        rebuild()
    }

    /// Return current user bindings.
    public func getUserBindings() -> [String: [KeyId]?] {
        userBindings
    }
}

// MARK: - Global keybindings singleton

private final class LockedTUIKeybindings: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TUIKeybindingsManager

    init(_ value: TUIKeybindingsManager) {
        self.value = value
    }

    func get() -> TUIKeybindingsManager {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: TUIKeybindingsManager) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private let globalTUIKeybindings = LockedTUIKeybindings(TUIKeybindingsManager())

public func setKeybindings(_ manager: TUIKeybindingsManager) {
    globalTUIKeybindings.set(manager)
}

public func getKeybindings() -> TUIKeybindingsManager {
    globalTUIKeybindings.get()
}

// MARK: - Backward compatibility (EditorAction-based API)

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
    case pageUp
    case pageDown
    // Deletion
    case deleteCharBackward
    case deleteCharForward
    case deleteWordBackward
    case deleteWordForward
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
    case yank
    case yankPop
    // Edit
    case undo
    // Character jump
    case jumpForward
    case jumpBackward

    /// Map to the namespaced keybinding ID.
    public var keybinding: String {
        switch self {
        case .cursorUp: return TUIKeybinding.editorCursorUp
        case .cursorDown: return TUIKeybinding.editorCursorDown
        case .cursorLeft: return TUIKeybinding.editorCursorLeft
        case .cursorRight: return TUIKeybinding.editorCursorRight
        case .cursorWordLeft: return TUIKeybinding.editorCursorWordLeft
        case .cursorWordRight: return TUIKeybinding.editorCursorWordRight
        case .cursorLineStart: return TUIKeybinding.editorCursorLineStart
        case .cursorLineEnd: return TUIKeybinding.editorCursorLineEnd
        case .pageUp: return TUIKeybinding.editorPageUp
        case .pageDown: return TUIKeybinding.editorPageDown
        case .deleteCharBackward: return TUIKeybinding.editorDeleteCharBackward
        case .deleteCharForward: return TUIKeybinding.editorDeleteCharForward
        case .deleteWordBackward: return TUIKeybinding.editorDeleteWordBackward
        case .deleteWordForward: return TUIKeybinding.editorDeleteWordForward
        case .deleteToLineStart: return TUIKeybinding.editorDeleteToLineStart
        case .deleteToLineEnd: return TUIKeybinding.editorDeleteToLineEnd
        case .newLine: return TUIKeybinding.inputNewLine
        case .submit: return TUIKeybinding.inputSubmit
        case .tab: return TUIKeybinding.inputTab
        case .selectUp: return TUIKeybinding.selectUp
        case .selectDown: return TUIKeybinding.selectDown
        case .selectPageUp: return TUIKeybinding.selectPageUp
        case .selectPageDown: return TUIKeybinding.selectPageDown
        case .selectConfirm: return TUIKeybinding.selectConfirm
        case .selectCancel: return TUIKeybinding.selectCancel
        case .copy: return TUIKeybinding.inputCopy
        case .yank: return TUIKeybinding.editorYank
        case .yankPop: return TUIKeybinding.editorYankPop
        case .undo: return TUIKeybinding.editorUndo
        case .jumpForward: return TUIKeybinding.editorJumpForward
        case .jumpBackward: return TUIKeybinding.editorJumpBackward
        }
    }
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
    .cursorUp: [Key.up],
    .cursorDown: [Key.down],
    .cursorLeft: [Key.left, Key.ctrl("b")],
    .cursorRight: [Key.right, Key.ctrl("f")],
    .cursorWordLeft: [Key.alt("left"), Key.ctrl("left"), Key.alt("b")],
    .cursorWordRight: [Key.alt("right"), Key.ctrl("right"), Key.alt("f")],
    .cursorLineStart: [Key.home, Key.ctrl("a")],
    .cursorLineEnd: [Key.end, Key.ctrl("e")],
    .pageUp: [Key.pageUp],
    .pageDown: [Key.pageDown],
    .deleteCharBackward: [Key.backspace],
    .deleteCharForward: [Key.delete, Key.ctrl("d")],
    .deleteWordBackward: [Key.ctrl("w"), Key.alt("backspace")],
    .deleteWordForward: [Key.alt("d"), Key.alt("delete")],
    .deleteToLineStart: [Key.ctrl("u")],
    .deleteToLineEnd: [Key.ctrl("k")],
    .newLine: [Key.shift("enter")],
    .submit: [Key.enter],
    .tab: [Key.tab],
    .selectUp: [Key.up],
    .selectDown: [Key.down],
    .selectPageUp: [Key.pageUp],
    .selectPageDown: [Key.pageDown],
    .selectConfirm: [Key.enter],
    .selectCancel: [Key.escape, Key.ctrl("c")],
    .copy: [Key.ctrl("c")],
    .yank: [Key.ctrl("y")],
    .yankPop: [Key.alt("y")],
    .undo: [Key.ctrl(Key.hyphen)],
    .jumpForward: [Key.ctrl("]")],
    .jumpBackward: [Key.ctrlAlt("]")],
]

/// Manages keybindings for editor-related components.
/// Delegates to the global `TUIKeybindingsManager` via `EditorAction.keybinding`.
public final class EditorKeybindingsManager {
    public init(config: EditorKeybindingsConfig = EditorKeybindingsConfig()) {
        // Apply user bindings to the global TUI manager
        if !config.bindings.isEmpty {
            var userBindings = getKeybindings().getUserBindings()
            for (action, keys) in config.bindings {
                userBindings[action.keybinding] = keys
            }
            getKeybindings().setUserBindings(userBindings)
        }
    }

    /// Return true when input matches the binding for an action.
    public func matches(_ data: String, _ action: EditorAction) -> Bool {
        getKeybindings().matches(data, action.keybinding)
    }

    /// Return the keys bound to an action.
    public func getKeys(_ action: EditorAction) -> [KeyId] {
        getKeybindings().getKeys(action.keybinding)
    }

    /// Update configuration.
    public func setConfig(_ config: EditorKeybindingsConfig) {
        var userBindings: [String: [KeyId]?] = [:]
        for (action, keys) in config.bindings {
            userBindings[action.keybinding] = keys
        }
        getKeybindings().setUserBindings(userBindings)
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
