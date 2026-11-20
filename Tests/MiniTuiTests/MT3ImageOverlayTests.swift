import Foundation
import Testing
@testable import MiniTui

@MainActor
private final class MT3Lines: Component {
    let lines: [String]
    var renders = 0
    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { renders += 1; return lines }
}

@MainActor
@Suite("MT3 terminal images", .serialized)
struct MT3ImageOverlayTests {
    private let deletePlacements = "\u{1B}_Ga=d,d=a,q=2\u{1B}\\"

    private func kitty(_ id: Int, columns: Int? = 4, rows: Int = 3) -> String {
        encodeKitty(base64Data: "AAAA", columns: columns, rows: rows, imageId: id, moveCursor: false)
    }

    private func start(_ lines: [String], fullscreen: Bool = false,
        imageProtocol: ImageProtocol? = nil) async -> (TUI, VirtualTerminal) {
        let terminal = VirtualTerminal(columns: 20, rows: 6)
        let tui = TUI(terminal: terminal)
        if fullscreen {
            let renderer = tui.enableAltScreen()
            renderer.setLayoutRoot(MT3Lines(lines))
            _ = tui.switchRenderer(to: .altScreen)
        } else {
            tui.addChild(MT3Lines(lines))
        }
        let old = getCapabilities()
        if let imageProtocol {
            setCapabilities(.init(images: imageProtocol, trueColor: true, hyperlinks: true))
        }
        tui.start()
        if imageProtocol != nil { setCapabilities(old) }
        await settle(tui)
        return (tui, terminal)
    }

    private func settle(_ tui: TUI) async {
        await Task.yield()
        await tui.waitForRender()
        await Task.yield()
        await tui.waitForRender()
    }

    private func panel(_ row: Int, _ col: Int, height: Int = 2, width: Int = 8) -> (MT3Lines, OverlayOptions) {
        (MT3Lines(Array(repeating: "PANEL", count: height)),
         OverlayOptions(width: .absolute(width), row: .absolute(row), col: .absolute(col)))
    }

    @Test("deletes a Kitty image under an overlay and redraws it after the overlay closes")
    func deleteAndRestore() async {
        let image = kitty(11585)
        let (tui, terminal) = await start(["top", image, "", "", "", "bottom"])
        defer { tui.stop() }
        terminal.writes.removeAll()
        let (component, options) = panel(2, 1)
        let overlay = tui.showOverlay(component, options: options)
        await settle(tui)
        let hidden = terminal.writes.joined()
        #expect(hidden.contains(deleteKittyImage(imageId: 11585)))
        #expect(!hidden.contains(image))
        #expect(hidden.contains("PANEL"))
        terminal.writes.removeAll()
        overlay.hide(); await settle(tui)
        #expect(terminal.writes.joined().contains(image))
    }

    @Test("keeps images whose rows the overlay does not touch")
    func disjointRows() async {
        let image = kitty(11584, rows: 2)
        let (tui, terminal) = await start([image, "", "", "", "", ""])
        defer { tui.stop() }
        terminal.writes.removeAll()
        let (component, options) = panel(4, 0)
        _ = tui.showOverlay(component, options: options); await settle(tui)
        #expect(!terminal.writes.joined().contains(deleteKittyImage(imageId: 11584)))
        #expect(terminal.writes.joined().contains("PANEL"))
    }

