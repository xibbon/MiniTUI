import Foundation
import Testing
@testable import MiniTui
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private final class M1RecordingTerminal: Terminal {
    let columns: Int
    let rows: Int
    var kittyProtocolActive = false
    var writes: [String] = []
    init(columns: Int = 20, rows: Int = 4) {
        self.columns = columns
        self.rows = rows
    }
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
private final class M1Lines: Component {
    let lines: [String]
    var wheelDeltas: [Int] = []
    var handlesWheel = false
    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { lines }
    func handleInput(_ data: String) {}
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        guard event.type == .wheel else { return nil }
        wheelDeltas.append(event.wheelDelta ?? 0)
        return handlesWheel ? TuiMouseEventResult(handled: true) : nil
    }
}

@MainActor
private func m1Frame(_ renderer: AltScreenRenderer, root: Component, width: Int, height: Int) -> TuiRenderFrame {
    let layout = renderer.renderLayout(root: root, width: width, height: height) {}
    return TuiRenderFrame(lines: layout.lines, cursor: nil, width: width, height: height,
        clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false,
        useSystemCursor: false, layoutFrame: layout)
}

@Suite("M1 alternate screen upgrades", .serialized)
@MainActor
struct M1AltScreenUpgradeTests {
    @Test("Alt wheel multiplies dispatched delta and direct scrolling by five")
    func altWheelMultiplier() {
        let terminal = M1RecordingTerminal()
        let lines = M1Lines((1...12).map { "line \($0)" })
        let scroll = ScrollView(lines, options: .init(follow: .end, primary: true))
        let renderer = AltScreenRenderer(terminal: terminal)
        renderer.setLayoutRoot(scroll)
        renderer.start()
        defer { renderer.stop(preserveScreen: true) }
        renderer.present(m1Frame(renderer, root: scroll, width: 20, height: 4))
        #expect(scroll.scrollTop == 8)

        lines.handlesWheel = true
        #expect(renderer.handleInput("\u{1B}[<72;1;1M"))
        #expect(lines.wheelDeltas == [-5])
        #expect(scroll.scrollTop == 8)

        lines.handlesWheel = false
        #expect(renderer.handleInput("\u{1B}[<72;1;1M"))
        #expect(lines.wheelDeltas == [-5, -5])
        #expect(scroll.scrollTop == 3)
    }

    @Test("clipboard failures show backend detail; an empty selection copies nothing silently")
    func clipboardFailureDetail() async {
        let terminal = M1RecordingTerminal(columns: 60, rows: 4)
        let lines = M1Lines(["alpha", "beta", "gamma", "delta"])
        let scroll = ScrollView(lines, options: .init(primary: true))
        let renderer = AltScreenRenderer(terminal: terminal, options: .init(copyOnSelect: false,
            copySelection: { _ in .failed("Clipboard unavailable: install wl-clipboard") }))
        renderer.setLayoutRoot(scroll)
        renderer.start()
        defer { renderer.stop(preserveScreen: true) }
        renderer.present(m1Frame(renderer, root: scroll, width: 60, height: 4))
        #expect(!renderer.hasActiveSelection())
        #expect(await !renderer.copyActiveSelectionToClipboard())
        renderer.present(m1Frame(renderer, root: scroll, width: 60, height: 4))
        // Upstream returns false without a notice so the caller can copy the last response instead.
        #expect(terminal.writes.last?.contains("Copy failed") != true)

        #expect(renderer.handleInput("\u{1B}[<0;1;1M"))
        #expect(renderer.handleInput("\u{1B}[<32;4;2M"))
        #expect(renderer.handleInput("\u{1B}[<0;4;2m"))
        #expect(renderer.hasActiveSelection())
        #expect(await !renderer.copyActiveSelectionToClipboard())
        renderer.present(m1Frame(renderer, root: scroll, width: 60, height: 4))
        #expect(terminal.writes.last?.contains("Clipboard unavailable: install wl-clipboard") == true)
    }

