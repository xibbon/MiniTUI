import Foundation
import Testing
import MiniTui

@MainActor
@Test("extracts / from 'hey /' when forced")
func extractsRootPrefix() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["hey /"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 5)
    #expect(result != nil)
    #expect(result?.prefix == "/")
}

@MainActor
@Test("extracts /A from '/A' when forced")
func extractsAbsolutePrefix() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["/A"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 2)
    if let result {
        #expect(result.prefix == "/A")
    }
}

@MainActor
@Test("does not trigger for slash commands")
func doesNotTriggerForSlashCommands() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["/model"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 6)
    #expect(result == nil)
}

@MainActor
@Test("triggers for absolute paths after slash command argument")
func triggersForAbsolutePathsInArgs() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["/command /"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 10)
    #expect(result != nil)
    #expect(result?.prefix == "/")
}

@MainActor
@Test("scopes fuzzy @ search to path prefixes")
func scopesFuzzyAtSearchToPathPrefix() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mt-autocomplete-\(UUID().uuidString)")
    let cwd = root.appendingPathComponent("cwd")
    let outside = root.appendingPathComponent("outside")
    try FileManager.default.createDirectory(at: cwd, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let fdScriptPath = root.appendingPathComponent("fake-fd.sh").path
    let script = """
    #!/usr/bin/env bash
    base=""
    query=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --base-directory)
          base="$2"; shift 2
          ;;
        --max-results|--type|--exclude)
          shift 2
          ;;
        --full-path|--hidden)
          shift
          ;;
        *)
          query="$1"; shift
          ;;
      esac
    done

    if [[ "$base" == */outside ]]; then
      for path in "nested/alpha.ts" "nested/deeper/also-alpha.ts" "nested/deeper/zzz.ts"; do
        if [[ -z "$query" || "$path" == *"$query"* ]]; then
          echo "$path"
        fi
      done
    fi
    """
    try script.write(toFile: fdScriptPath, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fdScriptPath)

    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: cwd.path, fdPath: fdScriptPath)
    let line = "@../outside/a"
    let result = provider.getSuggestions(lines: [line], cursorLine: 0, cursorCol: line.count)
    let values = result?.items.map(\.value) ?? []

    #expect(values.contains("@../outside/nested/alpha.ts"))
    #expect(values.contains("@../outside/nested/deeper/also-alpha.ts"))
    #expect(!values.contains("@../outside/nested/deeper/zzz.ts"))
}
