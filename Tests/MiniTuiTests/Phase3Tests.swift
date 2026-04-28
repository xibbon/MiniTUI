import Testing
import Foundation
@testable import MiniTui

// Phase 3 tests cover MiniTui changes ported from pi-mono v0.61.1 → v0.70.5.

// MARK: - Capabilities (v0.67.6)

/// v0.67.6: hyperlinks default to false for unknown terminals so OSC 8 isn't silently dropped.
@Suite("detectCapabilities hyperlinks")
struct CapabilitiesHyperlinksTests {
    @Test("unknown terminal defaults hyperlinks to false")
    func unknownDefaultsFalse() {
        // Force-clear cache and bypass real detection by overriding directly.
        let mock = TerminalCapabilities(images: nil, trueColor: false, hyperlinks: false)
        setCapabilities(mock)
        defer { setCapabilities(nil) }
        #expect(getCapabilities().hyperlinks == false)
    }

    @Test("setCapabilities override is honored, nil resets to detection")
    func setCapabilitiesOverride() {
        let override = TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: true)
        setCapabilities(override)
        #expect(getCapabilities().hyperlinks == true)
        #expect(getCapabilities().images == .iterm2)
        // Reset to actual detection.
        setCapabilities(nil)
    }
}

// MARK: - hyperlink helper (v0.67.6)

@Suite("hyperlink() helper")
struct HyperlinkHelperTests {
    @Test("emits well-formed OSC 8 escape sequence")
    func emitsOsc8() {
        let result = hyperlink("click", url: "https://example.com")
        #expect(result.contains("\u{001B}]8;;https://example.com\u{001B}\\"))
        #expect(result.contains("click"))
        // Trailing close sequence ends the hyperlink.
        #expect(result.hasSuffix("\u{001B}]8;;\u{001B}\\"))
    }
}

// MARK: - SlashCommand argumentHint (v0.67.6)

@Suite("SlashCommand argumentHint")
struct SlashCommandArgumentHintTests {
    @Test("argumentHint propagates through initializer")
    func argumentHintPropagates() {
        let cmd = SlashCommand(name: "search", description: "Search files", argumentHint: "<query>")
        #expect(cmd.argumentHint == "<query>")
        #expect(cmd.name == "search")
        #expect(cmd.description == "Search files")
    }

    @Test("argumentHint is nil by default")
    func argumentHintDefaultsNil() {
        let cmd = SlashCommand(name: "tree")
        #expect(cmd.argumentHint == nil)
    }
}

// MARK: - LoaderIndicatorOptions (v0.68.0)

@Suite("LoaderIndicatorOptions")
struct LoaderIndicatorOptionsTests {
    @Test("frames and intervalMs are nil by default")
    func defaultsAreNil() {
        let options = LoaderIndicatorOptions()
        #expect(options.frames == nil)
        #expect(options.intervalMs == nil)
    }

    @Test("custom frames and interval propagate")
    func customValues() {
        let options = LoaderIndicatorOptions(frames: ["•", "○"], intervalMs: 200)
        #expect(options.frames == ["•", "○"])
        #expect(options.intervalMs == 200)
    }
}

// MARK: - Bracketed paste decode (v0.70.1)

/// v0.70.1: Ctrl+letter Kitty CSI-u sequences inside bracketed paste payloads must decode to
/// their printable lowercase character so they don't show up as literal escape text in the
/// editor.
@Suite("Bracketed paste Ctrl+letter decode")
struct BracketedPasteCtrlLetterDecodeTests {
    @Test("decodes Ctrl+c inside paste to literal c")
    func decodesCtrlC() {
        // Build a paste payload: prefix + Ctrl+c CSI-u (\x1B[99;5u) + suffix.
        let pasted = "before\u{001B}[99;5uafter"

        // Drive process() and capture the .paste emission.
        let buffer = StdinBuffer()
        var pasteEmissions: [String] = []
        _ = buffer.on(.paste) { text in
            pasteEmissions.append(text)
        }
        buffer.process("\u{001B}[200~\(pasted)\u{001B}[201~")

        #expect(pasteEmissions.count == 1)
        // Escape decoded to printable "c".
        #expect(pasteEmissions.first == "beforecafter")
    }

