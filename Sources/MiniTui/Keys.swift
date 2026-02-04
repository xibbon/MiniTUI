import Foundation

public typealias KeyId = String

private final class LockedBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private let kittyProtocolState = LockedBool(false)

/// Set whether Kitty keyboard protocol is active.
public func setKittyProtocolActive(_ active: Bool) {
    kittyProtocolState.set(active)
}

/// Return true when Kitty keyboard protocol is active.
public func isKittyProtocolActive() -> Bool {
    return kittyProtocolState.get()
}

/// Helper for building key identifiers with autocomplete.
public enum Key {
    // Special keys
    public static let escape: KeyId = "escape"
    public static let esc: KeyId = "esc"
    public static let enter: KeyId = "enter"
    public static let `return`: KeyId = "return"
    public static let tab: KeyId = "tab"
    public static let space: KeyId = "space"
    public static let backspace: KeyId = "backspace"
    public static let delete: KeyId = "delete"
    public static let home: KeyId = "home"
    public static let end: KeyId = "end"
    public static let pageUp: KeyId = "pageUp"
    public static let pageDown: KeyId = "pageDown"
    public static let up: KeyId = "up"
    public static let down: KeyId = "down"
    public static let left: KeyId = "left"
    public static let right: KeyId = "right"

    // Symbol keys
    public static let backtick: KeyId = "`"
    public static let hyphen: KeyId = "-"
    public static let equals: KeyId = "="
    public static let leftbracket: KeyId = "["
    public static let rightbracket: KeyId = "]"
    public static let backslash: KeyId = "\\"
    public static let semicolon: KeyId = ";"
    public static let quote: KeyId = "'"
    public static let comma: KeyId = ","
    public static let period: KeyId = "."
    public static let slash: KeyId = "/"
    public static let exclamation: KeyId = "!"
    public static let at: KeyId = "@"
    public static let hash: KeyId = "#"
    public static let dollar: KeyId = "$"
    public static let percent: KeyId = "%"
    public static let caret: KeyId = "^"
    public static let ampersand: KeyId = "&"
    public static let asterisk: KeyId = "*"
    public static let leftparen: KeyId = "("
    public static let rightparen: KeyId = ")"
    public static let underscore: KeyId = "_"
    public static let plus: KeyId = "+"
    public static let pipe: KeyId = "|"
    public static let tilde: KeyId = "~"
    public static let leftbrace: KeyId = "{"
    public static let rightbrace: KeyId = "}"
    public static let colon: KeyId = ":"
    public static let lessthan: KeyId = "<"
    public static let greaterthan: KeyId = ">"
    public static let question: KeyId = "?"

    // Single modifiers
    public static func ctrl(_ key: KeyId) -> KeyId { "ctrl+\(key)" }
    public static func shift(_ key: KeyId) -> KeyId { "shift+\(key)" }
    public static func alt(_ key: KeyId) -> KeyId { "alt+\(key)" }

    // Combined modifiers
    public static func ctrlShift(_ key: KeyId) -> KeyId { "ctrl+shift+\(key)" }
    public static func shiftCtrl(_ key: KeyId) -> KeyId { "shift+ctrl+\(key)" }
    public static func ctrlAlt(_ key: KeyId) -> KeyId { "ctrl+alt+\(key)" }
    public static func altCtrl(_ key: KeyId) -> KeyId { "alt+ctrl+\(key)" }
    public static func shiftAlt(_ key: KeyId) -> KeyId { "shift+alt+\(key)" }
    public static func altShift(_ key: KeyId) -> KeyId { "alt+shift+\(key)" }

    // Triple modifiers
    public static func ctrlShiftAlt(_ key: KeyId) -> KeyId { "ctrl+shift+alt+\(key)" }
}

private let symbolKeys: Set<String> = [
    "`",
    "-",
    "=",
    "[",
    "]",
    "\\",
    ";",
    "'",
    ",",
    ".",
    "/",
    "!",
    "@",
    "#",
    "$",
    "%",
    "^",
    "&",
    "*",
    "(",
    ")",
    "_",
    "+",
    "|",
    "~",
    "{",
    "}",
    ":",
    "<",
    ">",
    "?",
]

