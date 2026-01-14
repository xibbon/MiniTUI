import Testing
import MiniTui

final class StaticOverlay: Component {
    private let lines: [String]
    var requestedWidth: Int?

    init(_ lines: [String]) {
        self.lines = lines
    }

    func render(width: Int) -> [String] {
        requestedWidth = width
        return lines
    }
}

final class EmptyContent: Component {
    func render(width: Int) -> [String] {
        return []
    }
}

@MainActor
private func renderAndFlush(_ tui: TUI, _ terminal: VirtualTerminal) async {
    tui.requestRender(force: true)
    await terminal.flush()
}

private func indexOfSubstring(_ line: String?, _ substring: String) -> Int {
    guard let line, let range = line.range(of: substring) else { return -1 }
    return line.distance(from: line.startIndex, to: range.lowerBound)
}

@MainActor
@Test("overlay truncates lines that exceed declared width")
func overlayWidthOverflowProtection() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay([String(repeating: "X", count: 100)])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 20))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(!viewport.isEmpty)
    tui.stop()
}

@MainActor
@Test("overlay handles complex ANSI sequences without crashing")
func overlayComplexAnsi() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let complexLine =
        "\u{001B}[48;2;40;50;40m \u{001B}[38;2;128;128;128mSome styled content\u{001B}[39m\u{001B}[49m" +
        "\u{001B}]8;;http://example.com\u{0007}link\u{001B}]8;;\u{0007}" +
        String(repeating: " more content ", count: 10)
    let overlay = StaticOverlay([complexLine, complexLine, complexLine])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 60))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport.count > 0)
    tui.stop()
}

@MainActor
@Test("overlay composited on styled base content")
func overlayStyledBase() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    final class StyledContent: Component {
        func render(width: Int) -> [String] {
            let styledLine = "\u{001B}[1m\u{001B}[38;2;255;0;0m" + String(repeating: "X", count: width) + "\u{001B}[0m"
            return [styledLine, styledLine, styledLine]
        }
    }

    let overlay = StaticOverlay(["OVERLAY"])
    tui.addChild(StyledContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 20, anchor: .center))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport.contains { $0.contains("OVERLAY") })
    tui.stop()
}

@MainActor
@Test("overlay handles wide characters at boundary")
func overlayWideCharacters() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["中文日本語한글テスト漢字"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 15))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport.count > 0)
    tui.stop()
}

@MainActor
@Test("overlay positioned at terminal edge")
func overlayAtEdge() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay([String(repeating: "X", count: 50)])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 20, col: 60))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport.count > 0)
    tui.stop()
}

@MainActor
@Test("overlay on base content with OSC sequences")
func overlayOnOscBase() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    final class HyperlinkContent: Component {
        func render(width: Int) -> [String] {
            let link = "\u{001B}]8;;file:///path/to/file.ts\u{0007}file.ts\u{001B}]8;;\u{0007}"
            let line = "See \(link) for details " + String(repeating: "X", count: max(0, width - 30))
            return [line, line, line]
        }
    }

    let overlay = StaticOverlay(["OVERLAY-TEXT"])
    tui.addChild(HyperlinkContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 20, anchor: .center))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport.count > 0)
    tui.stop()
}

@MainActor
@Test("overlay width percentage")
func overlayWidthPercent() async {
    let terminal = VirtualTerminal(columns: 100, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["test"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: .percent(50)))
    tui.start()
    await renderAndFlush(tui, terminal)

    #expect(overlay.requestedWidth == 50)
    tui.stop()
}

@MainActor
@Test("overlay width percent respects minWidth")
func overlayWidthPercentMinWidth() async {
    let terminal = VirtualTerminal(columns: 100, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["test"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: .percent(10), minWidth: 30))
    tui.start()
    await renderAndFlush(tui, terminal)

    #expect(overlay.requestedWidth == 30)
    tui.stop()
}

@MainActor
@Test("overlay anchor top-left")
func overlayAnchorTopLeft() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["TOP-LEFT"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, anchor: .topLeft))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].hasPrefix("TOP-LEFT"))
    tui.stop()
}

@MainActor
@Test("overlay anchor bottom-right")
func overlayAnchorBottomRight() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["BTM-RIGHT"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, anchor: .bottomRight))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    let lastRow = viewport[23]
    #expect(lastRow.contains("BTM-RIGHT"))
    #expect(lastRow.trimmedRight().hasSuffix("BTM-RIGHT"))
    tui.stop()
}

@MainActor
@Test("overlay anchor top-center")
func overlayAnchorTopCenter() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["CENTERED"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, anchor: .topCenter))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    let firstRow = viewport[0]
    #expect(firstRow.contains("CENTERED"))
    let colIndex = indexOfSubstring(firstRow, "CENTERED")
    #expect(colIndex >= 30 && colIndex <= 40)
    tui.stop()
}

@MainActor
@Test("overlay clamps negative margins to zero")
func overlayNegativeMarginClamp() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["NEG-MARGIN"])

    tui.addChild(EmptyContent())
    tui.showOverlay(
        overlay,
        options: OverlayOptions(width: 12, anchor: .topLeft, margin: OverlayMargin(top: -5, right: 0, bottom: 0, left: -10))
    )
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].hasPrefix("NEG-MARGIN"))
    tui.stop()
}

@MainActor
@Test("overlay respects margin as number")
func overlayMarginAll() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["MARGIN"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, anchor: .topLeft, margin: OverlayMargin(all: 5)))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(!viewport[0].contains("MARGIN"))
    #expect(!viewport[4].contains("MARGIN"))
    #expect(viewport[5].contains("MARGIN"))
    let colIndex = indexOfSubstring(viewport[5], "MARGIN")
    #expect(colIndex == 5)
    tui.stop()
}

