import Testing
@testable import MiniTui

private final class KittyRecordingTerminal: Terminal {
    var columns = 40
    var rows = 10
    var kittyProtocolActive = false
    var writes: [String] = []

    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {}
    func stop() {}
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) { writes.append(data) }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}
}

@MainActor
@Suite("Kitty main-screen redraws")
struct KittyMainScreenRendererTests {
    private func frame(_ lines: [String], height: Int = 10) -> TuiRenderFrame {
        TuiRenderFrame(
            lines: lines, cursor: nil, width: 40, height: height,
            clearOnShrink: false, hasOverlayEntries: false,
            hasVisibleOverlay: false, useSystemCursor: false
        )
    }

    private func image(id: Int, rows: Int, data: String = "AAAA") -> String {
        encodeKitty(base64Data: data, columns: 2, rows: rows, imageId: id, moveCursor: false)
    }

    @Test("clear reserved rows before drawing an appended Kitty image")
    func appendedImageClearsRowsFirst() {
        let terminal = KittyRecordingTerminal()
        let renderer = MainScreenRenderer(terminal: terminal)
        renderer.present(frame(["before"]))
        terminal.writes.removeAll()

        let sequence = image(id: 41, rows: 2)
        renderer.present(frame(["before", sequence, "", "after"]))
        let output = terminal.writes.joined()
        #expect(output.contains("\u{001B}[2K\r\n\u{001B}[2K\u{001B}[1A" + sequence + "\u{001B}[1B"))
        #expect(!output.contains(sequence + "\r\n\u{001B}[2K"))
    }

    @Test("use a full redraw when image row clearing would scroll")
    func unsafeImagePreclearFallsBack() {
        let terminal = KittyRecordingTerminal()
        terminal.rows = 2
        let renderer = MainScreenRenderer(terminal: terminal)
        renderer.present(frame(["before"], height: 2))
        terminal.writes.removeAll()

        let sequence = image(id: 42, rows: 3)
        renderer.present(frame(["before", sequence, "", "", "after"], height: 2))
        let output = terminal.writes.joined()
        #expect(output.contains("\u{001B}[2J"))
        #expect(output.contains(sequence))
    }

    @Test("reserve visible image rows before a full-redraw placement")
    func fullRedrawReservesRows() {
        let terminal = KittyRecordingTerminal()
        terminal.rows = 5
        let renderer = MainScreenRenderer(terminal: terminal)
        let sequence = image(id: 43, rows: 3)
        renderer.present(frame(["l0", "l1", "l2", "l3", "l4", sequence, "", "", "after"], height: 5))
        let output = terminal.writes.joined()
        #expect(output.contains("\r\n\r\n\u{001B}[2A" + sequence + "\u{001B}[2B"))
        #expect(!output.contains(sequence + "\r\n\u{001B}[0m"))
    }

    @Test("place an image taller than the viewport from its first row")
    func tallImageUsesFirstRow() {
        let terminal = KittyRecordingTerminal()
        terminal.rows = 5
        let renderer = MainScreenRenderer(terminal: terminal)
        let sequence = image(id: 44, rows: 6)
        renderer.present(frame(["before", sequence, "", "", "", "", "", "after"], height: 5))
        let output = terminal.writes.joined()
        #expect(output.contains(sequence))
        #expect(!output.contains("\u{001B}[5A" + sequence))
    }

    @Test("delete the old image before drawing a moved placement")
    func movedImageDeletesFirst() throws {
        let terminal = KittyRecordingTerminal()
        let renderer = MainScreenRenderer(terminal: terminal)
        let oldImage = image(id: 45, rows: 2)
        renderer.present(frame(["top", oldImage]))
        terminal.writes.removeAll()

        let newImage = image(id: 45, rows: 1, data: "BBBB")
        renderer.present(frame([newImage, ""]))
        let output = terminal.writes.joined()
        let deleteRange = try #require(output.range(of: deleteKittyImage(imageId: 45)))
        let drawRange = try #require(output.range(of: newImage))
        #expect(deleteRange.lowerBound < drawRange.lowerBound)
    }

    @Test("redraw an image when an earlier reserved row changes")
    func changedReservedRowRedrawsImage() throws {
        let terminal = KittyRecordingTerminal()
        let renderer = MainScreenRenderer(terminal: terminal)
        let sequence = image(id: 46, rows: 2)
        renderer.present(frame(["", sequence]))
        terminal.writes.removeAll()

        renderer.present(frame(["covered", sequence]))
        let output = terminal.writes.joined()
        let deleteRange = try #require(output.range(of: deleteKittyImage(imageId: 46)))
        let drawRange = try #require(output.range(of: sequence))
        #expect(deleteRange.lowerBound < drawRange.lowerBound)
        #expect(!output.contains("\u{001B}[2J"))
    }

    @Test("delete previous image IDs before clearing for a full redraw")
    func fullRedrawDeletesPreviousImage() throws {
        let terminal = KittyRecordingTerminal()
        let renderer = MainScreenRenderer(terminal: terminal)
        renderer.present(frame([image(id: 47, rows: 2)]))
        terminal.writes.removeAll()

        renderer.invalidateRenderState()
        renderer.present(frame(["plain text"]))
        let output = terminal.writes.joined()
        let deleteRange = try #require(output.range(of: deleteKittyImage(imageId: 47)))
        let clearRange = try #require(output.range(of: "\u{001B}[2J"))
        #expect(deleteRange.lowerBound < clearRange.lowerBound)
    }

    @Test("renderer takeover transmits the previous image again")
    func takeoverRetransmitsImage() {
        let terminal = KittyRecordingTerminal()
        let first = MainScreenRenderer(terminal: terminal)
        let sequence = image(id: 48, rows: 1)
        first.present(frame([sequence]))
        terminal.writes.removeAll()

        let replacement = MainScreenRenderer(terminal: terminal)
        replacement.takeOverRenderState(from: first)
        replacement.present(frame([sequence]))
        #expect(terminal.writes.joined().contains(sequence))
    }
}
