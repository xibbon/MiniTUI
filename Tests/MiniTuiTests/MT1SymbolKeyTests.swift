import Testing
@testable import MiniTui

@Suite("MT1 symbol keys", .serialized)
struct MT1SymbolKeyTests {
    // Source: pi-mono v1.3.0, packages/tui/test/keys.test.ts:137-145.
    @Test("Match shifted symbols by their produced character")
    func matchProducedSymbols() {
        #expect(matchesKey("\u{001B}[61:43;2u", "+"))
        #expect(matchesKey("\u{001B}[61:43;2u", "shift+="))
        #expect(parseKey("\u{001B}[61:43;2u") == "+")
        #expect(matchesKey("\u{001B}[61:43;6u", "ctrl++"))
        #expect(parseKey("\u{001B}[61:43;6u") == "ctrl++")
    }

    @Test("Keep Ctrl, Alt, and Super on produced symbols")
    func keepModifiers() {
        // Use an explicit mode because other test suites change the global mode.
        for modifier in stride(from: 0, through: 14, by: 2) {
            var names: [String] = []
            if modifier & 4 != 0 { names.append("ctrl") }
            if modifier & 2 != 0 { names.append("alt") }
            if modifier & 8 != 0 { names.append("super") }
            let keyId = (names + ["+"]).joined(separator: "+")
            let data = "\u{001B}[61:43;\(modifier + 2)u"
            #expect(matchesKey(data, keyId, kittyActive: true))
            #expect(parseKey(data) == keyId)
            let xtermData = "\u{001B}[27;\(modifier + 2);43~"
            #expect(matchesKey(xtermData, keyId, kittyActive: true))
            #expect(parseKey(xtermData) == keyId)
            #expect(!matchesKey(data, "ctrl+shift+alt+super++", kittyActive: true))
            #expect(matchesKey(xtermData, "ctrl+shift+alt+super++", kittyActive: true) == (modifier == 14))
        }
    }

    @Test("Match each xterm shifted symbol with its produced character")
    func matchXtermSymbols() {
        for symbol in "~!@#$%^&*()_+|{}:<>?".unicodeScalars {
            let key = String(symbol)
            let shifted = "\u{001B}[27;2;\(symbol.value)~"
            let ctrlShifted = "\u{001B}[27;6;\(symbol.value)~"
            #expect(matchesKey(shifted, key))
            #expect(matchesKey(shifted, "shift+" + key))
            #expect(parseKey(shifted) == key)
            #expect(matchesKey(ctrlShifted, "ctrl+" + key))
            #expect(matchesKey(ctrlShifted, "ctrl+shift+" + key))
            #expect(parseKey(ctrlShifted) == "ctrl+" + key)
        }
    }

    @Test("Keep Shift when xterm reports a symbol outside its shifted set")
    func keepExplicitShift() {
        #expect(matchesKey("\u{001B}[27;2;47~", "shift+/"))
        #expect(!matchesKey("\u{001B}[27;2;47~", "/"))
        #expect(parseKey("\u{001B}[27;2;47~") == "shift+/")
        #expect(parseKey("\u{001B}[27;6;69~") == "shift+ctrl+e")
    }

    @Test("Keep physical keys when a shifted symbol is absent")
    func keepPhysicalKeys() {
        #expect(matchesKey("\u{001B}[61;2u", "shift+="))
        #expect(!matchesKey("\u{001B}[61;2u", "+"))
        #expect(parseKey("\u{001B}[61;2u") == "shift+=")
        #expect(!matchesKey("\u{001B}[61:43;1u", "+"))
        #expect(parseKey("\u{001B}[61:43;1u") == "=")
    }

    @Test("Keep lock masks, release events, and base layout rules")
    func keepKittyRules() {
        let data = "\u{001B}[61:43:93;198:3u"
        #expect(matchesKey(data, "ctrl++"))
        #expect(matchesKey(data, "shift+ctrl+="))
        #expect(!matchesKey(data, "shift+ctrl+]"))
        #expect(parseKey(data) == "ctrl++")
        #expect(matchesKey("\u{001B}[1089::99;5:3u", "ctrl+c"))
        #expect(parseKey("\u{001B}[1089::99;5:3u") == "ctrl+c")
    }

    @Test("Keep Super aliases for plus keys")
    func keepSuperAliases() {
        for name in ["super", "cmd", "meta"] {
            #expect(matchesKey("\u{001B}[61:43;14u", "ctrl+" + name + "++", kittyActive: true))
            #expect(matchesKey("\u{001B}[61:43;14u", name + "+shift+ctrl+=", kittyActive: true))
            #expect(matchesKey("\u{001B}[27;14;43~", "ctrl+" + name + "++", kittyActive: true))
            #expect(matchesKey("\u{001B}[27;14;43~", name + "+shift+ctrl++", kittyActive: true))
        }
        #expect(parseKey("\u{001B}[61:43;14u") == "ctrl+super++")
    }

    @Test("Reject repeated modifiers and invalid plus suffixes")
    func rejectInvalidPrefixes() {
        for keyId in [
            "ctrl+ctrl++", "shift+shift+=", "alt+alt++", "super+super++",
            "cmd+meta++", "meta+super++", "cmd+cmd++", "ctrl+", "shift+",
            "ctrl+++", "++", "ctrl+unknown++", "unknown+ctrl++", "+ctrl",
        ] {
            #expect(!matchesKey("+", keyId))
            #expect(!matchesKey("\u{001B}[61:43;6u", keyId))
            #expect(!matchesKey("\u{001B}[27;6;43~", keyId))
        }
        for (data, keyId) in [
            ("\u{001B}[97;5u", "ctrl+ctrl+a"),
            ("\u{001B}[61;2u", "shift+shift+="),
            ("\u{001B}[43;3u", "alt+alt++"),
            ("\u{001B}[43;9u", "super+super++"),
            ("\u{001B}[43;9u", "cmd+meta++"),
            ("\u{001B}[43;9u", "meta+super++"),
        ] {
            #expect(!matchesKey(data, keyId))
        }
        #expect(matchesKey("\u{001B}[61:43;8u", "alt+ctrl++"))
        #expect(matchesKey("\u{001B}[61:43;8u", "CTRL+ALT++"))
    }
}
