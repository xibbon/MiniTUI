import Foundation

/// A width-aware Markdown source transform.
public typealias MarkdownSourceTransform = @Sendable (_ source: String, _ width: Int) -> String

private struct MarkdownFence {
    let character: Character
    let length: Int
    let closing: Bool
}

private func markdownFence(in line: String, openFence: MarkdownFence?) -> MarkdownFence? {
    let characters = Array(line)
    var position = 0
    while position < characters.count, position < 3, characters[position] == " " {
        position += 1
    }
    guard position < characters.count,
          characters[position] == "`" || characters[position] == "~" else { return nil }
    let character = characters[position]
    let start = position
    while position < characters.count, characters[position] == character { position += 1 }
    let length = position - start
    guard length >= 3 else { return nil }

    if let openFence {
        guard character == openFence.character, length >= openFence.length else { return nil }
        let remainder = characters[position...]
        guard remainder.allSatisfy({ $0 == " " || $0 == "\t" }) else { return nil }
        return MarkdownFence(character: character, length: length, closing: true)
    }
    return MarkdownFence(character: character, length: length, closing: false)
}

private func isEscaped(_ characters: [Character], at index: Int) -> Bool {
    var backslashes = 0
    var position = index - 1
    while position >= 0, characters[position] == "\\" {
        backslashes += 1
        position -= 1
    }
    return backslashes % 2 == 1
}

private func runLength(of character: Character, at index: Int, in characters: [Character]) -> Int {
    var position = index
    while position < characters.count, characters[position] == character { position += 1 }
    return position - index
}

private func findBacktickClose(run: Int, from start: Int, in characters: [Character]) -> Int? {
    var position = start
    while position < characters.count {
        if characters[position] == "`" {
            let candidateRun = runLength(of: "`", at: position, in: characters)
            if candidateRun == run { return position }
            position += candidateRun
        } else {
            position += 1
        }
    }
    return nil
}

private func findMathClose(
    delimiter: [Character],
    from start: Int,
    allowNewline: Bool,
    in characters: [Character]
) -> Int? {
    var position = start
    while position + delimiter.count <= characters.count {
        if !allowNewline, characters[position] == "\n" { return nil }
        if Array(characters[position..<(position + delimiter.count)]) == delimiter,
           !isEscaped(characters, at: position) {
            return position
        }
        position += 1
    }
    return nil
}

private func isLikelyInlineDollarMath(
    body: String,
    closeEnd: Int,
    characters: [Character]
) -> Bool {
    guard !body.isEmpty, body.first?.isWhitespace != true, body.last?.isWhitespace != true else { return false }
    if closeEnd < characters.count, characters[closeEnd].isNumber { return false }
    if body.contains("`") { return false }

    let bodyCharacters = Array(body)
    let isEnvironmentName = !bodyCharacters.isEmpty
        && (bodyCharacters[0].isUppercase || bodyCharacters[0] == "_")
        && bodyCharacters.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "_" }
    if isEnvironmentName, closeEnd < characters.count {
        let next = characters[closeEnd]
        if next.isLetter || next == "_" { return false }
    }
    return true
}

private func transformMathSegment(_ source: String) -> String {
    let characters = Array(source)
    var result = ""
    var position = 0

    while position < characters.count {
        if characters[position] == "`" {
            let run = runLength(of: "`", at: position, in: characters)
            if let close = findBacktickClose(run: run, from: position + run, in: characters) {
                result += String(characters[position..<(close + run)])
                position = close + run
            } else {
                result += String(characters[position...])
                break
            }
            continue
        }

        var opening: [Character]?
        var closing: [Character]?
        var display = false
        var allowNewline = false
        if characters[position] == "$", !isEscaped(characters, at: position) {
            if position + 1 < characters.count, characters[position + 1] == "$" {
                opening = ["$", "$"]
                closing = ["$", "$"]
                display = true
                allowNewline = true
            } else if position + 1 >= characters.count || characters[position + 1].isWhitespace == false {
                opening = ["$"]
                closing = ["$"]
            }
        } else if characters[position] == "\\", !isEscaped(characters, at: position),
                  position + 1 < characters.count {
            if characters[position + 1] == "(" {
                opening = ["\\", "("]
                closing = ["\\", ")"]
            } else if characters[position + 1] == "[" {
                opening = ["\\", "["]
                closing = ["\\", "]"]
                display = true
                allowNewline = true
            }
        }

        guard let opening, let closing,
              let close = findMathClose(
                delimiter: closing,
                from: position + opening.count,
                allowNewline: allowNewline,
                in: characters
              ) else {
            result.append(characters[position])
            position += 1
            continue
        }

        let body = String(characters[(position + opening.count)..<close])
        let closeEnd = close + closing.count
        if opening == ["$"], !isLikelyInlineDollarMath(body: body, closeEnd: closeEnd, characters: characters) {
            result.append(characters[position])
            position += 1
            continue
        }

        let latexSource = display ? body.trimmingCharacters(in: .whitespacesAndNewlines) : body
        if let rendered = renderLatex(latexSource, options: RenderLatexOptions(display: display)) {
            // Swift Markdown changes soft line breaks to spaces. Use Markdown hard breaks so a
            // stacked layout remains a line array after parsing.
            result += display ? rendered.replacingOccurrences(of: "\n", with: "  \n") : rendered
        } else {
            result += String(characters[position..<closeEnd])
        }
        position = closeEnd
    }
    return result
}

/// Replace complete LaTeX spans in Markdown source with Unicode terminal text.
///
/// Fenced code blocks and inline code spans are not changed. The width parameter is part of the
/// transform contract. The current LaTeX layout does not wrap to that width.
public func transformMarkdownLatex(_ source: String, width: Int) -> String {
    _ = width
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var result: [String] = []
    var pending: [String] = []
    var openFence: MarkdownFence?

    func flushPending() {
        guard !pending.isEmpty else { return }
        let transformed = transformMathSegment(pending.joined(separator: "\n"))
        result += transformed.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        pending.removeAll(keepingCapacity: true)
    }

    for line in lines {
        if let currentFence = openFence {
            result.append(line)
            if markdownFence(in: line, openFence: currentFence)?.closing == true {
                openFence = nil
            }
            continue
        }

        if let fence = markdownFence(in: line, openFence: nil) {
            flushPending()
            result.append(line)
            openFence = fence
        } else {
            pending.append(line)
        }
    }
    flushPending()
    return result.joined(separator: "\n")
}
