import Foundation
import Testing
@testable import MiniTui

private final class M1CountingProvider: AutocompleteProvider {
    let triggerCharacters: [String] = ["@", "#"]
    private(set) var requests: [String] = []

    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int, signal: CancellationSignal?) -> (items: [AutocompleteItem], prefix: String)? {
        let line = lines[cursorLine].prefixCharacters(cursorCol)
        requests.append(line)
        return ([AutocompleteItem(value: "choice", label: "choice")], line)
    }

    func applyCompletion(lines: [String], cursorLine: Int, cursorCol: Int, item: AutocompleteItem, prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        (lines, cursorLine, cursorCol)
    }
}

@MainActor
@Suite("M1 completion changes")
struct M1CompletionTests {
    private func folder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("m1-completion-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("skill commands match bare names while preserving inserted skill prefix")
    func bareSkillRanking() {
        let provider = CombinedAutocompleteProvider(commands: [
            SlashCommand(name: "skill:review"),
            SlashCommand(name: "reviewer"),
            SlashCommand(name: "skill:revise"),
        ])
        let bare = provider.getSuggestions(lines: ["/rev"], cursorLine: 0, cursorCol: 4)
        #expect(bare?.items.first?.value == "skill:review")
        #expect(bare?.items.contains { $0.value == "skill:revise" } == true)
        let prefixed = provider.getSuggestions(lines: ["/skill:rev"], cursorLine: 0, cursorCol: 10)
        #expect(prefixed?.items.first?.value.hasPrefix("skill:") == true)
    }

    @Test("CJK punctuation separates completion tokens; CJK letters do not")
    func cjkSeparators() {
        for character in "，．：；！？（）［］｛｝“”‘’…—。、「」『』《》【】・\u{3000}" {
            #expect(isAutocompleteSeparator(character), "\(character)")
        }
        for character in "文あカ한ㄅ𠮷々Ａ" {
            #expect(!isAutocompleteSeparator(character), "\(character)")
        }
    }

    @Test("file completion stops at CJK punctuation and quotes paths containing it")
    func pathBoundariesAndQuotes() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try "text".write(to: root.appendingPathComponent("说明.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("my，folder"), withIntermediateDirectories: true)
        try "text".write(to: root.appendingPathComponent("my，folder/说明.md"), atomically: true, encoding: .utf8)
        let provider = CombinedAutocompleteProvider(basePath: root.path)

        let line = "查看，说明"
        let boundary = provider.getForceFileSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)
        #expect(boundary?.prefix == "说明")
        #expect(boundary?.items.map(\.value) == ["说明.md"])

        let emptyPrefix = provider.getSuggestions(lines: ["查看，"], cursorLine: 0, cursorCol: 3)
        #expect(emptyPrefix?.prefix == "")
        #expect(emptyPrefix?.items.isEmpty == false)
        #expect(provider.getSuggestions(lines: [""], cursorLine: 0, cursorCol: 0) == nil)

        let quoted = "查看：\"my，folder/说\"后文"
        let beforeClosingQuote = "查看：\"my，folder/说".count
        let completion = provider.getForceFileSuggestions(lines: [quoted], cursorLine: 0, cursorCol: beforeClosingQuote)
        #expect(completion?.prefix == "\"my，folder/说")
        #expect(completion?.items.map(\.value) == ["\"my，folder/说明.md\""])
        if let item = completion?.items.first, let prefix = completion?.prefix {
            let applied = provider.applyCompletion(lines: [quoted], cursorLine: 0, cursorCol: beforeClosingQuote, item: item, prefix: prefix)
            #expect(applied.lines == ["查看：\"my，folder/说明.md\"后文"])
        }
    }

    @Test("attachment completion starts after CJK punctuation without losing prose")
    func attachmentAfterCJKPunctuation() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try "text".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let fd = root.appendingPathComponent("fd")
        try "#!/bin/sh\nprintf '%s\\n' README.md\n".write(to: fd, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fd.path)
        let provider = CombinedAutocompleteProvider(basePath: root.path, fdPath: fd.path)

        for before in ["查看，", "😀查看。", "\u{3000}"] {
            let line = before + "@REA"
            let result = provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)
            #expect(result?.prefix == "@REA")
            #expect(result?.items.map(\.value) == ["@README.md"])
            if let item = result?.items.first, let prefix = result?.prefix {
                let applied = provider.applyCompletion(lines: [line], cursorLine: 0, cursorCol: line.count, item: item, prefix: prefix)
                #expect(applied.lines == [before + "@README.md "])
                #expect(applied.cursorCol == (before + "@README.md ").count)
            }
        }

        for before in ["user", "查看", "あ", "カ", "한", "ㄅ", "𠮷", "々", "Ａ"] {
            let line = before + "@REA"
            #expect(provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count) == nil)
        }
    }

    @Test("quoted directories remain ahead of files")
    func quotedDirectoryOrder() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("z，folder"), withIntermediateDirectories: true)
        try "text".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let provider = CombinedAutocompleteProvider(basePath: root.path)
        let result = provider.getForceFileSuggestions(lines: [""], cursorLine: 0, cursorCol: 0)
        #expect(result?.items.map(\.label) == ["z，folder/", "a.txt"])
        #expect(result?.items.first?.value == "\"z，folder/\"")
    }

    @Test("editor triggers symbols after CJK punctuation and refreshes after CJK letters")
    func editorSymbolTriggers() async {
        for symbol in ["@", "#"] {
            let provider = M1CountingProvider()
            let editor = Editor(theme: defaultEditorTheme)
            editor.setAutocompleteProvider(provider)
            editor.setText("查看，")
            editor.handleInput(symbol)
            try? await Task.sleep(for: .milliseconds(60))
            #expect(provider.requests == ["查看，\(symbol)"])
            editor.handleInput("文")
            try? await Task.sleep(for: .milliseconds(60))
            #expect(provider.requests.last == "查看，\(symbol)文")
        }
    }

    @Test("editor does not trigger symbols after CJK letters")
    func editorDoesNotTriggerInsideCJKWord() async {
        let provider = M1CountingProvider()
        let editor = Editor(theme: defaultEditorTheme)
        editor.setAutocompleteProvider(provider)
        editor.setText("查看")
        editor.handleInput("@")
        editor.handleInput("文")
        try? await Task.sleep(for: .milliseconds(60))
        #expect(provider.requests.isEmpty)
    }

    @Test("long fuzzy matches preserve scores and stable ties")
    func longFuzzyScoresAndTies() {
        let longText = String(repeating: "a", count: 200_000) + "z"
        let match = fuzzyMatch("z", longText)
        #expect(match == FuzzyMatch(matches: true, score: 20_000))
        let values = fuzzyFilter(["abc", "abc", "axbc"], query: "abc") { $0 }
        #expect(values == ["abc", "abc", "axbc"])
    }
}