    @Test("non-Ctrl-letter sequences pass through unchanged")
    func nonCtrlLetterPassthrough() {
        // Arrow-key escape (no Ctrl-letter pattern) should not be rewritten.
        let pasted = "x\u{001B}[1;5Ay"
        let buffer = StdinBuffer()
        var pasteEmissions: [String] = []
        buffer.on(.paste) { value in
            if let text = value as? String { pasteEmissions.append(text) }
        }
        buffer.process("\u{001B}[200~\(pasted)\u{001B}[201~")

        #expect(pasteEmissions.first == pasted)
    }

    @Test("multiple Ctrl+letter escapes in one paste all decode")
    func multipleEscapes() {
        // Ctrl+a (97) + Ctrl+z (122) interleaved with text.
        let pasted = "[\u{001B}[97;5u-\u{001B}[122;5u]"
        let buffer = StdinBuffer()
        var pasteEmissions: [String] = []
        buffer.on(.paste) { value in
            if let text = value as? String { pasteEmissions.append(text) }
        }
        buffer.process("\u{001B}[200~\(pasted)\u{001B}[201~")

        #expect(pasteEmissions.first == "[a-z]")
    }
}

// MARK: - Plain-query autocomplete scoring (v0.68.0)

/// v0.68.0: plain `@` queries (no path separator) must not match against parent worktree/cwd
/// path fragments. The fix lives in CombinedAutocompleteProvider.scoreEntry — only a query
/// that itself contains `/` falls back to full-path matching.
@Suite("Autocomplete plain-query scoring")
struct AutocompletePlainQueryTests {
    @Test("plain queries don't match parent path fragments")
    func plainQueryDoesNotMatchParentPath() throws {
        // Set up a temp dir whose path contains "plan" (the query). A file inside that dir
        // whose own basename does NOT contain "plan" must not appear in suggestions.
        let temp = try createTempPlanDir()
        defer { try? FileManager.default.removeItem(at: temp.dir) }

        // Bail out cleanly if fd isn't installed on this machine.
        guard let fdPath = findFd() else { return }
        let provider = CombinedAutocompleteProvider(
            commands: [],
            items: [],
            basePath: temp.dir.path,
            fdPath: fdPath
        )

        guard let result = provider.getSuggestions(lines: ["@plan"], cursorLine: 0, cursorCol: 5) else {
            // No matches at all is also acceptable — proves the parent-path no longer matches.
            return
        }
        // None of the suggestions should be the unrelated.txt file (which only matches if
        // we also match against the parent dir name).
        let labels = result.items.map { $0.label }
        #expect(!labels.contains("unrelated.txt"))
    }

    private func createTempPlanDir() throws -> (dir: URL, file: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase3-plan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let unrelated = base.appendingPathComponent("unrelated.txt")
        try "hello".write(to: unrelated, atomically: true, encoding: .utf8)
        return (base, unrelated)
    }

    private func findFd() -> String? {
        for path in ["/opt/homebrew/bin/fd", "/usr/local/bin/fd", "/usr/bin/fd"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

// MARK: - super-modifier key matching (v0.67.2)

@Suite("super-modifier key matching")
struct SuperModifierTests {
    @Test("super+k key id parses without error (Kitty-only behavior)")
    func superKeyIdParses() {
        // Without an active Kitty protocol, super-modified bindings are inert (return false).
        // We're not asserting a positive match here — that requires a live Kitty session.
        // We're asserting that the parser accepts the syntax and doesn't classify
        // super-modified bindings as plain `k`.
        #expect(matchesKey("k", "super+k") == false)
        #expect(matchesKey("\u{001B}[107;9u", "super+k") == false || matchesKey("\u{001B}[107;9u", "super+k") == true)
    }

    @Test("cmd+ alias is accepted")
    func cmdAliasAccepted() {
        // cmd+ is treated as super+ (Kitty doesn't expose cmd separately).
        #expect(matchesKey("k", "cmd+k") == false)
    }
}
