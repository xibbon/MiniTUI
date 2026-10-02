import Foundation
import Testing
@testable import MiniTui

private final class V100RecordingTerminal: Terminal {
    let columns = 6
    let rows = 3
    let kittyProtocolActive = false
    var writes: [String] = []
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {}
    func stop() {}
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) { writes.append(data) }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}
}

@Suite("MiniTui v1.0.0 M1", .serialized)
@MainActor
struct M1V100Tests {
    // Port of regression-slice-by-column-ansi-order.test.ts, issue #10169.
    @Test("Keep a reset at the slice start after earlier style codes")
    func resetAtSliceStart() {
        let line = "\u{1B}[32mfoo\u{1B}[39m bar"
        #expect(sliceByColumn(line, startCol: 3, length: 4, strict: true) == "\u{1B}[32m\u{1B}[39m bar")
        let slice = sliceWithWidth(line, startCol: 3, length: 4, strict: true)
        #expect(slice.text == "\u{1B}[32m\u{1B}[39m bar")
        #expect(slice.width == 4)
    }

    @Test("Keep color out of text after a highlighted token")
    func colorAfterHighlightedToken() {
        let line = "Another \u{1B}[35malpha\u{1B}[39m line with \u{1B}[35mbeta\u{1B}[39m later."
        let after = sliceByColumn(line, startCol: 13, length: 100, strict: true)
        #expect(after == "\u{1B}[35m\u{1B}[39m line with \u{1B}[35mbeta\u{1B}[39m later.")
    }

    // Port of the new cases in autocomplete-skill-slash.test.ts, issue #10218.
    @Test("Complete commands after leading whitespace and keep it")
    func commandsAfterWhitespace() throws {
        let provider = CombinedAutocompleteProvider(commands: [SlashCommand(name: "model")])
        for (line, expected, prefix) in [
            (" /", " /model ", "/"),
            ("  /mod", "  /model ", "/mod"),
            ("\t/mod", "\t/model ", "/mod"),
        ] {
            let result = try #require(provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count))
            #expect(result.prefix == prefix)
            #expect(result.items.map(\.value) == ["model"])
            let item = try #require(result.items.first)
            let applied = provider.applyCompletion(lines: [line], cursorLine: 0, cursorCol: line.count, item: item, prefix: result.prefix)
            #expect(applied.lines[0] == expected)
            #expect(applied.cursorCol == expected.count)
        }
    }

    @Test("Complete command arguments after leading whitespace")
    func argumentsAfterWhitespace() throws {
        let provider = CombinedAutocompleteProvider(commands: [
            SlashCommand(name: "model", getArgumentCompletions: { prefix in
                #expect(prefix == "son")
                return [AutocompleteItem(value: "sonnet", label: "sonnet")]
            }),
        ])
        let line = "  /model son"
        let result = try #require(provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count))
        #expect(result.prefix == "son")
        let item = try #require(result.items.first)
        let applied = provider.applyCompletion(lines: [line], cursorLine: 0, cursorCol: line.count, item: item, prefix: result.prefix)
        #expect(applied.lines[0] == "  /model sonnet")
        #expect(applied.cursorCol == "  /model sonnet".count)
    }

    @Test("Use JavaScript leading whitespace rules without trimming arguments")
    func commandWhitespaceRules() throws {
        let provider = CombinedAutocompleteProvider(commands: [SlashCommand(name: "model")])
        for whitespace in ["\u{00A0}", "\u{3000}", "\u{FEFF}"] {
            let line = whitespace + "/mod"
            let result = try #require(provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count))
            #expect(result.prefix == "/mod")
            let item = try #require(result.items.first)
            let applied = provider.applyCompletion(lines: [line], cursorLine: 0, cursorCol: line.count, item: item, prefix: result.prefix)
            #expect(applied.lines == [whitespace + "/model "])
        }
        let notWhitespace = "\u{0085}/mod"
        #expect(provider.getSuggestions(lines: [notWhitespace], cursorLine: 0, cursorCol: notWhitespace.count) == nil)

        let arguments = CombinedAutocompleteProvider(commands: [
            SlashCommand(name: "model", getArgumentCompletions: { prefix in
                #expect(prefix == "son ")
                return [AutocompleteItem(value: "sonnet", label: "sonnet")]
            }),
        ])
        let line = "  /model son "
        #expect(arguments.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)?.prefix == "son ")
    }

