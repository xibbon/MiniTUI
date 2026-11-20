import Foundation
import Testing
@testable import MiniTui

@Suite("MT1 column slicing")
struct MT1SlicingTests {
    @Test("slices box drawing, arrows and CJK by cell")
    func standaloneGraphemeCases() {
        // pi-mono v1.6.0 packages/tui/test/slice-graphemes.test.ts, issue #9549.
        let line = "│ a → 中文 ✓ │"
        expectSlice(line, 0, 6, true, "│ a → ", 6)
        expectSlice(line, 6, 4, true, "中文", 4)
        expectSlice(line, 7, 3, true, "文", 2)
        #expect(getGraphemeCellRange(line: line, column: 7) == .init(start: 6, end: 8))

    }

    @Test("keeps clusters that join standalone characters")
    func joinedGraphemeCases() {
        let family = "x👨\u{200D}❤y"
        expectSlice(family, 1, 2, true, "👨\u{200D}❤", 2)
        let accented = "→e\u{0301}→"
        expectSlice(accented, 1, 1, true, "e\u{0301}", 1)
        #expect(getGraphemeCellRange(line: accented, column: 2) == .init(start: 2, end: 3))
    }

    @Test("Match the previous slicer on 20,000 seeded inputs")
    func seededDifferentialCorpus() {
        var random = SliceRandom(seed: 0x9549_1600)
        let pieces = [
            "a", "Z", "0", " ", "~", "│", "→", "✓", "界", "文", "🙂", "👨\u{200D}❤",
            "e\u{0301}", "\u{0301}", "\t", "\u{0007}", "\u{1B}[31m", "\u{1B}[39m",
            "\u{1B}[0m", "\u{1B}]8;;https://example.org\u{0007}", "\u{1B}]8;;\u{0007}",
            "👩🏽", "🇺🇸", "\u{FE0F}", "가", "\u{0600}a", "\u{FFFD}",
            "\u{1B}_cursor\u{1B}\\", "\u{200D}", "\u{200B}"
        ]

        for caseNumber in 0..<20_000 {
            var line = ""
            for _ in 0..<random.next(12) {
                line += pieces[random.next(pieces.count)]
            }
            for _ in 0..<4 {
                let start = random.next(24) - 3
                let length = random.next(26)
                let strict = random.next(2) == 0
                let expected = previousSliceWithWidth(line, startCol: start, length: length, strict: strict)
                let actual = sliceWithWidth(line, startCol: start, length: length, strict: strict)
                #expect(actual.text == expected.text,
                        "Case \(caseNumber): \(String(reflecting: line)), start \(start), length \(length), strict \(strict)")
                #expect(actual.width == expected.width,
                        "Case \(caseNumber): \(String(reflecting: line)), start \(start), length \(length), strict \(strict)")
            }
        }
    }

    @Test("preserves the previous APC marker placement")
    func positionalCursorMarker() {
        let marker = "\u{1B}_cursor\u{1B}\\"
        let line = "a" + marker + "bcd"
        for start in 0..<4 {
            let expected = previousSliceWithWidth(line, startCol: start, length: 2, strict: true)
            expectSlice(line, start, 2, true, expected.text, expected.width)
        }
    }

    @Test("Measure 10,000 rows when MT1_SLICE_BENCH is set")
    func optInBenchmark() {
        guard ProcessInfo.processInfo.environment["MT1_SLICE_BENCH"] == "1" else { return }
        let rows = (0..<10_000).map { index in
            index.isMultiple(of: 4)
                ? "\u{1B}[32m✓\u{1B}[0m Assistant \(index): Updated 中文 notes and checked the result."
                : "Assistant \(index): I checked the repository and prepared the next change."
        }
        let clock = ContinuousClock()
        let oldStart = clock.now
        var oldChecksum = 0
        for row in rows {
            let slice = previousSliceWithWidth(row, startCol: 4, length: 24, strict: true)
            oldChecksum += slice.text.utf8.count + slice.width
        }
        let oldTime = oldStart.duration(to: clock.now)
        let newStart = clock.now
        var newChecksum = 0
        for row in rows {
            let slice = sliceWithWidth(row, startCol: 4, length: 24, strict: true)
            newChecksum += slice.text.utf8.count + slice.width
        }
        let newTime = newStart.duration(to: clock.now)
        #expect(newChecksum == oldChecksum)
        print("MT1 slice benchmark (10,000 rows): previous \(oldTime), current \(newTime)")
    }

    private func expectSlice(_ line: String, _ start: Int, _ length: Int, _ strict: Bool,
                             _ expectedText: String, _ expectedWidth: Int) {
        let actual = sliceWithWidth(line, startCol: start, length: length, strict: strict)
        #expect(actual.text == expectedText)
        #expect(actual.width == expectedWidth)
        #expect(sliceByColumn(line, startCol: start, length: length, strict: strict) == expectedText)
    }
}

private struct SliceRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next(_ upperBound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 32) % UInt64(upperBound))
    }
}

// The implementation before the MT1 fast path. Keep it in the test target as
// an independent oracle for output and width, including ANSI code order.
private func previousSliceWithWidth(_ line: String, startCol: Int, length: Int,
                                    strict: Bool) -> (text: String, width: Int) {
    if length <= 0 { return ("", 0) }

    let endCol = startCol + length
    var result = ""
    var resultWidth = 0
    var currentCol = 0
    var i = 0
    var pendingAnsi = ""
    let lineLength = line.count

    while i < lineLength {
        if let ansi = extractAnsiCode(line, at: i) {
            if currentCol >= startCol && currentCol < endCol {
                result += pendingAnsi + ansi.code
                pendingAnsi = ""
            } else if currentCol < startCol {
                pendingAnsi += ansi.code
            }
            i += ansi.length
            continue
        }

        var textEnd = i
        while textEnd < lineLength && extractAnsiCode(line, at: textEnd) == nil {
            textEnd += 1
        }

        let start = line.index(line.startIndex, offsetBy: i)
        let end = line.index(start, offsetBy: textEnd - i)
        let textPortion = line[start..<end]
        for grapheme in textPortion {
            let width = visibleWidth(String(grapheme))
            let inRange = currentCol >= startCol && currentCol < endCol
            let fits = !strict || currentCol + width <= endCol
            if inRange && fits {
                if !pendingAnsi.isEmpty {
                    result += pendingAnsi
                    pendingAnsi = ""
                }
                result.append(grapheme)
                resultWidth += width
            }
            currentCol += width
            if currentCol >= endCol { break }
        }
        i = textEnd
        if currentCol >= endCol { break }
    }
    return (result, resultWidth)
}