// Legacy key sequences for various terminals
private let legacyKeySequences: [String: [String]] = [
    "up": ["\u{001B}[A", "\u{001B}OA"],
    "down": ["\u{001B}[B", "\u{001B}OB"],
    "right": ["\u{001B}[C", "\u{001B}OC"],
    "left": ["\u{001B}[D", "\u{001B}OD"],
    "home": ["\u{001B}[H", "\u{001B}OH", "\u{001B}[1~", "\u{001B}[7~"],
    "end": ["\u{001B}[F", "\u{001B}OF", "\u{001B}[4~", "\u{001B}[8~"],
    "insert": ["\u{001B}[2~"],
    "delete": ["\u{001B}[3~"],
    "pageUp": ["\u{001B}[5~", "\u{001B}[[5~"],
    "pageDown": ["\u{001B}[6~", "\u{001B}[[6~"],
    "clear": ["\u{001B}[E", "\u{001B}OE"],
    "f1": ["\u{001B}OP", "\u{001B}[11~", "\u{001B}[[A"],
    "f2": ["\u{001B}OQ", "\u{001B}[12~", "\u{001B}[[B"],
    "f3": ["\u{001B}OR", "\u{001B}[13~", "\u{001B}[[C"],
    "f4": ["\u{001B}OS", "\u{001B}[14~", "\u{001B}[[D"],
    "f5": ["\u{001B}[15~", "\u{001B}[[E"],
    "f6": ["\u{001B}[17~"],
    "f7": ["\u{001B}[18~"],
    "f8": ["\u{001B}[19~"],
    "f9": ["\u{001B}[20~"],
    "f10": ["\u{001B}[21~"],
    "f11": ["\u{001B}[23~"],
    "f12": ["\u{001B}[24~"],
]

// rxvt-style shift modifier sequences
private let legacyShiftSequences: [String: [String]] = [
    "up": ["\u{001B}[a"],
    "down": ["\u{001B}[b"],
    "right": ["\u{001B}[c"],
    "left": ["\u{001B}[d"],
    "clear": ["\u{001B}[e"],
    "insert": ["\u{001B}[2$"],
    "delete": ["\u{001B}[3$"],
    "pageUp": ["\u{001B}[5$"],
    "pageDown": ["\u{001B}[6$"],
    "home": ["\u{001B}[7$"],
    "end": ["\u{001B}[8$"],
]

// rxvt-style ctrl modifier sequences
private let legacyCtrlSequences: [String: [String]] = [
    "up": ["\u{001B}Oa"],
    "down": ["\u{001B}Ob"],
    "right": ["\u{001B}Oc"],
    "left": ["\u{001B}Od"],
    "clear": ["\u{001B}Oe"],
    "insert": ["\u{001B}[2^"],
    "delete": ["\u{001B}[3^"],
    "pageUp": ["\u{001B}[5^"],
    "pageDown": ["\u{001B}[6^"],
    "home": ["\u{001B}[7^"],
    "end": ["\u{001B}[8^"],
]

