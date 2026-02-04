import Foundation

private let pathDelimiters: Set<Character> = [" ", "\t", "\"", "'", "="]

private func findLastDelimiter(_ text: String) -> Int {
    guard !text.isEmpty else { return -1 }
    let chars = Array(text)
    for i in stride(from: chars.count - 1, through: 0, by: -1) {
        if pathDelimiters.contains(chars[i]) {
            return i
        }
    }
    return -1
}

private func findUnclosedQuoteStart(_ text: String) -> Int? {
    let chars = Array(text)
    var inQuotes = false
    var quoteStart = -1
    for i in 0..<chars.count {
        if chars[i] == "\"" {
            inQuotes.toggle()
            if inQuotes {
                quoteStart = i
            }
        }
    }
    return inQuotes ? quoteStart : nil
}

private func isTokenStart(_ text: String, _ index: Int) -> Bool {
    if index == 0 { return true }
    let chars = Array(text)
    return pathDelimiters.contains(chars[index - 1])
}

private func substring(_ text: String, from offset: Int) -> String {
    let idx = text.index(text.startIndex, offsetBy: max(0, offset))
    return String(text[idx...])
}

private func extractQuotedPrefix(_ text: String) -> String? {
    guard let quoteStart = findUnclosedQuoteStart(text) else { return nil }
    let chars = Array(text)
    if quoteStart > 0, chars[quoteStart - 1] == "@" {
        guard isTokenStart(text, quoteStart - 1) else { return nil }
        return substring(text, from: quoteStart - 1)
    }
    guard isTokenStart(text, quoteStart) else { return nil }
    return substring(text, from: quoteStart)
}

private func parsePathPrefix(_ prefix: String) -> (rawPrefix: String, isAtPrefix: Bool, isQuotedPrefix: Bool) {
    if prefix.hasPrefix("@\"") {
        return (String(prefix.dropFirst(2)), true, true)
    }
    if prefix.hasPrefix("\"") {
        return (String(prefix.dropFirst(1)), false, true)
    }
    if prefix.hasPrefix("@") {
        return (String(prefix.dropFirst(1)), true, false)
    }
    return (prefix, false, false)
}

private func buildCompletionValue(
    _ path: String,
    isAtPrefix: Bool,
    isQuotedPrefix: Bool
) -> String {
    let needsQuotes = isQuotedPrefix || path.contains(" ")
    let prefix = isAtPrefix ? "@" : ""
    if !needsQuotes {
        return "\(prefix)\(path)"
    }
    return "\(prefix)\"\(path)\""
}

private func walkDirectoryWithFd(
    baseDir: String,
    fdPath: String,
    query: String,
    maxResults: Int
) -> [(path: String, isDirectory: Bool)] {
    var args = ["--base-directory", baseDir, "--max-results", String(maxResults), "--type", "f", "--type", "d", "--full-path"]
    if !query.isEmpty {
        args.append(query)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: fdPath)
    process.arguments = args

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    do {
        try process.run()
    } catch {
        return []
    }

    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return []
    }

    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
        return []
    }

    let lines = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    return lines.map { line in
        let isDirectory = line.hasSuffix("/")
        return (path: line, isDirectory: isDirectory)
    }
}

/// Display item for autocomplete suggestions.
public typealias AutocompleteItem = SelectItem

/// Slash command definition used by the editor autocomplete.
public struct SlashCommand {
    /// Command name without the leading slash.
    public let name: String
    /// Optional description shown in the list.
    public let description: String?
    /// Optional provider for argument completions.
    public let getArgumentCompletions: ((String) -> [AutocompleteItem]?)?

    /// Create a slash command.
    public init(name: String, description: String? = nil, getArgumentCompletions: ((String) -> [AutocompleteItem]?)? = nil) {
        self.name = name
        self.description = description
        self.getArgumentCompletions = getArgumentCompletions
    }
}

/// Provider interface for editor autocomplete suggestions.
public protocol AutocompleteProvider {
    /// Return suggestions and the prefix that should be replaced, or nil for none.
    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> (items: [AutocompleteItem], prefix: String)?
    /// Apply a chosen completion and return updated text and cursor.
    func applyCompletion(lines: [String], cursorLine: Int, cursorCol: Int, item: AutocompleteItem, prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int)
}

/// Autocomplete provider that combines slash commands and file suggestions.
public final class CombinedAutocompleteProvider: AutocompleteProvider {
    private let commands: [Command]
    private let basePath: String
    private let fdPath: String?

    private enum Command {
        case slash(SlashCommand)
        case item(AutocompleteItem)

        var name: String {
            switch self {
            case .slash(let command):
                return command.name
            case .item(let item):
                return item.value
            }
        }

        var label: String {
            switch self {
            case .slash(let command):
                return command.name
            case .item(let item):
                return item.label
            }
        }

