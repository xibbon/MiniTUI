import Testing
@testable import MiniTui

// MARK: - matchesKey Tests

@Suite("matchesKey", .serialized)
struct MatchesKeyTests {

    // MARK: - Kitty protocol with alternate keys (non-Latin layouts)

    @Suite("Kitty protocol with alternate keys (non-Latin layouts)")
    struct KittyAlternateKeysTests {
        // Kitty protocol flag 4 (Report alternate keys) sends:
        // CSI codepoint:shifted:base ; modifier:event u
        // Where base is the key in standard PC-101 layout

        @Test("should match Ctrl+c when pressing Ctrl+С (Cyrillic) with base layout key")
        func matchCtrlCCyrillic() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Cyrillic 'с' = codepoint 1089, Latin 'c' = codepoint 99
            // Format: CSI 1089::99;5u (codepoint::base;modifier with ctrl=4, +1=5)
            let cyrillicCtrlC = "\u{001B}[1089::99;5u"
            #expect(matchesKey(cyrillicCtrlC, "ctrl+c") == true)
        }

        @Test("should match Ctrl+d when pressing Ctrl+В (Cyrillic) with base layout key")
        func matchCtrlDCyrillic() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Cyrillic 'в' = codepoint 1074, Latin 'd' = codepoint 100
            let cyrillicCtrlD = "\u{001B}[1074::100;5u"
            #expect(matchesKey(cyrillicCtrlD, "ctrl+d") == true)
        }

        @Test("should match Ctrl+z when pressing Ctrl+Я (Cyrillic) with base layout key")
        func matchCtrlZCyrillic() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Cyrillic 'я' = codepoint 1103, Latin 'z' = codepoint 122
            let cyrillicCtrlZ = "\u{001B}[1103::122;5u"
            #expect(matchesKey(cyrillicCtrlZ, "ctrl+z") == true)
        }

        @Test("should match Ctrl+Shift+p with base layout key")
        func matchCtrlShiftPCyrillic() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Cyrillic 'з' = codepoint 1079, Latin 'p' = codepoint 112
            // ctrl=4, shift=1, +1 = 6
            let cyrillicCtrlShiftP = "\u{001B}[1079::112;6u"
            #expect(matchesKey(cyrillicCtrlShiftP, "ctrl+shift+p") == true)
        }

        @Test("should still match direct codepoint when no base layout key")
        func matchDirectCodepoint() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Latin ctrl+c without base layout key (terminal doesn't support flag 4)
            let latinCtrlC = "\u{001B}[99;5u"
            #expect(matchesKey(latinCtrlC, "ctrl+c") == true)
        }

        @Test("should handle shifted key in format")
        func handleShiftedKey() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Format with shifted key: CSI codepoint:shifted:base;modifier u
            // Latin 'c' with shifted 'C' (67) and base 'c' (99)
            let shiftedKey = "\u{001B}[99:67:99;2u"  // shift modifier = 1, +1 = 2
            #expect(matchesKey(shiftedKey, "shift+c") == true)
        }

        @Test("should handle event type in format")
        func handleEventType() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Format with event type: CSI codepoint::base;modifier:event u
            // Cyrillic ctrl+c release event (event type 3)
            let releaseEvent = "\u{001B}[1089::99;5:3u"
            #expect(matchesKey(releaseEvent, "ctrl+c") == true)
        }

        @Test("should handle full format with shifted key, base key, and event type")
        func handleFullFormat() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Full format: CSI codepoint:shifted:base;modifier:event u
            // Cyrillic 'С' (shifted) with base 'c', Ctrl+Shift pressed, repeat event
            // Cyrillic 'с' = 1089, Cyrillic 'С' = 1057, Latin 'c' = 99
            // ctrl=4, shift=1, +1 = 6, repeat event = 2
            let fullFormat = "\u{001B}[1089:1057:99;6:2u"
            #expect(matchesKey(fullFormat, "ctrl+shift+c") == true)
        }

        @Test("should prefer codepoint for Latin letters even when base layout differs")
        func preferCodepointForLatinLetters() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Dvorak Ctrl+K reports codepoint 'k' (107) and base layout 'v' (118)
            let dvorakCtrlK = "\u{001B}[107::118;5u"
            #expect(matchesKey(dvorakCtrlK, "ctrl+k") == true)
            #expect(matchesKey(dvorakCtrlK, "ctrl+v") == false)
            #expect(parseKey(dvorakCtrlK) == "ctrl+k")
        }

        @Test("should prefer codepoint for symbol keys even when base layout differs")
        func preferCodepointForSymbols() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Dvorak Ctrl+/ reports codepoint '/' (47) and base layout '[' (91)
            let dvorakCtrlSlash = "\u{001B}[47::91;5u"
            #expect(matchesKey(dvorakCtrlSlash, "ctrl+/") == true)
            #expect(matchesKey(dvorakCtrlSlash, "ctrl+[") == false)
            #expect(parseKey(dvorakCtrlSlash) == "ctrl+/")
        }

        @Test("should not match wrong key even with base layout")
        func noMatchWrongKey() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Cyrillic ctrl+с with base 'c' should NOT match ctrl+d
            let cyrillicCtrlC = "\u{001B}[1089::99;5u"
            #expect(matchesKey(cyrillicCtrlC, "ctrl+d") == false)
        }

        @Test("should not match wrong modifiers even with base layout")
        func noMatchWrongModifiers() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Cyrillic ctrl+с should NOT match ctrl+shift+c
            let cyrillicCtrlC = "\u{001B}[1089::99;5u"
            #expect(matchesKey(cyrillicCtrlC, "ctrl+shift+c") == false)
        }
    }

    // MARK: - Legacy key matching

    @Suite("Legacy key matching")
    struct LegacyKeyMatchingTests {

        @Test("should match legacy Ctrl+c")
        func matchLegacyCtrlC() {
            setKittyProtocolActive(false)
            // Ctrl+c sends ASCII 3 (ETX)
            #expect(matchesKey("\u{0003}", "ctrl+c") == true)
        }

        @Test("should match legacy Ctrl+d")
        func matchLegacyCtrlD() {
            setKittyProtocolActive(false)
            // Ctrl+d sends ASCII 4 (EOT)
            #expect(matchesKey("\u{0004}", "ctrl+d") == true)
        }

        @Test("should match escape key")
        func matchEscape() {
            #expect(matchesKey("\u{001B}", "escape") == true)
        }

        @Test("should match legacy linefeed as enter")
        func matchLinefeedAsEnter() {
            setKittyProtocolActive(false)
            #expect(matchesKey("\n", "enter") == true)
            #expect(parseKey("\n") == "enter")
        }

        @Test("should treat linefeed as shift+enter when kitty active")
        func linefeedAsShiftEnterWithKitty() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            #expect(matchesKey("\n", "shift+enter") == true)
            #expect(matchesKey("\n", "enter") == false)
            #expect(parseKey("\n") == "shift+enter")
        }

        @Test("should parse ctrl+space")
        func parseCtrlSpace() {
            setKittyProtocolActive(false)
            #expect(matchesKey("\u{0000}", "ctrl+space") == true)
            #expect(parseKey("\u{0000}") == "ctrl+space")
        }

        @Test("should match legacy Ctrl+symbol")
        func matchLegacyCtrlSymbol() {
            setKittyProtocolActive(false)
            // Ctrl+\ sends ASCII 28 (File Separator) in legacy terminals
            #expect(matchesKey("\u{001C}", "ctrl+\\") == true)
            #expect(parseKey("\u{001C}") == "ctrl+\\")
            // Ctrl+] sends ASCII 29 (Group Separator) in legacy terminals
            #expect(matchesKey("\u{001D}", "ctrl+]") == true)
            #expect(parseKey("\u{001D}") == "ctrl+]")
            // Ctrl+_ sends ASCII 31 (Unit Separator) in legacy terminals
            // Ctrl+- is on the same physical key on US keyboards
            #expect(matchesKey("\u{001F}", "ctrl+_") == true)
            #expect(matchesKey("\u{001F}", "ctrl+-") == true)
            #expect(parseKey("\u{001F}") == "ctrl+-")
        }

        @Test("should match legacy Ctrl+Alt+symbol")
        func matchLegacyCtrlAltSymbol() {
            setKittyProtocolActive(false)
            // Ctrl+Alt+[ sends ESC followed by ESC (Ctrl+[ = ESC)
            #expect(matchesKey("\u{001B}\u{001B}", "ctrl+alt+[") == true)
            #expect(parseKey("\u{001B}\u{001B}") == "ctrl+alt+[")
            // Ctrl+Alt+\ sends ESC followed by ASCII 28
            #expect(matchesKey("\u{001B}\u{001C}", "ctrl+alt+\\") == true)
            #expect(parseKey("\u{001B}\u{001C}") == "ctrl+alt+\\")
            // Ctrl+Alt+] sends ESC followed by ASCII 29
            #expect(matchesKey("\u{001B}\u{001D}", "ctrl+alt+]") == true)
            #expect(parseKey("\u{001B}\u{001D}") == "ctrl+alt+]")
            // Ctrl+_ sends ASCII 31 (Unit Separator) in legacy terminals
            // Ctrl+- is on the same physical key on US keyboards
            #expect(matchesKey("\u{001B}\u{001F}", "ctrl+alt+_") == true)
            #expect(matchesKey("\u{001B}\u{001F}", "ctrl+alt+-") == true)
            #expect(parseKey("\u{001B}\u{001F}") == "ctrl+alt+-")
        }

        @Test("should parse legacy alt-prefixed sequences when kitty inactive")
        func parseLegacyAltPrefixed() {
            setKittyProtocolActive(false)
            #expect(matchesKey("\u{001B} ", "alt+space") == true)
            #expect(parseKey("\u{001B} ") == "alt+space")
            #expect(matchesKey("\u{001B}\u{0008}", "alt+backspace") == true)
            #expect(parseKey("\u{001B}\u{0008}") == "alt+backspace")
            #expect(matchesKey("\u{001B}\u{0003}", "ctrl+alt+c") == true)
            #expect(parseKey("\u{001B}\u{0003}") == "ctrl+alt+c")
            #expect(matchesKey("\u{001B}B", "alt+left") == true)
            #expect(parseKey("\u{001B}B") == "alt+left")
            #expect(matchesKey("\u{001B}F", "alt+right") == true)
            #expect(parseKey("\u{001B}F") == "alt+right")
            #expect(matchesKey("\u{001B}a", "alt+a") == true)
            #expect(parseKey("\u{001B}a") == "alt+a")
            #expect(matchesKey("\u{001B}y", "alt+y") == true)
            #expect(parseKey("\u{001B}y") == "alt+y")
            #expect(matchesKey("\u{001B}z", "alt+z") == true)
            #expect(parseKey("\u{001B}z") == "alt+z")
        }

        @Test("should not parse alt-prefixed sequences when kitty active")
        func noParseAltPrefixedWithKitty() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            #expect(matchesKey("\u{001B} ", "alt+space") == false)
            #expect(parseKey("\u{001B} ") == nil)
            #expect(matchesKey("\u{001B}\u{0008}", "alt+backspace") == true)
            #expect(parseKey("\u{001B}\u{0008}") == "alt+backspace")
            #expect(matchesKey("\u{001B}\u{0003}", "ctrl+alt+c") == false)
            #expect(parseKey("\u{001B}\u{0003}") == nil)
            #expect(matchesKey("\u{001B}B", "alt+left") == false)
            #expect(parseKey("\u{001B}B") == nil)
            #expect(matchesKey("\u{001B}F", "alt+right") == false)
            #expect(parseKey("\u{001B}F") == nil)
            #expect(matchesKey("\u{001B}a", "alt+a") == false)
            #expect(parseKey("\u{001B}a") == nil)
            #expect(matchesKey("\u{001B}y", "alt+y") == false)
            #expect(parseKey("\u{001B}y") == nil)
        }

        @Test("should match arrow keys")
        func matchArrowKeys() {
            #expect(matchesKey("\u{001B}[A", "up") == true)
            #expect(matchesKey("\u{001B}[B", "down") == true)
            #expect(matchesKey("\u{001B}[C", "right") == true)
            #expect(matchesKey("\u{001B}[D", "left") == true)
        }

        @Test("should match SS3 arrows and home/end")
        func matchSS3Arrows() {
            #expect(matchesKey("\u{001B}OA", "up") == true)
            #expect(matchesKey("\u{001B}OB", "down") == true)
            #expect(matchesKey("\u{001B}OC", "right") == true)
            #expect(matchesKey("\u{001B}OD", "left") == true)
            #expect(matchesKey("\u{001B}OH", "home") == true)
            #expect(matchesKey("\u{001B}OF", "end") == true)
        }

        @Test("should match legacy function keys and clear")
        func matchFunctionKeys() {
            #expect(matchesKey("\u{001B}OP", "f1") == true)
            #expect(matchesKey("\u{001B}[24~", "f12") == true)
            #expect(matchesKey("\u{001B}[E", "clear") == true)
        }

        @Test("should match alt+arrows")
        func matchAltArrows() {
            #expect(matchesKey("\u{001B}p", "alt+up") == true)
            #expect(matchesKey("\u{001B}p", "up") == false)
        }

        @Test("should match rxvt modifier sequences")
        func matchRxvtModifiers() {
            #expect(matchesKey("\u{001B}[a", "shift+up") == true)
            #expect(matchesKey("\u{001B}Oa", "ctrl+up") == true)
            #expect(matchesKey("\u{001B}[2$", "shift+insert") == true)
            #expect(matchesKey("\u{001B}[2^", "ctrl+insert") == true)
            #expect(matchesKey("\u{001B}[7$", "shift+home") == true)
        }
    }

    // MARK: - Digit keybinding matching

    @Suite("Digit keybinding matching")
    struct DigitKeybindingTests {
        @Test("should match plain digit key")
        func matchPlainDigit() {
            setKittyProtocolActive(false)
            #expect(matchesKey("1", "1") == true)
            #expect(matchesKey("2", "2") == true)
            #expect(matchesKey("0", "0") == true)
            #expect(matchesKey("9", "9") == true)
        }

        @Test("should not match digit with modifier when plain digit expected")
        func noMatchDigitWithModifier() {
            setKittyProtocolActive(false)
            // A plain "1" keypress should not match "ctrl+1"
            #expect(matchesKey("1", "ctrl+1") == false)
        }

        @Test("should not match wrong digit")
        func noMatchWrongDigit() {
            setKittyProtocolActive(false)
            #expect(matchesKey("1", "2") == false)
            #expect(matchesKey("0", "9") == false)
        }
    }
}