// Lookup table for legacy sequences to key identifiers
private let legacySequenceKeyIds: [String: String] = [
    "\u{001B}OA": "up",
    "\u{001B}OB": "down",
    "\u{001B}OC": "right",
    "\u{001B}OD": "left",
    "\u{001B}OH": "home",
    "\u{001B}OF": "end",
    "\u{001B}[E": "clear",
    "\u{001B}OE": "clear",
    "\u{001B}Oe": "ctrl+clear",
    "\u{001B}[e": "shift+clear",
    "\u{001B}[2~": "insert",
    "\u{001B}[2$": "shift+insert",
    "\u{001B}[2^": "ctrl+insert",
    "\u{001B}[3$": "shift+delete",
    "\u{001B}[3^": "ctrl+delete",
    "\u{001B}[[5~": "pageUp",
    "\u{001B}[[6~": "pageDown",
    "\u{001B}[a": "shift+up",
    "\u{001B}[b": "shift+down",
    "\u{001B}[c": "shift+right",
    "\u{001B}[d": "shift+left",
    "\u{001B}Oa": "ctrl+up",
    "\u{001B}Ob": "ctrl+down",
    "\u{001B}Oc": "ctrl+right",
    "\u{001B}Od": "ctrl+left",
    "\u{001B}[5$": "shift+pageUp",
    "\u{001B}[6$": "shift+pageDown",
    "\u{001B}[7$": "shift+home",
    "\u{001B}[8$": "shift+end",
    "\u{001B}[5^": "ctrl+pageUp",
    "\u{001B}[6^": "ctrl+pageDown",
    "\u{001B}[7^": "ctrl+home",
    "\u{001B}[8^": "ctrl+end",
    "\u{001B}OP": "f1",
    "\u{001B}OQ": "f2",
    "\u{001B}OR": "f3",
    "\u{001B}OS": "f4",
    "\u{001B}[11~": "f1",
    "\u{001B}[12~": "f2",
    "\u{001B}[13~": "f3",
    "\u{001B}[14~": "f4",
    "\u{001B}[[A": "f1",
    "\u{001B}[[B": "f2",
    "\u{001B}[[C": "f3",
    "\u{001B}[[D": "f4",
    "\u{001B}[[E": "f5",
    "\u{001B}[15~": "f5",
    "\u{001B}[17~": "f6",
    "\u{001B}[18~": "f7",
    "\u{001B}[19~": "f8",
    "\u{001B}[20~": "f9",
    "\u{001B}[21~": "f10",
    "\u{001B}[23~": "f11",
    "\u{001B}[24~": "f12",
    "\u{001B}b": "alt+left",
    "\u{001B}f": "alt+right",
    "\u{001B}p": "alt+up",
    "\u{001B}n": "alt+down",
]

private func matchesLegacySequence(_ data: String, _ sequences: [String]) -> Bool {
    return sequences.contains(data)
}

private func matchesLegacyModifierSequence(_ data: String, _ key: String, _ modifier: Int) -> Bool {
    if modifier == Modifiers.shift {
        if let sequences = legacyShiftSequences[key] {
            return matchesLegacySequence(data, sequences)
        }
    }
    if modifier == Modifiers.ctrl {
        if let sequences = legacyCtrlSequences[key] {
            return matchesLegacySequence(data, sequences)
        }
    }
    return false
}

private enum Modifiers {
    static let shift = 1
    static let alt = 2
    static let ctrl = 4
}

private let lockMask = 64 + 128

private enum Codepoints {
    static let escape = 27
    static let tab = 9
    static let enter = 13
    static let space = 32
    static let backspace = 127
    static let kpEnter = 57414
}

private enum ArrowCodepoints {
    static let up = -1
    static let down = -2
    static let right = -3
    static let left = -4
}

private enum FunctionalCodepoints {
    static let delete = -10
    static let insert = -11
    static let pageUp = -12
    static let pageDown = -13
    static let home = -14
    static let end = -15
}

public enum KeyEventType: String, Sendable {
    case press
    case `repeat`
    case release
}

private struct ParsedKittySequence {
    let codepoint: Int
    let shiftedKey: Int?
    let baseLayoutKey: Int?
    let modifier: Int
}

/// Return true when the Kitty key event is a key release.
public func isKeyRelease(_ data: String) -> Bool {
    if data.contains("\u{001B}[200~") {
        return false
    }
    if data.contains(":3u") || data.contains(":3~") || data.contains(":3A") || data.contains(":3B") {
        return true
    }
    if data.contains(":3C") || data.contains(":3D") || data.contains(":3H") || data.contains(":3F") {
        return true
    }
    return false
}

/// Return true when the Kitty key event is a key repeat.
public func isKeyRepeat(_ data: String) -> Bool {
    if data.contains("\u{001B}[200~") {
        return false
    }
    if data.contains(":2u") || data.contains(":2~") || data.contains(":2A") || data.contains(":2B") {
        return true
    }
    if data.contains(":2C") || data.contains(":2D") || data.contains(":2H") || data.contains(":2F") {
        return true
    }
    return false
}

