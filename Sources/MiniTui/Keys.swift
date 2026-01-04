import Foundation

private enum Codepoints {
    static let a = 97
    static let b = 98
    static let c = 99
    static let d = 100
    static let e = 101
    static let f = 102
    static let g = 103
    static let k = 107
    static let l = 108
    static let n = 110
    static let o = 111
    static let p = 112
    static let t = 116
    static let u = 117
    static let w = 119
    static let y = 121
    static let z = 122

    static let escape = 27
    static let tab = 9
    static let enter = 13
    static let space = 32
    static let backspace = 127
}

private let lockMask = 64 + 128

private enum Modifiers {
    static let shift = 1
    static let alt = 2
    static let ctrl = 4
    static let `super` = 8
}

private func kittySequence(codepoint: Int, modifier: Int) -> String {
    return "\u{001B}[\(codepoint);\(modifier + 1)u"
}

private struct ParsedKittySequence {
    let codepoint: Int
    let modifier: Int
}

private enum FunctionalCodepoints {
    static let delete = -10
    static let insert = -11
    static let pageUp = -12
    static let pageDown = -13
    static let home = -14
    static let end = -15
}

private func parseKittySequence(_ data: String) -> ParsedKittySequence? {
    if let match = matchRegex("^\\u{001B}\\[(\\d+)(?:;(\\d+))?u$", in: data) {
        let codepoint = Int(match[1]) ?? 0
        let modString = match.count > 2 && !match[2].isEmpty ? match[2] : "1"
        let modValue = Int(modString) ?? 1
        return ParsedKittySequence(codepoint: codepoint, modifier: modValue - 1)
    }

    if let match = matchRegex("^\\u{001B}\\[1;(\\d+)([ABCD])$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let letter = match[2]
        let arrowCodes: [String: Int] = ["A": -1, "B": -2, "C": -3, "D": -4]
        if let codepoint = arrowCodes[letter] {
            return ParsedKittySequence(codepoint: codepoint, modifier: modValue - 1)
        }
    }

    if let match = matchRegex("^\\u{001B}\\[(\\d+)(?:;(\\d+))?~$", in: data) {
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

    if let match = matchRegex("^\\u{001B}\\[1;(\\d+)([HF])$", in: data) {
        let modValue = Int(match[1]) ?? 1
        let letter = match[2]
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

/// Kitty protocol escape sequences for common keys.
public enum Keys {
    /// Kitty sequence for Ctrl+A.
    public static let ctrlA = kittySequence(codepoint: Codepoints.a, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+B.
    public static let ctrlB = kittySequence(codepoint: Codepoints.b, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+C.
    public static let ctrlC = kittySequence(codepoint: Codepoints.c, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+D.
    public static let ctrlD = kittySequence(codepoint: Codepoints.d, modifier: Modifiers.ctrl)
    /// Kitty sequence for Alt+D.
    public static let altD = kittySequence(codepoint: Codepoints.d, modifier: Modifiers.alt)
    /// Kitty sequence for Ctrl+E.
    public static let ctrlE = kittySequence(codepoint: Codepoints.e, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+F.
    public static let ctrlF = kittySequence(codepoint: Codepoints.f, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+G.
    public static let ctrlG = kittySequence(codepoint: Codepoints.g, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+K.
    public static let ctrlK = kittySequence(codepoint: Codepoints.k, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+L.
    public static let ctrlL = kittySequence(codepoint: Codepoints.l, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+N.
    public static let ctrlN = kittySequence(codepoint: Codepoints.n, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+O.
    public static let ctrlO = kittySequence(codepoint: Codepoints.o, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+P.
    public static let ctrlP = kittySequence(codepoint: Codepoints.p, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+T.
    public static let ctrlT = kittySequence(codepoint: Codepoints.t, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+U.
    public static let ctrlU = kittySequence(codepoint: Codepoints.u, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+W.
    public static let ctrlW = kittySequence(codepoint: Codepoints.w, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+Y.
    public static let ctrlY = kittySequence(codepoint: Codepoints.y, modifier: Modifiers.ctrl)
    /// Kitty sequence for Ctrl+Z.
    public static let ctrlZ = kittySequence(codepoint: Codepoints.z, modifier: Modifiers.ctrl)

    /// Kitty sequence for Shift+Enter.
    public static let shiftEnter = kittySequence(codepoint: Codepoints.enter, modifier: Modifiers.shift)
    /// Kitty sequence for Alt+Enter.
    public static let altEnter = kittySequence(codepoint: Codepoints.enter, modifier: Modifiers.alt)
    /// Kitty sequence for Ctrl+Enter.
    public static let ctrlEnter = kittySequence(codepoint: Codepoints.enter, modifier: Modifiers.ctrl)

    /// Kitty sequence for Shift+Tab.
    public static let shiftTab = kittySequence(codepoint: Codepoints.tab, modifier: Modifiers.shift)

    /// Kitty sequence for Alt+Backspace.
    public static let altBackspace = kittySequence(codepoint: Codepoints.backspace, modifier: Modifiers.alt)
}

private enum RawKeys {
    static let ctrlA = "\u{0001}"
    static let ctrlB = "\u{0002}"
    static let ctrlC = "\u{0003}"
    static let ctrlD = "\u{0004}"
    static let altD = "\u{001B}d"
    static let ctrlE = "\u{0005}"
    static let ctrlF = "\u{0006}"
    static let ctrlG = "\u{0007}"
    static let ctrlK = "\u{000B}"
    static let ctrlL = "\u{000C}"
    static let ctrlN = "\u{000E}"
    static let ctrlO = "\u{000F}"
    static let ctrlP = "\u{0010}"
    static let ctrlT = "\u{0014}"
    static let ctrlU = "\u{0015}"
    static let ctrlW = "\u{0017}"
    static let ctrlY = "\u{0019}"
    static let ctrlZ = "\u{001A}"
    static let altBackspace = "\u{001B}\u{007F}"
    static let shiftTab = "\u{001B}[Z"
}

/// Return true when input matches Ctrl+<key> using Kitty protocol.
public func isKittyCtrl(_ data: String, key: String) -> Bool {
    guard key.count == 1, let scalar = key.unicodeScalars.first else {
        return false
    }
    let codepoint = Int(scalar.value)
    if data == kittySequence(codepoint: codepoint, modifier: Modifiers.ctrl) {
        return true
    }
    return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches a Kitty protocol codepoint and modifier.
public func isKittyKey(_ data: String, codepoint: Int, modifier: Int) -> Bool {
    if data == kittySequence(codepoint: codepoint, modifier: modifier) {
        return true
    }
    return matchesKittySequence(data, expectedCodepoint: codepoint, expectedModifier: modifier)
}

/// Return true when input matches Ctrl+A (raw byte or Kitty protocol).
public func isCtrlA(_ data: String) -> Bool {
    return data == RawKeys.ctrlA || data == Keys.ctrlA || matchesKittySequence(data, expectedCodepoint: Codepoints.a, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+B (raw byte or Kitty protocol).
public func isCtrlB(_ data: String) -> Bool {
    return data == RawKeys.ctrlB || data == Keys.ctrlB || matchesKittySequence(data, expectedCodepoint: Codepoints.b, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+C (raw byte or Kitty protocol).
public func isCtrlC(_ data: String) -> Bool {
    return data == RawKeys.ctrlC || data == Keys.ctrlC || matchesKittySequence(data, expectedCodepoint: Codepoints.c, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+D (raw byte or Kitty protocol).
public func isCtrlD(_ data: String) -> Bool {
    return data == RawKeys.ctrlD || data == Keys.ctrlD || matchesKittySequence(data, expectedCodepoint: Codepoints.d, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Alt+D (raw byte or Kitty protocol).
public func isAltD(_ data: String) -> Bool {
    return data == RawKeys.altD || data == Keys.altD || matchesKittySequence(data, expectedCodepoint: Codepoints.d, expectedModifier: Modifiers.alt)
}

/// Return true when input matches Ctrl+E (raw byte or Kitty protocol).
public func isCtrlE(_ data: String) -> Bool {
    return data == RawKeys.ctrlE || data == Keys.ctrlE || matchesKittySequence(data, expectedCodepoint: Codepoints.e, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+F (raw byte or Kitty protocol).
public func isCtrlF(_ data: String) -> Bool {
    return data == RawKeys.ctrlF || data == Keys.ctrlF || matchesKittySequence(data, expectedCodepoint: Codepoints.f, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+G (raw byte or Kitty protocol).
public func isCtrlG(_ data: String) -> Bool {
    return data == RawKeys.ctrlG || data == Keys.ctrlG || matchesKittySequence(data, expectedCodepoint: Codepoints.g, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+K (raw byte or Kitty protocol).
public func isCtrlK(_ data: String) -> Bool {
    if data == RawKeys.ctrlK { return true }
    if let first = data.unicodeScalars.first, first.value == 0x0B { return true }
    return data == Keys.ctrlK || matchesKittySequence(data, expectedCodepoint: Codepoints.k, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+L (raw byte or Kitty protocol).
public func isCtrlL(_ data: String) -> Bool {
    return data == RawKeys.ctrlL || data == Keys.ctrlL || matchesKittySequence(data, expectedCodepoint: Codepoints.l, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+N (raw byte or Kitty protocol).
public func isCtrlN(_ data: String) -> Bool {
    return data == RawKeys.ctrlN || data == Keys.ctrlN || matchesKittySequence(data, expectedCodepoint: Codepoints.n, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+O (raw byte or Kitty protocol).
public func isCtrlO(_ data: String) -> Bool {
    return data == RawKeys.ctrlO || data == Keys.ctrlO || matchesKittySequence(data, expectedCodepoint: Codepoints.o, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Shift+Ctrl+O (Kitty protocol).
public func isShiftCtrlO(_ data: String) -> Bool {
    return matchesKittySequence(data, expectedCodepoint: Codepoints.o, expectedModifier: Modifiers.shift + Modifiers.ctrl)
}

/// Return true when input matches Ctrl+P (raw byte or Kitty protocol).
public func isCtrlP(_ data: String) -> Bool {
    return data == RawKeys.ctrlP || data == Keys.ctrlP || matchesKittySequence(data, expectedCodepoint: Codepoints.p, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Shift+Ctrl+P (Kitty protocol).
public func isShiftCtrlP(_ data: String) -> Bool {
    return matchesKittySequence(data, expectedCodepoint: Codepoints.p, expectedModifier: Modifiers.shift + Modifiers.ctrl)
}

/// Return true when input matches Shift+Ctrl+D (Kitty protocol).
public func isShiftCtrlD(_ data: String) -> Bool {
    return matchesKittySequence(data, expectedCodepoint: Codepoints.d, expectedModifier: Modifiers.shift + Modifiers.ctrl)
}

/// Return true when input matches Ctrl+T (raw byte or Kitty protocol).
public func isCtrlT(_ data: String) -> Bool {
    return data == RawKeys.ctrlT || data == Keys.ctrlT || matchesKittySequence(data, expectedCodepoint: Codepoints.t, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+U (raw byte or Kitty protocol).
public func isCtrlU(_ data: String) -> Bool {
    return data == RawKeys.ctrlU || data == Keys.ctrlU || matchesKittySequence(data, expectedCodepoint: Codepoints.u, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+W (raw byte or Kitty protocol).
public func isCtrlW(_ data: String) -> Bool {
    return data == RawKeys.ctrlW || data == Keys.ctrlW || matchesKittySequence(data, expectedCodepoint: Codepoints.w, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+Y (raw byte or Kitty protocol).
public func isCtrlY(_ data: String) -> Bool {
    return data == RawKeys.ctrlY || data == Keys.ctrlY || matchesKittySequence(data, expectedCodepoint: Codepoints.y, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+Z (raw byte or Kitty protocol).
public func isCtrlZ(_ data: String) -> Bool {
    return data == RawKeys.ctrlZ || data == Keys.ctrlZ || matchesKittySequence(data, expectedCodepoint: Codepoints.z, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Alt+Backspace (legacy or Kitty protocol).
public func isAltBackspace(_ data: String) -> Bool {
    return data == RawKeys.altBackspace || data == Keys.altBackspace || matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: Modifiers.alt)
}

/// Return true when input matches Shift+Tab (legacy or Kitty protocol).
public func isShiftTab(_ data: String) -> Bool {
    return data == RawKeys.shiftTab || data == Keys.shiftTab || matchesKittySequence(data, expectedCodepoint: Codepoints.tab, expectedModifier: Modifiers.shift)
}

/// Return true when input matches Escape (raw byte or Kitty protocol).
public func isEscape(_ data: String) -> Bool {
    return data == "\u{001B}" || data == "\u{001B}[\(Codepoints.escape)u" || matchesKittySequence(data, expectedCodepoint: Codepoints.escape, expectedModifier: 0)
}

private enum ArrowCodepoints {
    static let up = -1
    static let down = -2
    static let right = -3
    static let left = -4
}

/// Return true when input matches Arrow Up (legacy or Kitty protocol).
public func isArrowUp(_ data: String) -> Bool {
    return data == "\u{001B}[A" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.up, expectedModifier: 0)
}

/// Return true when input matches Arrow Down (legacy or Kitty protocol).
public func isArrowDown(_ data: String) -> Bool {
    return data == "\u{001B}[B" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.down, expectedModifier: 0)
}

/// Return true when input matches Arrow Right (legacy or Kitty protocol).
public func isArrowRight(_ data: String) -> Bool {
    return data == "\u{001B}[C" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: 0)
}

/// Return true when input matches Arrow Left (legacy or Kitty protocol).
public func isArrowLeft(_ data: String) -> Bool {
    return data == "\u{001B}[D" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: 0)
}

/// Return true when input matches Tab (legacy or Kitty protocol).
public func isTab(_ data: String) -> Bool {
    return data == "\t" || matchesKittySequence(data, expectedCodepoint: Codepoints.tab, expectedModifier: 0)
}

/// Return true when input matches Enter (legacy or Kitty protocol).
public func isEnter(_ data: String) -> Bool {
    return data == "\r" || matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: 0)
}

/// Return true when input matches Backspace (legacy or Kitty protocol).
public func isBackspace(_ data: String) -> Bool {
    return data == "\u{007F}" || data == "\u{0008}" || matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: 0)
}

/// Return true when input matches Shift+Backspace (Kitty protocol).
public func isShiftBackspace(_ data: String) -> Bool {
    return matchesKittySequence(data, expectedCodepoint: Codepoints.backspace, expectedModifier: Modifiers.shift)
}

/// Return true when input matches Shift+Enter (Kitty protocol).
public func isShiftEnter(_ data: String) -> Bool {
    return data == Keys.shiftEnter || matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: Modifiers.shift)
}

/// Return true when input matches Alt+Enter (legacy or Kitty protocol).
public func isAltEnter(_ data: String) -> Bool {
    return data == Keys.altEnter || data == "\u{001B}\r" || matchesKittySequence(data, expectedCodepoint: Codepoints.enter, expectedModifier: Modifiers.alt)
}

/// Return true when input matches Shift+Space (Kitty protocol).
public func isShiftSpace(_ data: String) -> Bool {
    return matchesKittySequence(data, expectedCodepoint: Codepoints.space, expectedModifier: Modifiers.shift)
}

/// Return true when input matches Alt+Left (legacy or Kitty protocol).
public func isAltLeft(_ data: String) -> Bool {
    return data == "\u{001B}[1;3D" || data == "\u{001B}b" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: Modifiers.alt)
}

/// Return true when input matches Alt+Right (legacy or Kitty protocol).
public func isAltRight(_ data: String) -> Bool {
    return data == "\u{001B}[1;3C" || data == "\u{001B}f" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: Modifiers.alt)
}

/// Return true when input matches Ctrl+Left (legacy or Kitty protocol).
public func isCtrlLeft(_ data: String) -> Bool {
    return data == "\u{001B}[1;5D" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.left, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Ctrl+Right (legacy or Kitty protocol).
public func isCtrlRight(_ data: String) -> Bool {
    return data == "\u{001B}[1;5C" || matchesKittySequence(data, expectedCodepoint: ArrowCodepoints.right, expectedModifier: Modifiers.ctrl)
}

/// Return true when input matches Home (legacy or Kitty protocol).
public func isHome(_ data: String) -> Bool {
    return data == "\u{001B}[H" || data == "\u{001B}[1~" || data == "\u{001B}[7~" || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.home, expectedModifier: 0)
}

/// Return true when input matches End (legacy or Kitty protocol).
public func isEnd(_ data: String) -> Bool {
    return data == "\u{001B}[F" || data == "\u{001B}[4~" || data == "\u{001B}[8~" || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.end, expectedModifier: 0)
}

/// Return true when input matches Delete (legacy or Kitty protocol).
public func isDelete(_ data: String) -> Bool {
    return data == "\u{001B}[3~" || matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.delete, expectedModifier: 0)
}

/// Return true when input matches Shift+Delete (Kitty protocol).
public func isShiftDelete(_ data: String) -> Bool {
    return matchesKittySequence(data, expectedCodepoint: FunctionalCodepoints.delete, expectedModifier: Modifiers.shift)
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
