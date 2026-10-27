import Foundation
import Markdown

/// Input for cmark with the CJK emphasis boundary rule from marked-cjk-friendly 0.1.2.
/// cmark still matches delimiter runs, including nested and unmatched runs.
struct MarkdownCJKParserInput {
    let source: String
    let padding: String?

    init(_ source: String) {
        guard (source.contains("*") || source.contains("_")), source.contains(where: Self.isCJK) else {
            self.source = source
            padding = nil
            return
        }

        let characters = Array(source)
        let byteOffsets = characters.reduce(into: [0]) { offsets, character in
            offsets.append(offsets.last! + String(character).utf8.count)
        }
        let eligible = Self.delimiterPositions(in: source)
        var before = Set<Int>()
        var after = Set<Int>()
        var index = 0
        while index < characters.count {
            let marker = characters[index]
            guard (marker == "*" || marker == "_"), eligible.contains(byteOffsets[index]),
                  !Self.isEscaped(characters, at: index) else {
                index += 1
                continue
            }
            var end = index + 1
            while end < characters.count, characters[end] == marker { end += 1 }
            let previous = index > 0 ? characters[index - 1] : nil
            let next = end < characters.count ? characters[end] : nil

            // The plugin keeps the alphanumeric restriction for underscore openers.
            // Asterisk runs can also open between two letters.
            let underscoreWord = marker == "_" && (previous?.isLetter == true || previous?.isNumber == true)
            if !underscoreWord, let previous, let next, !previous.isWhitespace, !next.isWhitespace {
                if Self.isPunctuation(next), !Self.isPunctuation(previous),
                   Self.isCJK(previous) || Self.isCJK(next) {
                    before.insert(index)
                }
            }
            if let previous, let next, !previous.isWhitespace, !next.isWhitespace,
               Self.isPunctuation(previous), !Self.isPunctuation(next),
               Self.isCJK(previous) || Self.isCJK(next) {
                after.insert(end)
            }
            index = end
        }

        guard !before.isEmpty || !after.isEmpty else {
            self.source = source
            padding = nil
            return
        }

        // A comment gives cmark a punctuation boundary without adding visible text.
        // Select a comment that does not occur in the source. Remove only InlineHTML
        // nodes with this exact value; user text and decoded entities stay intact.
        var padding = "<!--minitui-cjk-->"
        while source.contains(padding) { padding = padding.dropLast(3) + "-x-->" }
        var result = ""
        for position in characters.indices {
            if before.contains(position) || after.contains(position) { result += padding }
            result.append(characters[position])
        }
        if after.contains(characters.count) { result += padding }
        self.source = result
        self.padding = padding
    }

    private static func isEscaped(_ characters: [Character], at index: Int) -> Bool {
        var count = 0
        var position = index
        while position > 0, characters[position - 1] == "\\" {
            count += 1
            position -= 1
        }
        return count % 2 == 1
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation,
             .mathSymbol, .currencySymbol, .modifierSymbol, .otherSymbol:
            return true
        default:
            return false
        }
    }

    // These are the explicit CJK ranges in the pinned upstream plugin. A Character
    // can also contain a variation selector, so test its base scalar.
    private static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value, value >= 0x1100 else { return false }
        return cjkRanges.contains { $0.contains(value) }
    }

    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x1100...0x11ff, 0x20a9...0x20a9, 0x2329...0x232a, 0x2630...0x2637,
        0x268a...0x268f, 0x2e80...0x2e99, 0x2e9b...0x2ef3, 0x2f00...0x2fd5,
        0x2ff0...0x303e, 0x3041...0x3096, 0x3099...0x30ff, 0x3105...0x312f,
        0x3131...0x318e, 0x3190...0x31e5, 0x31ef...0x321e, 0x3220...0x3247,
        0x3250...0xa48c, 0xa490...0xa4c6, 0xa960...0xa97c, 0xac00...0xd7a3,
        0xd7b0...0xd7c6, 0xd7cb...0xd7fb, 0xf900...0xfaff, 0xfe10...0xfe19,
        0xfe30...0xfe52, 0xfe54...0xfe66, 0xfe68...0xfe6b, 0xff01...0xffbe,
        0xffc2...0xffc7, 0xffca...0xffcf, 0xffd2...0xffd7, 0xffda...0xffdc,
        0xffe0...0xffe6, 0xffe8...0xffee, 0x16fe0...0x16fe4, 0x16ff0...0x16ff6,
        0x17000...0x18cda, 0x18cff...0x18d20, 0x18d80...0x18df2,
        0x18e00...0x19191, 0x191a0...0x191d2, 0x1aff0...0x1aff3,
        0x1aff5...0x1affb, 0x1affd...0x1affe, 0x1b000...0x1b128,
        0x1b132...0x1b132, 0x1b150...0x1b152, 0x1b155...0x1b155,
        0x1b164...0x1b168, 0x1b170...0x1b2fb, 0x1d300...0x1d356,
        0x1d360...0x1d376, 0x1f1ae...0x1f1ae, 0x1f200...0x1f200,
        0x1f202...0x1f202, 0x1f210...0x1f219, 0x1f21b...0x1f22e,
        0x1f230...0x1f231, 0x1f237...0x1f237, 0x1f23b...0x1f23b,
        0x1f240...0x1f248, 0x1f260...0x1f265, 0x1f7da...0x1f7da,
        0x20000...0x3fffd,
    ]

    private static func delimiterPositions(in source: String) -> Set<Int> {
        let bytes = Array(source.utf8)
        var lineStarts = [0]
        for index in bytes.indices where bytes[index] == 0x0a { lineStarts.append(index + 1) }
        var result = Set<Int>()

        func offsets(_ markup: Markup) -> Range<Int>? {
            guard let range = markup.range,
                  lineStarts.indices.contains(range.lowerBound.line - 1),
                  lineStarts.indices.contains(range.upperBound.line - 1) else { return nil }
            let start = lineStarts[range.lowerBound.line - 1] + range.lowerBound.column - 1
            let end = lineStarts[range.upperBound.line - 1] + range.upperBound.column - 1
            guard start >= 0, end >= start, end <= bytes.count else { return nil }
            return start..<end
        }

        func visit(_ markup: Markup) {
            // Use the first parse only to identify inline source. This excludes code,
            // HTML, link destinations, and reference definitions without a second lexer.
            // MiniTui also has a Text component. Select the parser's plain inline
            // leaf by its protocols, with code and HTML leaves excluded.
            if markup is any InlineMarkup, markup is any LiteralMarkup,
               !(markup is InlineCode), !(markup is InlineHTML),
               let range = offsets(markup) {
                for index in range where bytes[index] == 0x2a || bytes[index] == 0x5f {
                    result.insert(index)
                }
            } else if (markup is Strong || markup is Emphasis), let range = offsets(markup) {
                for index in range {
                    guard bytes[index] == 0x2a || bytes[index] == 0x5f else { break }
                    result.insert(index)
                }
                for index in range.reversed() {
                    guard bytes[index] == 0x2a || bytes[index] == 0x5f else { break }
                    result.insert(index)
                }
            }
            for child in markup.children { visit(child) }
        }
        visit(Document(parsing: source))
        return result
    }
}
