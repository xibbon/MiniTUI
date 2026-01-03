import Testing
import MiniTui

@Test("extracts / from 'hey /' when forced")
func extractsRootPrefix() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["hey /"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 5)
    #expect(result != nil)
    #expect(result?.prefix == "/")
}

@Test("extracts /A from '/A' when forced")
func extractsAbsolutePrefix() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["/A"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 2)
    if let result {
        #expect(result.prefix == "/A")
    }
}

@Test("does not trigger for slash commands")
func doesNotTriggerForSlashCommands() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["/model"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 6)
    #expect(result == nil)
}

@Test("triggers for absolute paths after slash command argument")
func triggersForAbsolutePathsInArgs() {
    let provider = CombinedAutocompleteProvider(commands: [], items: [], basePath: "/tmp")
    let lines = ["/command /"]
    let result = provider.getForceFileSuggestions(lines: lines, cursorLine: 0, cursorCol: 10)
    #expect(result != nil)
    #expect(result?.prefix == "/")
}
