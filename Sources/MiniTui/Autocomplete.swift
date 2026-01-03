import Foundation

private func walkDirectoryWithFd(
    baseDir: String,
    fdPath: String,
    query: String,
    maxResults: Int
) -> [(path: String, isDirectory: Bool)] {
    var args = ["--base-directory", baseDir, "--max-results", String(maxResults), "--type", "f", "--type", "d"]
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

        if let atMatch = textBeforeCursor.range(of: "(?:^|\\s)(@[\\S]*)$", options: .regularExpression) {
            let prefix = String(textBeforeCursor[atMatch]).trimmingCharacters(in: .whitespaces)
            let query = String(prefix.dropFirst())
            let suggestions = getFuzzyFileSuggestions(query: query)
            if suggestions.isEmpty { return nil }
            return (suggestions, prefix)
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
                let filtered = commands.filter { $0.name.lowercased().hasPrefix(prefix.lowercased()) }
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

        let isSlashCommand = prefix.hasPrefix("/") && beforePrefix.trimmingCharacters(in: .whitespaces).isEmpty && !prefix.dropFirst().contains("/")
        if isSlashCommand {
            let newLine = "\(beforePrefix)/\(item.value) \(afterCursor)"
            var newLines = lines
            newLines[cursorLine] = newLine
            return (newLines, cursorLine, beforePrefix.count + item.value.count + 2)
        }

        if prefix.hasPrefix("@") {
            let newLine = "\(beforePrefix)\(item.value) \(afterCursor)"
            var newLines = lines
            newLines[cursorLine] = newLine
            return (newLines, cursorLine, beforePrefix.count + item.value.count + 1)
        }

        if currentLine.prefixCharacters(cursorCol).contains("/") && currentLine.prefixCharacters(cursorCol).contains(" ") {
            let newLine = beforePrefix + item.value + afterCursor
            var newLines = lines
            newLines[cursorLine] = newLine
            return (newLines, cursorLine, beforePrefix.count + item.value.count)
        }

        let newLine = beforePrefix + item.value + afterCursor
        var newLines = lines
        newLines[cursorLine] = newLine
        return (newLines, cursorLine, beforePrefix.count + item.value.count)
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

    private func extractPathPrefix(_ text: String, forceExtract: Bool) -> String? {
        if let atMatch = text.range(of: "@[\\S]*$", options: .regularExpression) {
            return String(text[atMatch])
        }

        let delimiters: [Character] = [" ", "\t", "\"", "'", "="]
        let lastDelimiterIndex = text.lastIndex(where: { delimiters.contains($0) })
        let pathPrefix = lastDelimiterIndex == nil ? text : String(text[text.index(after: lastDelimiterIndex!)...])

        if forceExtract {
            return pathPrefix
        }

        if pathPrefix.contains("/") || pathPrefix.hasPrefix(".") || pathPrefix.hasPrefix("~/") {
            return pathPrefix
        }

        if pathPrefix.isEmpty && (text.isEmpty || text.hasSuffix(" ")) {
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
            var searchDir = ""
            var searchPrefix = ""
            var expandedPrefix = prefix
            var isAtPrefix = false

            if prefix.hasPrefix("@") {
                isAtPrefix = true
                expandedPrefix = String(prefix.dropFirst())
            }

            if expandedPrefix.hasPrefix("~") {
                expandedPrefix = expandHomePath(expandedPrefix)
            }

            if expandedPrefix.isEmpty || expandedPrefix == "./" || expandedPrefix == "../" || expandedPrefix == "~" || expandedPrefix == "~/" || expandedPrefix == "/" || prefix == "@" {
                if prefix.hasPrefix("~") || expandedPrefix == "/" {
                    searchDir = expandedPrefix
                } else {
                    searchDir = joinPath(basePath, expandedPrefix)
                }
                searchPrefix = ""
            } else if expandedPrefix.hasSuffix("/") {
                if prefix.hasPrefix("~") || expandedPrefix.hasPrefix("/") {
                    searchDir = expandedPrefix
                } else {
                    searchDir = joinPath(basePath, expandedPrefix)
                }
                searchPrefix = ""
            } else {
                let dir = dirname(expandedPrefix)
                let file = basename(expandedPrefix)
                if prefix.hasPrefix("~") || expandedPrefix.hasPrefix("/") {
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
                var isDirectory: Bool
                var isDirFlag: ObjCBool = false
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirFlag) {
                    isDirectory = isDirFlag.boolValue
                } else {
                    isDirectory = false
                }

                var relativePath = ""
                if isAtPrefix {
                    let pathWithoutAt = expandedPrefix
                    if pathWithoutAt.hasSuffix("/") {
                        relativePath = "@" + pathWithoutAt + entry
                    } else if pathWithoutAt.contains("/") {
                        if pathWithoutAt.hasPrefix("~/") {
                            let homeRelativeDir = String(pathWithoutAt.dropFirst(2))
                            let dir = dirname(homeRelativeDir)
                            relativePath = "@~/" + (dir == "." ? entry : joinPath(dir, entry))
                        } else {
                            relativePath = "@" + joinPath(dirname(pathWithoutAt), entry)
                        }
                    } else {
                        if pathWithoutAt.hasPrefix("~") {
                            relativePath = "@~/" + entry
                        } else {
                            relativePath = "@" + entry
                        }
                    }
                } else if prefix.hasSuffix("/") {
                    relativePath = prefix + entry
                } else if prefix.contains("/") {
                    if prefix.hasPrefix("~/") {
                        let homeRelativeDir = String(prefix.dropFirst(2))
                        let dir = dirname(homeRelativeDir)
                        relativePath = "~/" + (dir == "." ? entry : joinPath(dir, entry))
                    } else if prefix.hasPrefix("/") {
                        let dir = dirname(prefix)
                        relativePath = dir == "/" ? "/\(entry)" : "\(dir)/\(entry)"
                    } else {
                        relativePath = joinPath(dirname(prefix), entry)
                    }
                } else {
                    if prefix.hasPrefix("~") {
                        relativePath = "~/" + entry
                    } else {
                        relativePath = entry
                    }
                }

                let value = isDirectory ? relativePath + "/" : relativePath
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

    private func getFuzzyFileSuggestions(query: String) -> [AutocompleteItem] {
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
            return AutocompleteItem(value: "@\(entryPath)", label: entryName + (isDirectory ? "/" : ""), description: pathWithoutSlash)
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