private func parseKittySequence(_ data: String) -> ParsedKittySequence? {
    // CSI u format with alternate keys (flag 4):
    // \x1b[<codepoint>u
    // \x1b[<codepoint>;<mod>u
    // \x1b[<codepoint>;<mod>:<event>u
    // \x1b[<codepoint>:<shifted>;<mod>u
    // \x1b[<codepoint>:<shifted>:<base>;<mod>u
    // \x1b[<codepoint>::<base>;<mod>u (no shifted key, only base)
    // \x1b[<codepoint>::<base>;<mod>:<event>u
    if let match = matchRegex("^\\x1B\\[(\\d+)(?::(\\d*))?(?::(\\d+))?(?:;(\\d+))?(?::(\\d+))?u$", in: data) {
        let codepoint = Int(match[1]) ?? 0
        let shiftedKey: Int? = match.count > 2 && !match[2].isEmpty ? Int(match[2]) : nil
        let baseLayoutKey: Int? = match.count > 3 && !match[3].isEmpty ? Int(match[3]) : nil
        let modString = match.count > 4 && !match[4].isEmpty ? match[4] : "1"
        let modValue = Int(modString) ?? 1
        return ParsedKittySequence(codepoint: codepoint, shiftedKey: shiftedKey, baseLayoutKey: baseLayoutKey, modifier: modValue - 1)
    }

    // Arrow keys with modifier: \x1b[1;<mod>A/B/C/D or \x1b[1;<mod>:<event>A/B/C/D
    if let match = matchRegex("^\\x1B\\[1;(\\d+)(?::(\\d+))?([ABCD])$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let letter = match.last ?? ""
        let arrowCodes: [String: Int] = ["A": -1, "B": -2, "C": -3, "D": -4]
        if let codepoint = arrowCodes[letter] {
            return ParsedKittySequence(codepoint: codepoint, shiftedKey: nil, baseLayoutKey: nil, modifier: modValue - 1)
        }
    }

    // Functional keys: \x1b[<num>~ or \x1b[<num>;<mod>~ or \x1b[<num>;<mod>:<event>~
    if let match = matchRegex("^\\x1B\\[(\\d+)(?:;(\\d+))?(?::(\\d+))?~$", in: data) {
        let keyNum = Int(match[1]) ?? 0
        let modString = match.count > 2 && !match[2].isEmpty ? match[2] : "1"
        let modValue = Int(modString) ?? 1
        let funcCodes: [Int: Int] = [
            2: FunctionalCodepoints.insert,
            3: FunctionalCodepoints.delete,
            5: FunctionalCodepoints.pageUp,
            6: FunctionalCodepoints.pageDown,
            7: FunctionalCodepoints.home,
            8: FunctionalCodepoints.end,
        ]
        if let codepoint = funcCodes[keyNum] {
            return ParsedKittySequence(codepoint: codepoint, shiftedKey: nil, baseLayoutKey: nil, modifier: modValue - 1)
        }
    }

    // Home/End with modifier: \x1b[1;<mod>H/F or \x1b[1;<mod>:<event>H/F
    if let match = matchRegex("^\\x1B\\[1;(\\d+)(?::(\\d+))?([HF])$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let letter = match.last ?? ""
        let codepoint = letter == "H" ? FunctionalCodepoints.home : FunctionalCodepoints.end
        return ParsedKittySequence(codepoint: codepoint, shiftedKey: nil, baseLayoutKey: nil, modifier: modValue - 1)
    }

    return nil
}

private func matchesKittySequence(_ data: String, expectedCodepoint: Int, expectedModifier: Int) -> Bool {
    guard let parsed = parseKittySequence(data) else {
        return false
    }

    let actualMod = parsed.modifier & ~lockMask
    let expectedMod = expectedModifier & ~lockMask

    // Check if modifiers match
    if actualMod != expectedMod { return false }

    // Primary match: codepoint matches directly
    if parsed.codepoint == expectedCodepoint { return true }

    // Alternate match: use base layout key for non-Latin keyboard layouts
    // This allows Ctrl+С (Cyrillic) to match Ctrl+c (Latin) when terminal reports
    // the base layout key (the key in standard PC-101 layout)
    if let baseLayoutKey = parsed.baseLayoutKey, baseLayoutKey == expectedCodepoint { return true }

    return false
}

