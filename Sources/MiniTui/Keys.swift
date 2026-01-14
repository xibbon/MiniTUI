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
    if let match = matchRegex("^\\u{001B}\\[(\\d+)(?:;(\\d+))?(?::(\\d+))?u$", in: data) {
        let codepoint = Int(match[1]) ?? 0
        let modString = match.count > 2 && !match[2].isEmpty ? match[2] : "1"
        let modValue = Int(modString) ?? 1
        return ParsedKittySequence(codepoint: codepoint, modifier: modValue - 1)
    }

    if let match = matchRegex("^\\u{001B}\\[1;(\\d+)(?::(\\d+))?([ABCD])$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let letter = match.last ?? ""
        let arrowCodes: [String: Int] = ["A": -1, "B": -2, "C": -3, "D": -4]
        if let codepoint = arrowCodes[letter] {
            return ParsedKittySequence(codepoint: codepoint, modifier: modValue - 1)
        }
    }

    if let match = matchRegex("^\\u{001B}\\[(\\d+)(?:;(\\d+))?(?::(\\d+))?~$", in: data) {
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
            return ParsedKittySequence(codepoint: codepoint, modifier: modValue - 1)
        }
    }

    if let match = matchRegex("^\\u{001B}\\[1;(\\d+)(?::(\\d+))?([HF])$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let letter = match.last ?? ""
        let codepoint = letter == "H" ? FunctionalCodepoints.home : FunctionalCodepoints.end
        return ParsedKittySequence(codepoint: codepoint, modifier: modValue - 1)
    }

    return nil
}

private func matchesKittySequence(_ data: String, expectedCodepoint: Int, expectedModifier: Int) -> Bool {
    guard let parsed = parseKittySequence(data) else {
        return false
    }

    let actualMod = parsed.modifier & ~lockMask
    let expectedMod = expectedModifier & ~lockMask

    return parsed.codepoint == expectedCodepoint && actualMod == expectedMod
}

private func matchesModifyOtherKeys(_ data: String, expectedKeycode: Int, expectedModifier: Int) -> Bool {
    if let match = matchRegex("^\\u{001B}\\[27;(\\d+);(\\d+)~$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let keycode = Int(match[2]) ?? 0
        let actualMod = modValue - 1
        return keycode == expectedKeycode && actualMod == expectedModifier
    }
    return false
}

private func rawCtrlChar(_ key: String) -> String? {
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
            return data == "\r"
                || data == "\u{001B}OM"
                || matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: 0)
                || matchesKittySequence(data, expectedCodepoint: Codepoints.kpEnter, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: modifier)
            || matchesKittySequence(data, expectedCodepoint: Codepoints.kpEnter, expectedModifier: modifier)
    case "backspace":
        if alt && !ctrl && !shift {
            return data == "\u{001B}\u{007F}" || matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: Modifiers.alt)
        }
        if modifier == 0 {
            return data == "\u{007F}" || data == "\u{0008}" || matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: modifier)
    case "delete":
        if modifier == 0 {
            return data == "\u{001B}[3~" || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.delete, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.delete, expectedModifier: modifier)
    case "home":
        if modifier == 0 {
            return data == "\u{001B}[H"
                || data == "\u{001B}[1~"
                || data == "\u{001B}[7~"
                || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.home, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.home, expectedModifier: modifier)
    case "end":
        if modifier == 0 {
            return data == "\u{001B}[F"
                || data == "\u{001B}[4~"
                || data == "\u{001B}[8~"
                || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.end, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.end, expectedModifier: modifier)
    case "pageup":
        if modifier == 0 {
            return data == "\u{001B}[5~" || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageUp, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageUp, expectedModifier: modifier)
    case "pagedown":
        if modifier == 0 {
            return data == "\u{001B}[6~" || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageDown, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.pageDown, expectedModifier: modifier)
    case "up":
        if modifier == 0 {
            return data == "\u{001B}[A" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.up, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.up, expectedModifier: modifier)
    case "down":
        if modifier == 0 {
            return data == "\u{001B}[B" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.down, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.down, expectedModifier: modifier)
    case "left":
        if alt && !ctrl && !shift {
            return data == "\u{001B}[1;3D"
                || data == "\u{001B}b"
                || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: Modifiers.alt)
        }
        if ctrl && !alt && !shift {
            return data == "\u{001B}[1;5D" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: Modifiers.ctrl)
        }
        if modifier == 0 {
            return data == "\u{001B}[D" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: modifier)
    case "right":
        if alt && !ctrl && !shift {
            return data == "\u{001B}[1;3C"
                || data == "\u{001B}f"
                || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: Modifiers.alt)
        }
        if ctrl && !alt && !shift {
            return data == "\u{001B}[1;5C" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: Modifiers.ctrl)
        }
        if modifier == 0 {
            return data == "\u{001B}[C" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: 0)
        }
        return matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: modifier)
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

        var keyName: String?
        switch kitty.codepoint {
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
            if kitty.codepoint >= 97 && kitty.codepoint <= 122, let scalar = UnicodeScalar(kitty.codepoint) {
                keyName = String(scalar)
            } else if let scalar = UnicodeScalar(kitty.codepoint) {
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

    if kittyActive {
        if data == "\u{001B}\r" || data == "\n" { return "shift+enter" }
    }

    if data == "\u{001B}" { return "escape" }
    if data == "\t" { return "tab" }
    if data == "\r" || data == "\u{001B}OM" { return "enter" }
    if data == " " { return "space" }
    if data == "\u{007F}" || data == "\u{0008}" { return "backspace" }
    if data == "\u{001B}[Z" { return "shift+tab" }
    if !kittyActive && data == "\u{001B}\r" { return "alt+enter" }
    if data == "\u{001B}\u{007F}" { return "alt+backspace" }
    if data == "\u{001B}[A" { return "up" }
    if data == "\u{001B}[B" { return "down" }
    if data == "\u{001B}[C" { return "right" }
    if data == "\u{001B}[D" { return "left" }
    if data == "\u{001B}[H" { return "home" }
    if data == "\u{001B}[F" { return "end" }
    if data == "\u{001B}[3~" { return "delete" }
    if data == "\u{001B}[5~" { return "pageUp" }
    if data == "\u{001B}[6~" { return "pageDown" }

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