// MARK: - parseKey Tests

@Suite("parseKey", .serialized)
struct ParseKeyTests {

    // MARK: - Kitty protocol with alternate keys

    @Suite("Kitty protocol with alternate keys")
    struct KittyAlternateKeysTests {

        @Test("should return Latin key name when base layout key is present")
        func returnLatinKeyWithBaseLayout() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            // Cyrillic ctrl+с with base layout 'c'
            let cyrillicCtrlC = "\u{001B}[1089::99;5u"
            #expect(parseKey(cyrillicCtrlC) == "ctrl+c")
        }

        @Test("should return key name from codepoint when no base layout")
        func returnKeyFromCodepoint() {
            setKittyProtocolActive(true)
            defer { setKittyProtocolActive(false) }
            let latinCtrlC = "\u{001B}[99;5u"
            #expect(parseKey(latinCtrlC) == "ctrl+c")
        }
    }

    // MARK: - Legacy key parsing

    @Suite("Legacy key parsing")
    struct LegacyKeyParsingTests {

        @Test("should parse legacy Ctrl+letter")
        func parseLegacyCtrlLetter() {
            setKittyProtocolActive(false)
            #expect(parseKey("\u{0003}") == "ctrl+c")
            #expect(parseKey("\u{0004}") == "ctrl+d")
        }

        @Test("should parse special keys")
        func parseSpecialKeys() {
            #expect(parseKey("\u{001B}") == "escape")
            #expect(parseKey("\t") == "tab")
            #expect(parseKey("\r") == "enter")
            setKittyProtocolActive(false)
            #expect(parseKey("\n") == "enter")
            #expect(parseKey("\u{0000}") == "ctrl+space")
            #expect(parseKey(" ") == "space")
        }

        @Test("should parse arrow keys")
        func parseArrowKeys() {
            #expect(parseKey("\u{001B}[A") == "up")
            #expect(parseKey("\u{001B}[B") == "down")
            #expect(parseKey("\u{001B}[C") == "right")
            #expect(parseKey("\u{001B}[D") == "left")
        }

        @Test("should parse SS3 arrows and home/end")
        func parseSS3Arrows() {
            #expect(parseKey("\u{001B}OA") == "up")
            #expect(parseKey("\u{001B}OB") == "down")
            #expect(parseKey("\u{001B}OC") == "right")
            #expect(parseKey("\u{001B}OD") == "left")
            #expect(parseKey("\u{001B}OH") == "home")
            #expect(parseKey("\u{001B}OF") == "end")
        }

        @Test("should parse legacy function and modifier sequences")
        func parseFunctionAndModifierSequences() {
            #expect(parseKey("\u{001B}OP") == "f1")
            #expect(parseKey("\u{001B}[24~") == "f12")
            #expect(parseKey("\u{001B}[E") == "clear")
            #expect(parseKey("\u{001B}[2^") == "ctrl+insert")
            #expect(parseKey("\u{001B}p") == "alt+up")
        }

        @Test("should parse double bracket pageUp")
        func parseDoubleBracketPageUp() {
            #expect(parseKey("\u{001B}[[5~") == "pageUp")
        }
    }
}