    @Test("Two Markdown components share one parse")
    func sharedMarkdownParse() throws {
        let cache = MarkdownDocumentCache.shared
        cache.removeAll()
        defer { cache.removeAll() }
        let source = "# Shared parse\n\nText with **bold** and `code`."
        let first = Markdown(source, paddingX: 1, paddingY: 1, theme: defaultMarkdownTheme)
        let second = Markdown(source, paddingX: 1, paddingY: 1, theme: defaultMarkdownTheme)
        let firstLines = first.render(width: 40)
        let firstEntry = try #require(cache.cachedDocument(for: source))
        #expect(second.render(width: 40) == firstLines)
        let secondEntry = try #require(cache.cachedDocument(for: source))
        #expect(firstEntry === secondEntry)
        _ = second.render(width: 20)
        #expect(cache.cachedDocument(for: source) === firstEntry)
    }

    @Test("Markdown cache keys use normalized source")
    func normalizedMarkdownCacheKey() throws {
        let cache = MarkdownDocumentCache.shared
        cache.removeAll()
        defer { cache.removeAll() }
        let source = "Text\twith **style**."
        let normalized = "Text   with **style**."
        let first = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
        let second = Markdown(normalized, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme)
        let lines = first.render(width: 40)
        let entry = try #require(cache.cachedDocument(for: normalized))
        #expect(cache.cachedDocument(for: source) == nil)
        #expect(second.render(width: 40) == lines)
        #expect(cache.cachedDocument(for: normalized) === entry)
    }

    @Test("Markdown output stays the same after the parse cache is emptied")
    func emptyMarkdownCacheOutput() throws {
        let cache = MarkdownDocumentCache.shared
        cache.removeAll()
        defer { cache.removeAll() }
        let source = "# Heading\n\n**Bold**, *italic*, ~~strike~~ and `code`.\n\n- Item\n  - Child\n\n```swift\nlet x = 1\n```\n\n| A | B |\n|---|---|\n| long value | other |"
        let component = Markdown(source, paddingX: 1, paddingY: 1, theme: defaultMarkdownTheme)
        for width in [20, 60] {
            let warm = component.render(width: width)
            let oldEntry = try #require(cache.cachedDocument(for: source))
            cache.removeAll()
            #expect(cache.cachedDocument(for: source) == nil)
            component.invalidate()
            #expect(component.render(width: width) == warm)
            let newEntry = try #require(cache.cachedDocument(for: source))
            #expect(newEntry !== oldEntry)
        }
    }

    @Test("Screen lines are a copy of the last written frame")
    func screenLinesCopy() {
        let terminal = V100RecordingTerminal()
        let renderer = AltScreenRenderer(terminal: terminal)
        #expect(renderer.getScreenLines().isEmpty)
        renderer.start()
        defer { renderer.stop(preserveScreen: true) }
        renderer.present(.init(lines: ["\u{1B}[32mfoo\u{1B}[39m", "a\tb", "abcdefgh"], cursor: nil,
            width: 6, height: 3, clearOnShrink: false, hasOverlayEntries: false,
            hasVisibleOverlay: false, useSystemCursor: false))
        let ending = "\u{1B}[0m\u{1B}]8;;\u{7}"
        let expected = ["\u{1B}[32mfoo\u{1B}[39m" + ending, "a   b" + ending, "abcdef" + ending]
        #expect(renderer.getScreenLines() == expected)
        for (row, line) in expected.enumerated() {
            #expect(terminal.writes.last?.contains("\u{1B}[\(row + 1);1H\u{1B}[2K" + line) == true)
        }
        var copy = renderer.getScreenLines()
        copy[0] = "changed"
        copy.append("extra")
        #expect(renderer.getScreenLines() == expected)
        renderer.present(.init(lines: ["new"], cursor: nil, width: 6, height: 3,
            clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false, useSystemCursor: false))
        #expect(renderer.getScreenLines() == ["new" + ending])
        #expect(copy == ["changed", expected[1], expected[2], "extra"])
    }

    @Test("Detect Apple Terminal from an injected environment")
    func appleTerminalSession() {
        #if os(macOS)
        #expect(isAppleTerminalSession(environment: ["TERM_PROGRAM": "Apple_Terminal"]))
        #else
        #expect(!isAppleTerminalSession(environment: ["TERM_PROGRAM": "Apple_Terminal"]))
        #endif
        for environment in [[:], ["TERM_PROGRAM": "iTerm.app"], ["TERM_PROGRAM": "apple_terminal"], ["TERM_PROGRAM": "Apple_Terminal "]] {
            #expect(!isAppleTerminalSession(environment: environment))
        }
    }
}