private func matchesModifyOtherKeys(_ data: String, expectedKeycode: Int, expectedModifier: Int) -> Bool {
    if let match = matchRegex("^\\x1B\\[27;(\\d+);(\\d+)~$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let keycode = Int(match[2]) ?? 0
        let actualMod = modValue - 1
        return keycode == expectedKeycode && actualMod == expectedModifier
    }
    return false
}

private func rawCtrlChar(_ key: String) -> String? {
    if key == "]" { return "\u{001D}" }
    if key == "\\" { return "\u{001C}" }
    if key == "-" || key == "_" { return "\u{001F}" }  // Ctrl+- and Ctrl+_ both send 0x1F
    if key == "[" { return "\u{001B}" }
    guard let scalar = key.lowercased().unicodeScalars.first else { return nil }
    let code = Int(scalar.value) - 96
    guard code >= 0, let rawScalar = UnicodeScalar(code) else { return nil }
    return String(rawScalar)
}

private struct ParsedKeyId {
    let key: String
    let ctrl: Bool
    let shift: Bool
    let alt: Bool
}

private func parseKeyId(_ keyId: String) -> ParsedKeyId? {
    let parts = keyId.lowercased().split(separator: "+").map(String.init)
    guard let key = parts.last, !key.isEmpty else { return nil }
    return ParsedKeyId(
        key: key,
        ctrl: parts.contains("ctrl"),
        shift: parts.contains("shift"),
        alt: parts.contains("alt")
    )
}