@MainActor
@Test("overlay respects margin object")
func overlayMarginEdges() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["MARGIN"])

    tui.addChild(EmptyContent())
    tui.showOverlay(
        overlay,
        options: OverlayOptions(width: 10, anchor: .topLeft, margin: OverlayMargin(top: 2, right: 0, bottom: 0, left: 3))
    )
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[2].contains("MARGIN"))
    let colIndex = indexOfSubstring(viewport[2], "MARGIN")
    #expect(colIndex == 3)
    tui.stop()
}

@MainActor
@Test("overlay applies offsets")
func overlayOffsets() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["OFFSET"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, anchor: .topLeft, offsetX: 10, offsetY: 5))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[5].contains("OFFSET"))
    let colIndex = indexOfSubstring(viewport[5], "OFFSET")
    #expect(colIndex == 10)
    tui.stop()
}

@MainActor
@Test("overlay percentage positioning")
func overlayPercentagePositioning() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["PCT"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, row: .percent(50), col: .percent(50)))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    var foundRow = -1
    for (index, line) in viewport.enumerated() {
        if line.contains("PCT") {
            foundRow = index
            break
        }
    }
    #expect(foundRow >= 10 && foundRow <= 13)
    tui.stop()
}

@MainActor
@Test("overlay row percent 0 positions at top")
func overlayRowPercentTop() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["TOP"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, row: .percent(0)))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].contains("TOP"))
    tui.stop()
}

@MainActor
@Test("overlay row percent 100 positions at bottom")
func overlayRowPercentBottom() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["BOTTOM"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, row: .percent(100)))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[23].contains("BOTTOM"))
    tui.stop()
}

@MainActor
@Test("overlay maxHeight truncation")
func overlayMaxHeightTruncation() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["Line 1", "Line 2", "Line 3", "Line 4", "Line 5"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(maxHeight: 3))
    tui.start()
    await renderAndFlush(tui, terminal)

    let content = terminal.getViewport().joined(separator: "\n")
    #expect(content.contains("Line 1"))
    #expect(content.contains("Line 2"))
    #expect(content.contains("Line 3"))
    #expect(!content.contains("Line 4"))
    #expect(!content.contains("Line 5"))
    tui.stop()
}

@MainActor
@Test("overlay maxHeight percent truncation")
func overlayMaxHeightPercentTruncation() async {
    let terminal = VirtualTerminal(columns: 80, rows: 10)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(maxHeight: .percent(50)))
    tui.start()
    await renderAndFlush(tui, terminal)

    let content = terminal.getViewport().joined(separator: "\n")
    #expect(content.contains("L1"))
    #expect(content.contains("L5"))
    #expect(!content.contains("L6"))
    tui.stop()
}

@MainActor
@Test("overlay absolute positioning overrides anchor")
func overlayAbsolutePositioning() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)
    let overlay = StaticOverlay(["ABSOLUTE"])

    tui.addChild(EmptyContent())
    tui.showOverlay(overlay, options: OverlayOptions(width: 10, anchor: .bottomRight, row: 3, col: 5))
    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[3].contains("ABSOLUTE"))
    let colIndex = indexOfSubstring(viewport[3], "ABSOLUTE")
    #expect(colIndex == 5)
    tui.stop()
}

@MainActor
@Test("stacked overlays render in order")
func overlayStackOrder() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    tui.addChild(EmptyContent())
    let overlay1 = StaticOverlay(["FIRST-OVERLAY"])
    tui.showOverlay(overlay1, options: OverlayOptions(width: 20, anchor: .topLeft))

    let overlay2 = StaticOverlay(["SECOND"])
    tui.showOverlay(overlay2, options: OverlayOptions(width: 10, anchor: .topLeft))

    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].contains("SECOND"))
    tui.stop()
}

@MainActor
@Test("stacked overlays at different positions")
func overlayStackDifferentPositions() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    tui.addChild(EmptyContent())
    let overlay1 = StaticOverlay(["TOP-LEFT"])
    tui.showOverlay(overlay1, options: OverlayOptions(width: 15, anchor: .topLeft))

    let overlay2 = StaticOverlay(["BTM-RIGHT"])
    tui.showOverlay(overlay2, options: OverlayOptions(width: 15, anchor: .bottomRight))

    tui.start()
    await renderAndFlush(tui, terminal)

    let viewport = terminal.getViewport()
    #expect(viewport[0].contains("TOP-LEFT"))
    #expect(viewport[23].contains("BTM-RIGHT"))
    tui.stop()
}

@MainActor
@Test("stacked overlays hide in order")
func overlayStackHideOrder() async {
    let terminal = VirtualTerminal(columns: 80, rows: 24)
    let tui = TUI(terminal: terminal)

    tui.addChild(EmptyContent())
    let overlay1 = StaticOverlay(["FIRST"])
    tui.showOverlay(overlay1, options: OverlayOptions(width: 10, anchor: .topLeft))

    let overlay2 = StaticOverlay(["SECOND"])
    tui.showOverlay(overlay2, options: OverlayOptions(width: 10, anchor: .topLeft))

    tui.start()
    await renderAndFlush(tui, terminal)

    var viewport = terminal.getViewport()
    #expect(viewport[0].contains("SECOND"))

    tui.hideOverlay()
    await renderAndFlush(tui, terminal)

    viewport = terminal.getViewport()
    #expect(viewport[0].contains("FIRST"))
    tui.stop()
}