        var description: String? {
            switch self {
            case .slash(let command):
                return command.description
            case .item(let item):
                return item.description
            }
        }

        var argumentCompletions: ((String) -> [AutocompleteItem]?)? {
            switch self {
            case .slash(let command):
                return command.getArgumentCompletions
            case .item:
                return nil
            }
        }
    }

    /// Create a combined provider with commands, static items, and file lookup settings.
    public init(commands: [SlashCommand] = [], items: [AutocompleteItem] = [], basePath: String = FileManager.default.currentDirectoryPath, fdPath: String? = nil) {
        self.commands = commands.map { .slash($0) } + items.map { .item($0) }
        self.basePath = basePath
        self.fdPath = fdPath
    }

    /// Return suggestions for the current cursor position, if any.
    public func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> (items: [AutocompleteItem], prefix: String)? {
        let currentLine = lines[safe: cursorLine] ?? ""
        let textBeforeCursor = currentLine.substring(from: 0, length: cursorCol)

        if let atPrefix = extractAtPrefix(textBeforeCursor) {
            let parsed = parsePathPrefix(atPrefix)
            let suggestions = getFuzzyFileSuggestions(query: parsed.rawPrefix, isQuotedPrefix: parsed.isQuotedPrefix)
            if suggestions.isEmpty { return nil }
            return (suggestions, atPrefix)
        }

        if textBeforeCursor.hasPrefix("/") {
            if let spaceIndex = textBeforeCursor.firstIndex(of: " ") {
                let commandName = String(textBeforeCursor[textBeforeCursor.index(after: textBeforeCursor.startIndex)..<spaceIndex])
                let argumentText = String(textBeforeCursor[textBeforeCursor.index(after: spaceIndex)...])
                guard let command = commands.first(where: { $0.name == commandName }), let completions = command.argumentCompletions else {
                    return nil
                }
                guard let suggestions = completions(argumentText), !suggestions.isEmpty else {
                    return nil
                }
                return (suggestions, argumentText)
            } else {
                let prefix = String(textBeforeCursor.dropFirst())
                let filtered = fuzzyFilter(commands, query: prefix) { $0.name }
                if filtered.isEmpty { return nil }
                let items = filtered.map { command in
                    AutocompleteItem(value: command.name, label: command.label, description: command.description)
                }
                return (items, textBeforeCursor)
            }
        }

        if let pathPrefix = extractPathPrefix(textBeforeCursor, forceExtract: false) {
            let suggestions = getFileSuggestions(prefix: pathPrefix)
            if suggestions.isEmpty { return nil }

            if suggestions.count == 1, suggestions[0].value == pathPrefix, !pathPrefix.hasSuffix("/") {
                return (suggestions, pathPrefix)
            }

            return (suggestions, pathPrefix)
        }

        return nil
    }

    /// Apply a suggestion and return updated text and cursor.
    public func applyCompletion(lines: [String], cursorLine: Int, cursorCol: Int, item: AutocompleteItem, prefix: String) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        let currentLine = lines[safe: cursorLine] ?? ""
        let beforePrefix = currentLine.substring(from: 0, length: max(0, cursorCol - prefix.count))
        let afterCursor = currentLine.substring(from: cursorCol, length: max(0, currentLine.count - cursorCol))

        let isQuotedPrefix = prefix.hasPrefix("\"") || prefix.hasPrefix("@\"")
        let hasLeadingQuoteAfterCursor = afterCursor.hasPrefix("\"")
        let hasTrailingQuoteInItem = item.value.hasSuffix("\"")
        let adjustedAfterCursor = isQuotedPrefix && hasTrailingQuoteInItem && hasLeadingQuoteAfterCursor
            ? String(afterCursor.dropFirst())
            : afterCursor

        let isSlashCommand = prefix.hasPrefix("/") && beforePrefix.trimmingCharacters(in: .whitespaces).isEmpty && !prefix.dropFirst().contains("/")
        if isSlashCommand {
            let newLine = "\(beforePrefix)/\(item.value) \(adjustedAfterCursor)"
            var newLines = lines
            newLines[cursorLine] = newLine
            return (newLines, cursorLine, beforePrefix.count + item.value.count + 2)
        }

        if prefix.hasPrefix("@") {
            let isDirectory = item.label.hasSuffix("/")
            let suffix = isDirectory ? "" : " "
            let newLine = "\(beforePrefix)\(item.value)\(suffix)\(adjustedAfterCursor)"
            var newLines = lines
            newLines[cursorLine] = newLine
            let cursorOffset = isDirectory && hasTrailingQuoteInItem ? item.value.count - 1 : item.value.count
            return (newLines, cursorLine, beforePrefix.count + cursorOffset + suffix.count)
        }