/// Return true when input matches a key identifier (legacy or Kitty protocol).
public func matchesKey(_ data: String, _ keyId: KeyId) -> Bool {
    guard let parsed = parseKeyId(keyId) else { return false }

    let key = parsed.key
    let ctrl = parsed.ctrl
    let shift = parsed.shift
    let alt = parsed.alt

    var modifier = 0
    if shift { modifier |= Modifiers.shift }
    if alt { modifier |= Modifiers.alt }
    if ctrl { modifier |= Modifiers.ctrl }
    let kittyActive = isKittyProtocolActive()

    switch key {
    case "escape", "esc":
        if modifier != 0 { return false }
        return data == "\u{001B}" || matchesKittySequence(data, expectedCodepoint: Codepoints.escape, expectedModifier: 0)
    case "space":
        if !kittyActive {
            if ctrl && !alt && !shift && data == "\u{0000}" {
                return true
            }
            if alt && !ctrl && !shift && data == "\u{001B} " {
                return true
            }
        }
        if modifier == 0 {
            return data == " " || matchesKittySequence(data, expectedCodepoint: Codepoints.space, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: Codepoints.space, expectedModifier: modifier)
    case "tab":
        if shift && !ctrl && !alt {
            return data == "\u{001B}[Z" || matchesKittySequence(data, expectedCodepoint: Codepoints.tab, expectedModifier: Modifiers.shift)
        }
        if modifier == 0 {
            return data == "\t" || matchesKittySequence(data, expectedCodepoint: Codepoints.tab, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: Codepoints.tab, expectedModifier: modifier)
    case "enter", "return":
        if shift && !ctrl && !alt {
            if matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: Modifiers.shift)
                || matchesKittySequence(data, expectedCodepoint: Codepoints.kpEnter, expectedModifier: Modifiers.shift) {
                return true
            }
            if matchesModifyOtherKeys(data, expectedKeycode: Codepoints.enter, expectedModifier: Modifiers.shift) {
                return true
            }
            if kittyActive {
                return data == "\u{001B}\r" || data == "\n"
            }
            return false
        }
        if alt && !ctrl && !shift {
            if matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: Modifiers.alt)
                || matchesKittySequence(data, expectedCodepoint: Codepoints.kpEnter, expectedModifier: Modifiers.alt) {
                return true
            }
            if matchesModifyOtherKeys(data, expectedKeycode: Codepoints.enter, expectedModifier: Modifiers.alt) {
                return true
            }
            if !kittyActive {
                return data == "\u{001B}\r"
            }
            return false
        }
        if modifier == 0 {
            // When kitty is active, \n is shift+enter (handled above), so exclude it here
            if kittyActive && data == "\n" { return false }
            return data == "\r"
                || (!kittyActive && data == "\n")
                || data == "\u{001B}OM"
                || matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: 0)
                || matchesKittySequence(data, expectedCodepoint: Codepoints.kpEnter, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: modifier)
            || matchesKittySequence(data, expectedCodepoint: Codepoints.kpEnter, expectedModifier: modifier)
    case "backspace":
        if alt && !ctrl && !shift {
            return data == "\u{001B}\u{007F}" || data == "\u{001B}\u{0008}" || matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: Modifiers.alt)
        }
        if modifier == 0 {
            return data == "\u{007F}" || data == "\u{0008}" || matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: modifier)
    case "insert":
        if modifier == 0 {
            if let seqs = legacyKeySequences["insert"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.insert, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "insert", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.insert, expectedModifier: modifier)
    case "delete":
        if modifier == 0 {
            if let seqs = legacyKeySequences["delete"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.delete, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "delete", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.delete, expectedModifier: modifier)
    case "clear":
        if modifier == 0 {
            if let seqs = legacyKeySequences["clear"], matchesLegacySequence(data, seqs) {
                return true
            }
        }
        return matchesLegacyModifierSequence(data, "clear", modifier)
    case "home":
        if modifier == 0 {
            if let seqs = legacyKeySequences["home"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.home, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "home", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.home, expectedModifier: modifier)
    case "end":
        if modifier == 0 {
            if let seqs = legacyKeySequences["end"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.end, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "end", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.end, expectedModifier: modifier)
    case "pageup":
        if modifier == 0 {
            if let seqs = legacyKeySequences["pageUp"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageUp, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "pageUp", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageUp, expectedModifier: modifier)
    case "pagedown":
        if modifier == 0 {
            if let seqs = legacyKeySequences["pageDown"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageDown, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "pageDown", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageDown, expectedModifier: modifier)
    case "up":
        if alt && !ctrl && !shift {
            return data == "\u{001B}p" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.up, expectedModifier: Modifiers.alt)
        }
        if modifier == 0 {
            if let seqs = legacyKeySequences["up"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.up, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "up", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.up, expectedModifier: modifier)
    case "down":
        if alt && !ctrl && !shift {
            return data == "\u{001B}n" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.down, expectedModifier: Modifiers.alt)
        }
        if modifier == 0 {
            if let seqs = legacyKeySequences["down"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.down, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "down", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.down, expectedModifier: modifier)
    case "left":
        if alt && !ctrl && !shift {
            return data == "\u{001B}[1;3D"
                || (!kittyActive && (data == "\u{001B}B" || data == "\u{001B}b"))
                || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: Modifiers.alt)
        }
        if ctrl && !alt && !shift {
            return data == "\u{001B}[1;5D"
                || matchesLegacyModifierSequence(data, "left", Modifiers.ctrl)
                || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: Modifiers.ctrl)
        }
        if modifier == 0 {
            if let seqs = legacyKeySequences["left"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "left", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: modifier)
    case "right":
        if alt && !ctrl && !shift {
            return data == "\u{001B}[1;3C"
                || (!kittyActive && (data == "\u{001B}F" || data == "\u{001B}f"))
                || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: Modifiers.alt)
        }
        if ctrl && !alt && !shift {
            return data == "\u{001B}[1;5C"
                || matchesLegacyModifierSequence(data, "right", Modifiers.ctrl)
                || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: Modifiers.ctrl)
        }
        if modifier == 0 {
            if let seqs = legacyKeySequences["right"], matchesLegacySequence(data, seqs) {
                return true
            }
            return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: 0)
        }
        if matchesLegacyModifierSequence(data, "right", modifier) {
            return true
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: modifier)
    case "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12":
        if modifier != 0 { return false }
        if let seqs = legacyKeySequences[key] {
            return matchesLegacySequence(data, seqs)
        }
        return false
    default:
        break
    }

    if key.count == 1, let scalar = key.unicodeScalars.first {
        let isLetter = key >= "a" && key <= "z"
        let isSymbol = symbolKeys.contains(key)
        if isLetter || isSymbol {
            let codepoint = Int(scalar.value)

            if ctrl && !shift && !alt {
                if let raw = rawCtrlChar(key) {
                    if data == raw { return true }
                    if let dataScalar = data.unicodeScalars.first, let rawScalar = raw.unicodeScalars.first, dataScalar.value == rawScalar.value {
                        return true
                    }
                }
                return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: Modifiers.ctrl)
            }

            if ctrl && shift && !alt {
                return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: Modifiers.shift + Modifiers.ctrl)
            }

            if shift && !ctrl && !alt {
                if isLetter, data == key.uppercased() { return true }
                return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: Modifiers.shift)
            }

            if ctrl && alt && !shift {
                if !kittyActive, let raw = rawCtrlChar(key), data == "\u{001B}\(raw)" {
                    return true
                }
                return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: Modifiers.ctrl + Modifiers.alt)
            }

            if alt && !ctrl && !shift {
                if !kittyActive && isLetter && data == "\u{001B}\(key)" { return true }
                return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: Modifiers.alt)
            }

            if modifier != 0 {
                return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: modifier)
            }

            return data == key || matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: 0)
        }
    }

    return false
}