    @Test("keeps an image beside an overlay that shares its rows")
    func sideBySide() async {
        let image = kitty(11588, rows: 4)
        let (tui, terminal) = await start(["top", image, "", "", "", "bottom"])
        defer { tui.stop() }
        terminal.writes.removeAll()
        let (component, options) = panel(0, 10, height: 6)
        _ = tui.showOverlay(component, options: options); await settle(tui)
        let output = terminal.writes.joined()
        let deletion = output.range(of: deleteKittyImage(imageId: 11588))
        let drawing = output.range(of: image, options: .backwards)
        #expect(drawing != nil)
        if let deletion, let drawing { #expect(deletion.lowerBound < drawing.lowerBound) }
        #expect(terminal.writes.joined().contains("PANEL"))
        #expect(!terminal.getViewport()[1].contains("PANEL"))
    }

    @Test("keeps a fullscreen image beside an overlay that shares its rows")
    func fullscreenSideBySide() async {
        registerKittyImageMetadata(imageID: 11591, columns: 4, rows: 3, widthPx: 100, heightPx: 100)
        let (tui, terminal) = await start(["top", kitty(11591), "", "", "after", ""],
            fullscreen: true, imageProtocol: .kitty)
        defer { tui.stop() }
        terminal.writes.removeAll()
        let (component, options) = panel(1, 10, height: 4)
        _ = tui.showOverlay(component, options: options); await settle(tui)
        let output = terminal.writes.joined()
        #expect(output.contains("\u{1B}_Ga=p,q=2"))
        #expect(output.contains("i=11591"))
        #expect(output.contains("PANEL"))
    }

    @Test("hides an image of unknown width under any overlay sharing its rows")
    func unknownWidth() async {
        let (tui, terminal) = await start(["top", kitty(11589, columns: nil, rows: 2), "", "", "", ""])
        defer { tui.stop() }
        terminal.writes.removeAll()
        let (component, options) = panel(2, 15, width: 5)
        _ = tui.showOverlay(component, options: options); await settle(tui)
        #expect(terminal.writes.joined().contains(deleteKittyImage(imageId: 11589)))
    }

    @Test("reads the cells an image line covers")
    func extents() {
        let kittyLine = "  " + kitty(11590, columns: 6, rows: 3)
        #expect(getImageLineExtent(kittyLine) == .init(firstRow: 0, lastRow: 2, startCol: 2, endCol: 8))
        let iterm = "\u{1B}[2A" + encodeITerm2(base64Data: "AAAA", width: "5", height: "auto")
        #expect(getImageLineExtent(iterm) == .init(firstRow: -2, lastRow: 0, startCol: 0, endCol: 5))
        let auto = encodeITerm2(base64Data: "AAAA", width: "50%", height: "auto")
        #expect(getImageLineExtent(auto)?.endCol == nil)
        #expect(getImageLineExtent("plain text") == nil)
        #expect(stripImageSequences("before " + kittyLine + " after") == "before    after")
        #expect(stripImageSequences("before " + iterm + " after") == "before  after")
    }

    @Test("hides an image inside an overlay when a later overlay covers it")
    func stackedOverlays() async {
        let image = kitty(11587)
        let (tui, terminal) = await start(Array(repeating: "", count: 6))
        defer { tui.stop() }
        let lower = MT3Lines([image, "", ""])
        _ = tui.showOverlay(lower, options: .init(width: 10, row: 0, col: 0)); await settle(tui)
        #expect(terminal.writes.joined().contains(image))
        terminal.writes.removeAll()
        let (component, options) = panel(2, 0)
        _ = tui.showOverlay(component, options: options); await settle(tui)
        #expect(terminal.writes.joined().contains(deleteKittyImage(imageId: 11587)))
        #expect(terminal.getViewport()[2].contains("PANEL"))
    }

    @Test("hides an iTerm2 image when an overlay covers rows above its image line")
    func itermAbove() async {
        let image = "\u{1B}[2A" + encodeITerm2(base64Data: "AAAA", width: "4", height: "auto")
        let (tui, terminal) = await start(["top", "", "", image, "", "bottom"])
        defer { tui.stop() }
        terminal.writes.removeAll()
        let (component, options) = panel(1, 0)
        let overlay = tui.showOverlay(component, options: options); await settle(tui)
        #expect(!terminal.writes.joined().contains("\u{1B}]1337;File="))
        #expect(terminal.writes.joined().contains("PANEL"))
        terminal.writes.removeAll()
        overlay.hide(); await settle(tui)
        #expect(terminal.writes.joined().contains(image))
    }

    @Test("removes Kitty placements in fullscreen mode while an overlay covers them")
    func fullscreenPlacement() async {
        registerKittyImageMetadata(imageID: 11586, columns: 4, rows: 3, widthPx: 100, heightPx: 100)
        let (tui, terminal) = await start(["top", kitty(11586), "", "", "after", ""],
            fullscreen: true, imageProtocol: .kitty)
        defer { tui.stop() }
        terminal.writes.removeAll()
        let (component, options) = panel(2, 1)
        let overlay = tui.showOverlay(component, options: options); await settle(tui)
        let hidden = terminal.writes.joined()
        #expect(hidden.contains(deletePlacements))
        #expect(!hidden.contains("i=11586"))
        #expect(hidden.contains("PANEL"))
        terminal.writes.removeAll()
        overlay.hide(); await settle(tui)
        let restored = terminal.writes.joined()
        #expect(restored.contains("\u{1B}_Ga=p,q=2"))
        #expect(!restored.contains("\u{1B}_Ga=T"))
    }

    @Test("keeps uploaded Kitty images across a full redraw")
    func uploadedKittyFullRedraw() {
        let old = getCapabilities(); defer { setCapabilities(old) }
        setCapabilities(.init(images: .kitty, trueColor: true, hyperlinks: true))
        registerKittyImageMetadata(imageID: 12010, columns: 2, rows: 3, widthPx: 100, heightPx: 100)
        let image = kitty(12010, columns: 2)
        let terminal = VirtualTerminal(columns: 20, rows: 6)
        let renderer = AltScreenRenderer(terminal: terminal)
        renderer.start()
        func frame(_ height: Int) -> TuiRenderFrame {
            TuiRenderFrame(lines: ["before", image, "", "", "after"], cursor: nil,
                width: 20, height: height, clearOnShrink: false, hasOverlayEntries: false,
                hasVisibleOverlay: false, useSystemCursor: false)
        }
        renderer.present(frame(6))
        terminal.writes.removeAll()
        terminal.resize(columns: 20, rows: 8)
        renderer.present(frame(8))
        let output = terminal.writes.joined()
        #expect(output.contains(deletePlacements))
        #expect(output.contains("\u{1B}_Ga=p,q=2"))
        #expect(!output.contains("\u{1B}_Ga=T"))
        #expect(!output.contains("\u{1B}[2J"))
        #expect(output.components(separatedBy: "\u{1B}[2K").count - 1 == 8)
        #expect(output.contains("after"))
        renderer.stop(preserveScreen: true)
    }

    @Test("keeps hard breaks after an inline image as separate rows")
    func markdownImageHardBreaks() {
        let image = "\u{1B}_Ga=T,f=100,q=2,c=20,r=3,C=1;AAAA\u{1B}\\"
        let markdown = Markdown("`\(image)`  \n` `  \n` `\n\n- one", paddingX: 0, paddingY: 0,
            theme: defaultMarkdownTheme)
        let lines = markdown.render(width: 80)
        #expect(lines.allSatisfy { !$0.contains("\n") })
        #expect(lines.first?.contains(image) == true)
        #expect(lines.dropFirst().map { stripAnsiCodes($0).trimmingCharacters(in: .whitespaces) }
            == ["", "", "", "- one"])
        #expect(markdown.render(width: 80) == lines)
    }