        let textBeforeCursor = currentLine.prefixCharacters(cursorCol)
        if textBeforeCursor.contains("/") && textBeforeCursor.contains(" ") {
            let newLine = beforePrefix + item.value + adjustedAfterCursor
            var newLines = lines
            newLines[cursorLine] = newLine
            let isDirectory = item.label.hasSuffix("/")
            let cursorOffset = isDirectory && hasTrailingQuoteInItem ? item.value.count - 1 : item.value.count
            return (newLines, cursorLine, beforePrefix.count + cursorOffset)
        }

        let newLine = beforePrefix + item.value + adjustedAfterCursor
        var newLines = lines
        newLines[cursorLine] = newLine
        let isDirectory = item.label.hasSuffix("/")
        let cursorOffset = isDirectory && hasTrailingQuoteInItem ? item.value.count - 1 : item.value.count
        return (newLines, cursorLine, beforePrefix.count + cursorOffset)
    }

    /// Force file suggestions even when the prefix is not obviously a path.
    public func getForceFileSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> (items: [AutocompleteItem], prefix: String)? {
        let currentLine = lines[safe: cursorLine] ?? ""
        let textBeforeCursor = currentLine.substring(from: 0, length: cursorCol)

        if textBeforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") && !textBeforeCursor.trimmingCharacters(in: .whitespaces).contains(" ") {
            return nil
        }

        guard let pathPrefix = extractPathPrefix(textBeforeCursor, forceExtract: true) else {
            return nil
        }

        let suggestions = getFileSuggestions(prefix: pathPrefix)
        if suggestions.isEmpty { return nil }
        return (suggestions, pathPrefix)
    }

    /// Return whether file completion should trigger for the current context.
    public func shouldTriggerFileCompletion(lines: [String], cursorLine: Int, cursorCol: Int) -> Bool {
        let currentLine = lines[safe: cursorLine] ?? ""
        let textBeforeCursor = currentLine.substring(from: 0, length: cursorCol)
        if textBeforeCursor.trimmingCharacters(in: .whitespaces).hasPrefix("/") && !textBeforeCursor.trimmingCharacters(in: .whitespaces).contains(" ") {
            return false
        }
        return true
    }

    private func extractAtPrefix(_ text: String) -> String? {
        if let quoted = extractQuotedPrefix(text), quoted.hasPrefix("@\"") {
            return quoted
        }

        let lastDelimiterIndex = findLastDelimiter(text)
        let tokenStart = lastDelimiterIndex == -1 ? 0 : lastDelimiterIndex + 1
        let chars = Array(text)
        guard tokenStart < chars.count, chars[tokenStart] == "@" else { return nil }
        return substring(text, from: tokenStart)
    }

    private func extractPathPrefix(_ text: String, forceExtract: Bool) -> String? {
        if let quoted = extractQuotedPrefix(text) {
            return quoted
        }

        let lastDelimiterIndex = findLastDelimiter(text)
        let pathPrefix = lastDelimiterIndex == -1 ? text : substring(text, from: lastDelimiterIndex + 1)

        if forceExtract {
            return pathPrefix
        }

        if pathPrefix.contains("/") || pathPrefix.hasPrefix(".") || pathPrefix.hasPrefix("~/") {
            return pathPrefix
        }

        if pathPrefix.isEmpty && text.hasSuffix(" ") {
            return pathPrefix
        }

        return nil
    }

    private func expandHomePath(_ path: String) -> String {
        if path.hasPrefix("~/") {
            let expanded = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(String(path.dropFirst(2))).path
            if path.hasSuffix("/") && !expanded.hasSuffix("/") {
                return expanded + "/"
            }
            return expanded
        } else if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return path
    }

    private func getFileSuggestions(prefix: String) -> [AutocompleteItem] {
        do {
            let parsed = parsePathPrefix(prefix)
            var searchDir = ""
            var searchPrefix = ""
            var expandedPrefix = parsed.rawPrefix

            if expandedPrefix.hasPrefix("~") {
                expandedPrefix = expandHomePath(expandedPrefix)
            }

            let isRootPrefix =
                parsed.rawPrefix.isEmpty ||
                parsed.rawPrefix == "./" ||
                parsed.rawPrefix == "../" ||
                parsed.rawPrefix == "~" ||
                parsed.rawPrefix == "~/" ||
                parsed.rawPrefix == "/" ||
                (parsed.isAtPrefix && parsed.rawPrefix.isEmpty)

            if isRootPrefix {
                if parsed.rawPrefix.hasPrefix("~") || expandedPrefix.hasPrefix("/") {
                    searchDir = expandedPrefix
                } else {
                    searchDir = joinPath(basePath, expandedPrefix)
                }
                searchPrefix = ""
            } else if parsed.rawPrefix.hasSuffix("/") {
                if parsed.rawPrefix.hasPrefix("~") || expandedPrefix.hasPrefix("/") {
                    searchDir = expandedPrefix
                } else {
                    searchDir = joinPath(basePath, expandedPrefix)
                }
                searchPrefix = ""
            } else {
                let dir = dirname(expandedPrefix)
                let file = basename(expandedPrefix)
                if parsed.rawPrefix.hasPrefix("~") || expandedPrefix.hasPrefix("/") {
                    searchDir = dir
                } else {
                    searchDir = joinPath(basePath, dir)
                }
                searchPrefix = file
            }

            let entries = try FileManager.default.contentsOfDirectory(atPath: searchDir)
            var suggestions: [AutocompleteItem] = []

            for entry in entries {
                if !entry.lowercased().hasPrefix(searchPrefix.lowercased()) {
                    continue
                }

                let fullPath = joinPath(searchDir, entry)
                var isDirFlag: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirFlag) else {
                    continue
                }

                let isDirectory = isDirFlag.boolValue
                let displayPrefix = parsed.rawPrefix
                var relativePath = ""

                if displayPrefix.hasSuffix("/") {
                    relativePath = displayPrefix + entry
                } else if displayPrefix.contains("/") {
                    if displayPrefix.hasPrefix("~/") {
                        let homeRelativeDir = String(displayPrefix.dropFirst(2))
                        let dir = dirname(homeRelativeDir)
                        relativePath = "~/" + (dir == "." ? entry : joinPath(dir, entry))
                    } else if displayPrefix.hasPrefix("/") {
                        let dir = dirname(displayPrefix)
                        relativePath = dir == "/" ? "/\(entry)" : "\(dir)/\(entry)"
                    } else {
                        relativePath = joinPath(dirname(displayPrefix), entry)
                    }
                } else {
                    if displayPrefix.hasPrefix("~") {
                        relativePath = "~/" + entry
                    } else {
                        relativePath = entry
                    }
                }

                let pathValue = isDirectory ? "\(relativePath)/" : relativePath
                let value = buildCompletionValue(pathValue, isAtPrefix: parsed.isAtPrefix, isQuotedPrefix: parsed.isQuotedPrefix)
                let label = entry + (isDirectory ? "/" : "")
                suggestions.append(AutocompleteItem(value: value, label: label, description: nil))
            }

            suggestions.sort { a, b in
                let aIsDir = a.value.hasSuffix("/")
                let bIsDir = b.value.hasSuffix("/")
                if aIsDir != bIsDir {
                    return aIsDir
                }
                return a.label.localizedCaseInsensitiveCompare(b.label) == .orderedAscending
            }

            return suggestions
        } catch {
            return []
        }
    }

    private func scoreEntry(filePath: String, query: String, isDirectory: Bool) -> Int {
        let fileName = basename(filePath)
        let lowerFileName = fileName.lowercased()
        let lowerQuery = query.lowercased()
        var score = 0

        if lowerFileName == lowerQuery {
            score = 100
        } else if lowerFileName.hasPrefix(lowerQuery) {
            score = 80
        } else if lowerFileName.contains(lowerQuery) {
            score = 50
        } else if filePath.lowercased().contains(lowerQuery) {
            score = 30
        }

        if isDirectory && score > 0 {
            score += 10
        }

        return score
    }

    private func getFuzzyFileSuggestions(query: String, isQuotedPrefix: Bool) -> [AutocompleteItem] {
        guard let fdPath, !fdPath.isEmpty else {
            return []
        }

        let entries = walkDirectoryWithFd(baseDir: basePath, fdPath: fdPath, query: query, maxResults: 100)
        let scored = entries
            .map { entry in
                (entry: entry, score: query.isEmpty ? 1 : scoreEntry(filePath: entry.path, query: query, isDirectory: entry.isDirectory))
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(20)

        return scored.map { scoredEntry in
            let entryPath = scoredEntry.entry.path
            let isDirectory = scoredEntry.entry.isDirectory
            let pathWithoutSlash = isDirectory ? String(entryPath.dropLast()) : entryPath
            let entryName = basename(pathWithoutSlash)
            let value = buildCompletionValue(entryPath, isAtPrefix: true, isQuotedPrefix: isQuotedPrefix)
            return AutocompleteItem(value: value, label: entryName + (isDirectory ? "/" : ""), description: pathWithoutSlash)
        }
    }
}

private func joinPath(_ base: String, _ component: String) -> String {
    let ns = base as NSString
    return ns.appendingPathComponent(component)
}

private func dirname(_ path: String) -> String {
    return (path as NSString).deletingLastPathComponent
}

private func basename(_ path: String) -> String {
    return (path as NSString).lastPathComponent
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