/// Parse input data into a key identifier, if recognized.
public func parseKey(_ data: String) -> KeyId? {
    let kittyActive = isKittyProtocolActive()

    if let kitty = parseKittySequence(data) {
        let effectiveMod = kitty.modifier & ~lockMask
        var mods: [String] = []
        if (effectiveMod & Modifiers.shift) != 0 { mods.append("shift") }
        if (effectiveMod & Modifiers.ctrl) != 0 { mods.append("ctrl") }
        if (effectiveMod & Modifiers.alt) != 0 { mods.append("alt") }

        // Prefer base layout key for consistent shortcut naming across keyboard layouts
        // This ensures Ctrl+С (Cyrillic) is reported as "ctrl+c" (Latin)
        let effectiveCodepoint = kitty.baseLayoutKey ?? kitty.codepoint

        var keyName: String?
        switch effectiveCodepoint {
        case Codepoints.escape:
            keyName = "escape"
        case Codepoints.tab:
            keyName = "tab"
        case Codepoints.enter, Codepoints.kpEnter:
            keyName = "enter"
        case Codepoints.space:
            keyName = "space"
        case Codepoints.backspace:
            keyName = "backspace"
        case FunctionalCodepoints.delete:
            keyName = "delete"
        case FunctionalCodepoints.insert:
            keyName = "insert"
        case FunctionalCodepoints.home:
            keyName = "home"
        case FunctionalCodepoints.end:
            keyName = "end"
        case FunctionalCodepoints.pageUp:
            keyName = "pageUp"
        case FunctionalCodepoints.pageDown:
            keyName = "pageDown"
        case ArrowCodepoints.up:
            keyName = "up"
        case ArrowCodepoints.down:
            keyName = "down"
        case ArrowCodepoints.left:
            keyName = "left"
        case ArrowCodepoints.right:
            keyName = "right"
        default:
            if effectiveCodepoint >= 97 && effectiveCodepoint <= 122, let scalar = UnicodeScalar(effectiveCodepoint) {
                keyName = String(scalar)
            } else if let scalar = UnicodeScalar(effectiveCodepoint) {
                let symbol = String(scalar)
                if symbolKeys.contains(symbol) {
                    keyName = symbol
                }
            }
        }

        if let keyName {
            return mods.isEmpty ? keyName : mods.joined(separator: "+") + "+" + keyName
        }
    }

    // Mode-aware legacy sequences
    // When Kitty protocol is active, ambiguous sequences are interpreted as custom terminal mappings:
    // - \x1b\r = shift+enter (Kitty mapping), not alt+enter
    // - \n = shift+enter (Ghostty mapping)
    if kittyActive {
        if data == "\u{001B}\r" || data == "\n" { return "shift+enter" }
    }

    // Check legacy sequence lookup table (SS3 sequences, function keys, rxvt modifiers)
    // Exclude ambiguous alt+letter sequences when kitty is active
    if let keyId = legacySequenceKeyIds[data] {
        // When kitty is active, don't match ESC+letter as alt+letter - they're ambiguous
        if kittyActive && data.count == 2 && data.first == "\u{001B}" {
            let second = data[data.index(after: data.startIndex)]
            if let scalar = second.unicodeScalars.first {
                let code = Int(scalar.value)
                // Skip lowercase letters and Emacs-style navigation keys
                if (code >= 97 && code <= 122) || (code >= 65 && code <= 90) {
                    // Don't return the keyId, fall through to other checks
                }
                else {
                    return keyId
                }
            }
        } else {
            return keyId
        }
    }

    if data == "\u{001B}" { return "escape" }
    if data == "\u{001C}" { return "ctrl+\\" }
    if data == "\u{001D}" { return "ctrl+]" }
    if data == "\u{001F}" { return "ctrl+-" }
    if data == "\u{001B}\u{001B}" { return "ctrl+alt+[" }
    if data == "\u{001B}\u{001C}" { return "ctrl+alt+\\" }
    if data == "\u{001B}\u{001D}" { return "ctrl+alt+]" }
    if data == "\u{001B}\u{001F}" { return "ctrl+alt+-" }
    if data == "\t" { return "tab" }
    if data == "\r" || (!kittyActive && data == "\n") || data == "\u{001B}OM" { return "enter" }
    if data == "\u{0000}" { return "ctrl+space" }
    if data == " " { return "space" }
    if data == "\u{007F}" || data == "\u{0008}" { return "backspace" }
    if data == "\u{001B}[Z" { return "shift+tab" }
    if !kittyActive && data == "\u{001B}\r" { return "alt+enter" }
    if !kittyActive && data == "\u{001B} " { return "alt+space" }
    if data == "\u{001B}\u{007F}" || data == "\u{001B}\u{0008}" { return "alt+backspace" }
    if !kittyActive && data == "\u{001B}B" { return "alt+left" }
    if !kittyActive && data == "\u{001B}F" { return "alt+right" }
    if data == "\u{001B}[A" { return "up" }
    if data == "\u{001B}[B" { return "down" }
    if data == "\u{001B}[C" { return "right" }
    if data == "\u{001B}[D" { return "left" }
    if data == "\u{001B}[H" { return "home" }
    if data == "\u{001B}[F" { return "end" }
    if data == "\u{001B}[3~" { return "delete" }
    if data == "\u{001B}[5~" { return "pageUp" }
    if data == "\u{001B}[6~" { return "pageDown" }
    if !kittyActive && data.count == 2, data.first == "\u{001B}" {
        let second = data[data.index(after: data.startIndex)]
        if let scalar = second.unicodeScalars.first {
            let code = Int(scalar.value)
            if code >= 1 && code <= 26 {
                return "ctrl+alt+" + String(UnicodeScalar(code + 96)!)
            }
            if code >= 97 && code <= 122 {
                return "alt+" + String(UnicodeScalar(code)!)
            }
        }
    }

    if data.count == 1, let scalar = data.unicodeScalars.first {
        let code = Int(scalar.value)
        if code >= 1 && code <= 26 {
            return "ctrl+" + String(UnicodeScalar(code + 96)!)
        }
        if code >= 32 && code <= 126 {
            return data
        }
    }

    return nil
}

private func matchRegex(_ pattern: String, in text: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range) else {
        return nil
    }
    var results: [String] = []
    for index in 0..<match.numberOfRanges {
        let matchRange = match.range(at: index)
        if let swiftRange = Range(matchRange, in: text) {
            results.append(String(text[swiftRange]))
        } else {
            results.append("")
        }
    }
    return results
}
