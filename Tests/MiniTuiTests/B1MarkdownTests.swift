import Foundation
import Testing
@testable import MiniTui

private struct B1StyledCell {
    var text: String
    var foreground: [Int] = []
    var bold = false
    var dim = false
    var underline = false
}

// Read rendered SGR state directly. The existing virtual terminal only records italic.
private func b1Cells(_ line: String) -> [B1StyledCell] {
    var result: [B1StyledCell] = []
    var state = B1StyledCell(text: "")
    var index = 0
    let chars = Array(line)
    while index < chars.count {
        if let ansi = extractAnsiCode(line, at: index) {
            if ansi.code.hasPrefix("\u{1b}["), ansi.code.hasSuffix("m") {
                let codes = ansi.code.dropFirst(2).dropLast().split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
                var i = 0
                while i < codes.count {
                    let code = codes[i]
                    switch code {
                    case 0: state = B1StyledCell(text: "")
                    case 1: state.bold = true
                    case 2: state.dim = true
                    case 4: state.underline = true
                    case 22: state.bold = false; state.dim = false
                    case 24: state.underline = false
                    case 39: state.foreground = []
                    case 30...37, 90...97: state.foreground = [code]
                    case 38 where i + 1 < codes.count:
                        let length = codes[i + 1] == 2 ? 5 : 3
                        if i + length <= codes.count { state.foreground = Array(codes[i..<(i + length)]); i += length - 1 }
                    default: break
                    }
                    i += 1
                }
            }
            index += ansi.length
        } else {
            state.text = String(chars[index]); result.append(state); index += 1
        }
    }
    return result
}

@MainActor
@Suite("B1 Markdown table styles")
struct B1MarkdownTests {
    @Test("wrapped links do not color table borders or plain cells")
    func wrappedLinks() throws {
        defer { resetCapabilitiesCache() }
        let source = "| Link | Plain |\n| --- | --- |\n| [**one two three four five six**](https://example.com) | normal text |"
        for hyperlinks in [true, false] {
            setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: hyperlinks))
            let lines = Markdown(source, paddingX: 0, paddingY: 0, theme: defaultMarkdownTheme).render(width: 24)
        let line = try #require(lines.first { stripTerminalSequences($0).contains("one") && stripTerminalSequences($0).contains("nor") })
            let cells = b1Cells(line)
            let text = cells.map(\.text).joined()
            let link = try #require(text.range(of: "one")).lowerBound
            let linkIndex = text.distance(from: text.startIndex, to: link)
            let separator = try #require(cells.indices.first { $0 > linkIndex && cells[$0].text == "│" })
            let plain = try #require(text.range(of: "nor")).lowerBound
            let plainIndex = text.distance(from: text.startIndex, to: plain)
            #expect(!cells[linkIndex].foreground.isEmpty && cells[linkIndex].bold)
            #expect(cells[separator].foreground.isEmpty && !cells[separator].bold)
            #expect(cells[plainIndex].foreground.isEmpty && !cells[plainIndex].bold)
            if !hyperlinks {
                let urlLine = try #require(lines.first { stripTerminalSequences($0).contains("https") })
                let urlCells = b1Cells(urlLine)
                let urlText = urlCells.map(\.text).joined()
                let urlStart = try #require(urlText.range(of: "https")).lowerBound
                let urlIndex = urlText.distance(from: urlText.startIndex, to: urlStart)
                #expect(urlCells[urlIndex].dim)
                for index in urlCells.indices where index > urlIndex && urlCells[index].text == "│" { #expect(!urlCells[index].dim) }
            }
        }
    }

    @Test("wrapped table links restore the surrounding blockquote color")
    func quote() throws {
        defer { resetCapabilitiesCache() }
        setCapabilities(TerminalCapabilities(images: nil, trueColor: true, hyperlinks: true))
        let theme = MarkdownTheme(heading: { $0 }, link: { "\u{1b}[38;2;129;162;190m\($0)\u{1b}[39m" }, linkUrl: { $0 }, code: { $0 }, codeBlock: { $0 }, codeBlockBorder: { $0 }, quote: { "\u{1b}[38;2;18;52;86m\($0)\u{1b}[39m" }, quoteBorder: { $0 }, hr: { $0 }, listBullet: { $0 }, bold: { $0 }, italic: { $0 }, strikethrough: { $0 }, underline: { "\u{1b}[4m\($0)\u{1b}[24m" })
        let source = "> | Link | Plain |\n> | --- | --- |\n> | [one two three four five six](https://example.com) | normal text |"
        let lines = Markdown(source, paddingX: 0, paddingY: 0, theme: theme).render(width: 28)
        let line = try #require(lines.first { stripTerminalSequences($0).contains("one") && stripTerminalSequences($0).contains("norma") })
        let cells = b1Cells(line)
        let text = cells.map(\.text).joined()
        let linkStart = try #require(text.range(of: "one")).lowerBound
        let linkIndex = text.distance(from: text.startIndex, to: linkStart)
        let separator = try #require(cells.indices.first { $0 > linkIndex && cells[$0].text == "│" })
        let plainStart = try #require(text.range(of: "norma")).lowerBound
        let plainIndex = text.distance(from: text.startIndex, to: plainStart)
        #expect(cells[linkIndex].foreground != [38, 2, 18, 52, 86])
        #expect(cells[separator].foreground == [38, 2, 18, 52, 86])
        #expect(cells[plainIndex].foreground == [38, 2, 18, 52, 86])
        let final = try #require(lines.first { stripTerminalSequences($0).contains("five six") })
        let finalCells = b1Cells(final)
        for cell in finalCells.dropFirst(2) where cell.text == "│" { #expect(cell.foreground == [38, 2, 18, 52, 86]) }
    }
}
