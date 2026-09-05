import Foundation
import Testing
@testable import MiniTui

@Suite("B2 transcript search")
@MainActor
struct B2SearchTests {
    @Test("Search normalized transcript text across rows")
    func acrossRows() {
        #expect(findAltScreenSearchMatches(lines: ["alpha QUICK", "brown fox"], query: "quick brown") == [
            AltScreenSearchMatch(segments: [
                AltScreenSearchSegment(row: 0, startCol: 6, endCol: 11),
                AltScreenSearchSegment(row: 1, startCol: 0, endCol: 5),
            ]),
        ])
    }

    @Test("Map ASCII and Unicode matches to rendered columns")
    func renderedColumns() {
        #expect(findAltScreenSearchMatches(
            lines: ["\u{001B}[31mfoo  bar\u{001B}[0m", "A界🙂e\u{0301}Z"], query: "oo   bar\nA界🙂e\u{0301}"
        ) == [
            AltScreenSearchMatch(segments: [
                AltScreenSearchSegment(row: 0, startCol: 1, endCol: 3),
                AltScreenSearchSegment(row: 0, startCol: 5, endCol: 8),
                AltScreenSearchSegment(row: 1, startCol: 0, endCol: 6),
            ]),
        ])
    }

    @Test("Reuse matches until the query or rendered lines change")
    func cache() {
        let index = AltScreenSearchIndex()
        let initial = index.search(lines: ["alpha needle", "omega"], query: "needle")
        #expect(initial.changed)
        #expect(initial.matches.count == 1)
        let cached = index.search(lines: ["alpha needle", "omega"], query: "needle")
        #expect(!cached.changed)
        #expect(cached.matches == initial.matches)
        let normalized = index.search(lines: ["alpha needle", "omega"], query: " \tneedle\n")
        #expect(!normalized.changed)
        let changedQuery = index.search(lines: ["alpha needle", "omega"], query: "omega")
        #expect(changedQuery.changed)
        #expect(changedQuery.matches.first?.segments == [AltScreenSearchSegment(row: 1, startCol: 0, endCol: 5)])
        let changedLines = index.search(lines: ["alpha needle", "no match"], query: "omega")
        #expect(changedLines.changed)
        #expect(changedLines.matches.isEmpty)
    }

    @Test("Render a dim placeholder and right-aligned controls")
    func component() {
        var queries: [String] = []
        let component = AltScreenSearchComponent(onQueryChange: { queries.append($0) })
        let rendered = component.render(width: 48)
        let lines = rendered.map(stripTerminalSequences)
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { visibleWidth($0) == 48 })
        #expect(lines[0] == "┌" + String(repeating: "─", count: 46) + "┐")
        #expect(lines[1] == "│ Find in transcript" + String(repeating: " ", count: 27) + "│")
        #expect(rendered[1].contains("\u{001B}[2m"))
        #expect(lines[2].hasSuffix(" ↑ Shift+Enter · ↓ Enter ─┘"))
        func column(_ value: String, backwards: Bool = false) -> Int {
            let range = lines[2].range(of: value, options: backwards ? .backwards : [])!
            return visibleWidth(String(lines[2][..<range.lowerBound]))
        }
        #expect(component.getNavigationDirectionAt(row: 2, column: column("↑")) == -1)
        #expect(component.getNavigationDirectionAt(row: 2, column: column("Shift+Enter") + 5) == -1)
        #expect(component.getNavigationDirectionAt(row: 2, column: column("·")) == nil)
        #expect(component.getNavigationDirectionAt(row: 2, column: column("↓")) == 1)
        #expect(component.getNavigationDirectionAt(row: 2, column: column("Enter", backwards: true) + 2) == 1)
        component.handleInput("n")
        component.setResult(index: 0, count: 2)
        let populated = component.render(width: 48)
        #expect(populated[1].contains("\u{001B}[2m 1/2 \u{001B}[22m"))
        #expect(stripTerminalSequences(populated[1]).contains("n"))
        #expect(!populated.contains { stripTerminalSequences($0).contains("Find in transcript") })
        #expect(queries == ["n"])
        component.handleInput("\u{001B}[D")
        #expect(queries == ["n"])
    }

    @Test("Handle narrow search boxes and navigation hover")
    func narrowAndHovered() {
        let component = AltScreenSearchComponent(onQueryChange: { _ in }, navigationButtonStyle: {
            "\u{001B}[\($1 ? 45 : 44)m\($0)\u{001B}[49m"
        })
        #expect(component.render(width: 1) == ["┌", "│", "└"])
        #expect(component.getNavigationDirectionAt(row: 2, column: 0) == nil)
        #expect(component.render(width: 8).map(stripTerminalSequences)[2] == "└ ↑ ↓ ─┘")
        #expect(component.getNavigationDirectionAt(row: 2, column: 2) == -1)
        #expect(component.getNavigationDirectionAt(row: 1, column: 2) == nil)
        #expect(component.setHoveredNavigationDirection(-1))
        #expect(!component.setHoveredNavigationDirection(-1))
        #expect(component.render(width: 8)[2].contains("\u{001B}[45m↑\u{001B}[49m"))
        #expect(component.setHoveredNavigationDirection(nil))
        for width in 1...50 {
            let lines = component.render(width: width)
            #expect(lines.allSatisfy { visibleWidth($0) == width })
        }
        component.handleInput("absent")
        #expect(component.render(width: 40)[1].contains("\u{001B}[2m No matches \u{001B}[22m"))
        component.focused = true
        #expect(component.render(width: 40)[1].contains(systemCursorMarker))
    }

    @Test("Use literal non-overlapping matches with Unicode simple folding")
    func literalMatches() {
        #expect(findAltScreenSearchMatches(lines: ["a.a aXa"], query: "a.a").count == 1)
        #expect(findAltScreenSearchMatches(lines: ["aaaaa"], query: "aa").map(\.segments) == [
            [AltScreenSearchSegment(row: 0, startCol: 0, endCol: 2)],
            [AltScreenSearchSegment(row: 0, startCol: 2, endCol: 4)],
        ])
        #expect(findAltScreenSearchMatches(lines: ["K ſ ς"], query: "k s Σ").count == 1)
        #expect(findAltScreenSearchMatches(lines: ["Straße STRASSE"], query: "strasse").first?.segments.first?.startCol == 7)
        #expect(findAltScreenSearchMatches(lines: ["ßs"], query: "sß").isEmpty)
        #expect(findAltScreenSearchMatches(lines: ["İ ı"], query: "i").isEmpty)
        #expect(findAltScreenSearchMatches(lines: ["é"], query: "e\u{0301}").isEmpty)
        #expect(findAltScreenSearchMatches(lines: [" x", "", "  y "], query: "\u{FEFF}x\ty\n").count == 1)
        #expect(findAltScreenSearchMatches(lines: ["anything"], query: " \n ").isEmpty)
        #expect(findAltScreenSearchMatches(lines: [], query: "anything").isEmpty)
    }

    @Test("Cache compares rendered code units and match keys retain both ends")
    func codeUnitsAndKeys() {
        let index = AltScreenSearchIndex()
        _ = index.search(lines: ["é"], query: "é")
        #expect(index.search(lines: ["e\u{0301}"], query: "é").changed)
        let changedQuery = index.search(lines: ["e\u{0301}"], query: "e\u{0301}")
        #expect(changedQuery.changed)
        #expect(changedQuery.matches.count == 1)
        #expect(getAltScreenSearchMatchKey(AltScreenSearchMatch(segments: [])) == "")
        #expect(getAltScreenSearchMatchKey(AltScreenSearchMatch(segments: [
            AltScreenSearchSegment(row: 1, startCol: 2, endCol: 4),
            AltScreenSearchSegment(row: 3, startCol: 0, endCol: 5),
        ])) == "1:2:3:5")
    }
}