    @Test("WezTerm clears changed rows before writing a Kitty image")
    func wezTermKittyErasure() {
        let savedProgram = getenv("TERM_PROGRAM").map { String(cString: $0) }
        let savedTerm = getenv("TERM").map { String(cString: $0) }
        let savedPane = getenv("WEZTERM_PANE").map { String(cString: $0) }
        defer {
            if let savedProgram { setenv("TERM_PROGRAM", savedProgram, 1) } else { unsetenv("TERM_PROGRAM") }
            if let savedTerm { setenv("TERM", savedTerm, 1) } else { unsetenv("TERM") }
            if let savedPane { setenv("WEZTERM_PANE", savedPane, 1) } else { unsetenv("WEZTERM_PANE") }
            setCapabilities(nil)
        }
        setenv("TERM_PROGRAM", "WezTerm", 1)
        setenv("TERM", "xterm-256color", 1)
        unsetenv("WEZTERM_PANE")
        #expect(isWezTerm(environment: ProcessInfo.processInfo.environment))
        setCapabilities(.init(images: .kitty, trueColor: true, hyperlinks: true))
        let terminal = M1RecordingTerminal(columns: 20, rows: 2)
        let renderer = AltScreenRenderer(terminal: terminal)
        renderer.start()
        let kitty = "\u{1B}_Ga=T,f=100,s=1,v=1;AAAA\u{1B}\\"
        renderer.present(.init(lines: ["text", kitty], cursor: nil, width: 20, height: 2,
            clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false, useSystemCursor: false))
        let output = terminal.writes.last ?? ""
        let firstClear = output.range(of: "\u{1B}[1;1H\u{1B}[2K")?.lowerBound
        let lastClear = output.range(of: "\u{1B}[2;1H\u{1B}[2K")?.lowerBound
        let image = output.range(of: kitty)?.lowerBound
        #expect(firstClear != nil && lastClear != nil && image != nil)
        if let firstClear, let lastClear, let image {
            #expect(firstClear < lastClear && lastClear < image)
        }
        renderer.stop(preserveScreen: true)

        setenv("TERM_PROGRAM", "Other", 1)
        #expect(!isWezTerm(environment: ProcessInfo.processInfo.environment))
        let otherTerminal = M1RecordingTerminal(columns: 20, rows: 2)
        let otherRenderer = AltScreenRenderer(terminal: otherTerminal)
        otherRenderer.start()
        otherRenderer.present(.init(lines: ["text", kitty], cursor: nil, width: 20, height: 2,
            clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false, useSystemCursor: false))
        let otherOutput = otherTerminal.writes.last ?? ""
        if let text = otherOutput.range(of: "text")?.lowerBound,
           let secondClear = otherOutput.range(of: "\u{1B}[2;1H\u{1B}[2K")?.lowerBound,
           let image = otherOutput.range(of: kitty)?.lowerBound {
            #expect(text < secondClear && secondClear < image)
        } else {
            Issue.record("Expected interleaved row clearing on another terminal")
        }
        otherRenderer.stop(preserveScreen: true)

        setenv("TERM_PROGRAM", "WezTerm", 1)
        let textTerminal = M1RecordingTerminal(columns: 20, rows: 2)
        let textRenderer = AltScreenRenderer(terminal: textTerminal)
        textRenderer.start()
        textRenderer.present(.init(lines: ["one", "two"], cursor: nil, width: 20, height: 2,
            clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false, useSystemCursor: false))
        let textOutput = textTerminal.writes.last ?? ""
        if let one = textOutput.range(of: "one")?.lowerBound,
           let secondClear = textOutput.range(of: "\u{1B}[2;1H\u{1B}[2K")?.lowerBound,
           let two = textOutput.range(of: "two")?.lowerBound {
            #expect(one < secondClear && secondClear < two)
        } else {
            Issue.record("Expected interleaved row clearing on a text-only frame")
        }
        textRenderer.stop(preserveScreen: true)
    }

    @Test("jump indicator stays centered when a scrollbar appears")
    func indicatorCentering() {
        let terminal = M1RecordingTerminal(columns: 80, rows: 6)
        let lines = M1Lines((1...20).map { "line \($0)" })
        let scroll = ScrollView(lines, options: .init(follow: .end, primary: true, scrollbar: .always))
        let label = " end now! "
        let renderer = AltScreenRenderer(terminal: terminal,
            options: .init(scrollToEndIndicator: { label }))
        renderer.setLayoutRoot(scroll)
        renderer.start()
        defer { renderer.stop(preserveScreen: true) }
        renderer.present(m1Frame(renderer, root: scroll, width: 80, height: 6))
        scroll.scrollBy(-1)
        let visible = stripTerminalSequences(m1Frame(renderer, root: scroll, width: 80, height: 6).lines[5])
        let visibleColumn = visible.range(of: label).map { visible.distance(from: visible.startIndex, to: $0.lowerBound) }
        scroll.setScrollbar(.hidden)
        let hidden = stripTerminalSequences(m1Frame(renderer, root: scroll, width: 80, height: 6).lines[5])
        let hiddenColumn = hidden.range(of: label).map { hidden.distance(from: hidden.startIndex, to: $0.lowerBound) }
        #expect(visibleColumn == 35)
        #expect(hiddenColumn == 35)
    }
}
