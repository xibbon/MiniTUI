import Foundation
import Testing
@testable import MiniTui

@Suite("MT1 Rex capabilities")
struct MT1RexCapabilityTests {
    @Test("Rex supports Kitty images, truecolor, and hyperlinks with or without Kitty variables")
    func rexCapabilities() {
        // Keep the upstream v1.4.0 vector and a clean environment.
        for environment in [
            ["TERM_PROGRAM": "rex", "TERM": "xterm-256color", "KITTY_WINDOW_ID": "1"],
            ["TERM_PROGRAM": "rex", "TERM": "xterm-256color"],
            ["TERM_PROGRAM": "ReX"],
        ] {
            let capabilities = detectCapabilities(environment: environment)
            #expect(capabilities.images == .kitty)
            #expect(capabilities.trueColor)
            #expect(capabilities.hyperlinks)
        }
        #expect(!detectCapabilities(environment: ["TERM_PROGRAM": "rex", "PI_HYPERLINKS": "0"]).hyperlinks)
    }

    @Test("Rex uses multiplexer limits before terminal capabilities")
    func rexMultiplexers() {
        for hints in [
            ["TMUX": "/tmp/tmux"], ["STY": "session"],
            ["TERM": "tmux-256color"], ["TERM": "screen-256color"],
        ] {
            let environment = hints.merging(["TERM_PROGRAM": "rex", "KITTY_WINDOW_ID": "1"]) { _, value in value }
            let capabilities = detectCapabilities(environment: environment)
            #expect(capabilities.images == nil)
            #expect(!capabilities.trueColor)
            #expect(!capabilities.hyperlinks)
            let withColorHint = detectCapabilities(environment: environment.merging(["COLORTERM": "truecolor"]) { _, value in value })
            #expect(withColorHint.trueColor)
        }
        let forwarded = detectCapabilities(environment: ["TERM_PROGRAM": "rex", "TMUX": "/tmp/tmux"], tmuxForwardsHyperlink: { true })
        #expect(forwarded.images == nil)
        #expect(forwarded.hyperlinks)
    }

    @Test("Rex environment overrides take priority over terminal and multiplexer limits")
    func rexOverrides() {
        let disabled = detectCapabilities(environment: [
            "TERM_PROGRAM": "rex", "PI_IMAGE_PROTOCOL": "none", "PI_TRUE_COLOR": "0", "PI_HYPERLINKS": "0",
        ])
        #expect(disabled.images == nil)
        #expect(!disabled.trueColor)
        #expect(!disabled.hyperlinks)
        var didProbe = false
        let enabled = detectCapabilities(environment: [
            "TERM_PROGRAM": "rex", "TMUX": "/tmp/tmux", "PI_IMAGE_PROTOCOL": "iterm2",
            "PI_TRUE_COLOR": "1", "PI_HYPERLINKS": "1",
        ], tmuxForwardsHyperlink: { didProbe = true; return false })
        #expect(enabled.images == .iterm2)
        #expect(enabled.trueColor)
        #expect(enabled.hyperlinks)
        #expect(!didProbe)
    }
}

@MainActor
@Suite("MT1 literal fd queries")
struct MT1LiteralFdQueryTests {
    @Test("fd matches the exact upstream literal query vectors")
    func literalQueries() throws {
        let fixture = try MT1FdFixture(files: ["pages/[id].tsx", "pages/(group).ts", "pages/index.tsx"])
        defer { fixture.remove() }
        let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: fixture.base.path, fdPath: fixture.executable.path)
        for (line, expected, query, searchBase) in [
            ("@pages/[", "@pages/[id].tsx", #"\["#, fixture.base.appendingPathComponent("pages").path),
            ("@pages/(", "@pages/(group).ts", #"\("#, fixture.base.appendingPathComponent("pages").path),
            ("@[id", "@pages/[id].tsx", #"\[id"#, fixture.base.path),
        ] {
            try "".write(to: fixture.calls, atomically: true, encoding: .utf8)
            let result = provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)
            #expect(result?.items.map(\.value) == [expected])
            // Check both searches, the existing directory scope, and --full-path.
            let calls = try fixture.recordedCalls()
            #expect(calls == ["\(searchBase)\t1\t1\t\(query)", "\(searchBase)\t\t1\t\(query)"])
        }
    }

    @Test("fd arguments escape each regex metacharacter while ranking uses the original query")
    func allMetacharacters() throws {
        let query = #"a.*+?^${}()|[]\"#
        let fixture = try MT1FdFixture(files: [query, "ordinary.txt"])
        defer { fixture.remove() }
        let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: fixture.base.path, fdPath: fixture.executable.path)
        let line = "@" + query
        let result = provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)
        #expect(result?.items.map(\.value) == [line])
        let escaped = #"a\.\*\+\?\^\$\{\}\(\)\|\[\]\\"#
        let calls = try fixture.recordedCalls()
        #expect(calls == ["\(fixture.base.path)\t1\t1\t\(escaped)", "\(fixture.base.path)\t\t1\t\(escaped)"])
    }
}

private struct MT1FdFixture {
    let root: URL
    let base: URL
    let executable: URL
    let calls: URL

    init(files: [String]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mt1-fd-\(UUID().uuidString)")
        base = root.appendingPathComponent("cwd")
        executable = root.appendingPathComponent("fake-fd.sh")
        calls = root.appendingPathComponent("calls")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        for file in files {
            let url = base.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "x".write(to: url, atomically: true, encoding: .utf8)
        }
        // Use Bash's regex engine so that a raw '[' or '(' query fails.
        let script = #"""
        #!/bin/bash
        base=""
        query=""
        depth=""
        full_path=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            --base-directory) base="$2"; shift 2 ;;
            --max-depth) depth="$2"; shift 2 ;;
            --max-results|--type|--exclude) shift 2 ;;
            --full-path) full_path=1; shift ;;
            --follow|--hidden) shift ;;
            *) query="$1"; shift ;;
          esac
        done
        printf '%s\t%s\t%s\t%s\n' "$base" "$depth" "$full_path" "$query" >> "$(dirname "$0")/calls"
        while IFS= read -r path; do
          relative="${path#"${base%/}"/}"
          if [[ "$depth" == 1 && "$relative" == */* ]]; then continue; fi
          if [[ -z "$query" || "$relative" =~ $query ]]; then
            printf '%s\n' "$relative"
          fi
        done < <(/usr/bin/find "${base%/}" -type f)
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func recordedCalls() throws -> [String] {
        try String(contentsOf: calls, encoding: .utf8).split(separator: "\n").map { line in
            var fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            // Foundation can preserve a final slash on a directory argument.
            fields[0] = URL(fileURLWithPath: fields[0]).standardizedFileURL.path
            return fields.joined(separator: "\t")
        }
    }
}