    @Test("fullscreen view-only scroll keeps an overlapped image hidden and restores it on close")
    func viewOnlyOverlayScroll() async {
        registerKittyImageMetadata(imageID: 12011, columns: 4, rows: 3, widthPx: 100, heightPx: 100)
        let image = kitty(12011)
        let content = MT3Lines(["one", "two", image, "", "", "six", "seven", "eight"])
        let scroll = ScrollView(content, options: .init(primary: true))
        let terminal = VirtualTerminal(columns: 20, rows: 6)
        let tui = TUI(terminal: terminal)
        let renderer = tui.enableAltScreen(options: .init(wheelScrollLines: .lines(1)))
        renderer.setLayoutRoot(scroll)
        _ = tui.switchRenderer(to: .altScreen)
        let old = getCapabilities()
        setCapabilities(.init(images: .kitty, trueColor: true, hyperlinks: true))
        tui.start()
        setCapabilities(old)
        defer { tui.stop() }
        await settle(tui)
        let (component, options) = panel(1, 1, height: 3)
        terminal.writes.removeAll()
        let overlay = tui.showOverlay(component, options: options)
        await settle(tui)
        #expect(!renderer.getScreenLines().contains(where: isImageLine))
        let rendersBeforeScroll = content.renders
        terminal.writes.removeAll()
        terminal.sendInput("\u{1B}[<64;1;1M")
        await settle(tui)
        #expect(content.renders == rendersBeforeScroll)
        #expect(!renderer.getScreenLines().contains(where: isImageLine))
        #expect(!terminal.writes.joined().contains("i=12011"))
        terminal.writes.removeAll()
        overlay.hide(); await settle(tui)
        #expect(renderer.getScreenLines().contains(where: isImageLine))
        #expect(terminal.writes.joined().contains("i=12011"))
    }

    @Test("plain frame without overlays or images keeps recorded HEAD bytes")
    func plainFrameBytes() {
        let old = getCapabilities()
        setCapabilities(.init(images: nil, trueColor: false, hyperlinks: false))
        let terminal = VirtualTerminal(columns: 4, rows: 2)
        let renderer = AltScreenRenderer(terminal: terminal)
        renderer.start()
        setCapabilities(old)
        terminal.writes.removeAll()
        renderer.present(TuiRenderFrame(lines: ["one", "two"], cursor: nil,
            width: 4, height: 2, clearOnShrink: false, hasOverlayEntries: false,
            hasVisibleOverlay: false, useSystemCursor: false))
        // Recorded from the unchanged plain full-redraw path at HEAD 967c71f.
        let recorded = "\u{1B}[?2026h\u{1B}[2J"
            + "\u{1B}[1;1H\u{1B}[2Kone\u{1B}[0m\u{1B}]8;;\u{07}"
            + "\u{1B}[2;1H\u{1B}[2Ktwo\u{1B}[0m\u{1B}]8;;\u{07}"
            + "\u{1B}[?25l\u{1B}[?2026l"
        #expect(terminal.writes.joined() == recorded)
        renderer.stop(preserveScreen: true)
    }

    @Test("code block image lines bypass margins and background")
    func markdownCodeBlockImage() {
        let image = kitty(12012)
        let markdown = Markdown("```\n\(image)\n```", paddingX: 2, paddingY: 0,
            theme: defaultMarkdownTheme,
            defaultTextStyle: .init(bgColor: { "<bg>\($0)</bg>" }))
        let lines = markdown.render(width: 12)
        let imageLine = lines.first { isImageLine($0) }
        #expect(imageLine?.contains(image) == true)
        #expect(imageLine?.contains("<bg>") == false)
        #expect(imageLine?.contains("\n") == false)
    }
}
