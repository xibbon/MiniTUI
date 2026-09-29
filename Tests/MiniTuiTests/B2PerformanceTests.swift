import Foundation
import Testing
@testable import MiniTui

private final class B2NullTerminal: Terminal {
    var columns = 80
    var rows = 30
    var kittyProtocolActive = false
    var bytesWritten = 0
    private var input: ((String) -> Void)?
    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) { input = onInput }
    func stop() { input = nil }
    func drainInput(maxMs: Int, idleMs: Int) {}
    func write(_ data: String) { bytesWritten += data.utf8.count }
    func moveBy(lines: Int) {}
    func hideCursor() {}
    func showCursor() {}
    func clearLine() {}
    func clearFromCursor() {}
    func clearScreen() {}
    func setTitle(_ title: String) {}
    func sendInput(_ data: String) { input?(data) }
}

@MainActor
private final class B2BenchmarkLines: Component {
    let lines: [String]
    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { lines }
}

/// The cached editor stand-in from render-churn-bench.ts.
@MainActor
private final class B2BenchmarkEditor: Component {
    var text = ""
    private var cachedText: String?
    private var cachedWidth: Int?
    private var cachedLines: [String]?
    func invalidate() { cachedLines = nil }
    func render(width: Int) -> [String] {
        if cachedText == text, cachedWidth == width, let cachedLines { return cachedLines }
        let border = "\u{001B}[90m" + String(repeating: "─", count: max(1, width - 2)) + "\u{001B}[39m"
        let lines = [border, " > " + text + systemCursorMarker, border]
        cachedText = text
        cachedWidth = width
        cachedLines = lines
        return lines
    }
}

/// Set MINITUI_FULL_BENCHMARKS=1 for the upstream component and frame counts.
/// Default counts keep the correctness suite small. Timings have no pass limit.
@Suite("B2 performance scenarios", .serialized)
@MainActor
struct B2PerformanceTests {
    private var full: Bool { ProcessInfo.processInfo.environment["MINITUI_FULL_BENCHMARKS"] == "1" }

    @Test("Styled ASCII and Unicode width scan benchmark")
    func styledWidthScan() {
        let styled = String(repeating: "\u{001B}[36mstatus\u{001B}[39m plain text ", count: full ? 2_000 : 100)
        let unicode = String(repeating: "\u{001B}[36m界🙂\u{001B}[39m text ", count: full ? 2_000 : 100)
        let frames = full ? 100 : 5
        let elapsed = ContinuousClock().measure {
            for _ in 0..<frames {
                _ = visibleWidth(styled)
                _ = visibleWidth(unicode)
                _ = stripTerminalSequences(styled)
                _ = getActiveBackgroundAnsi(styled)
            }
        }
        #expect(visibleWidth(styled) == 18 * (full ? 2_000 : 100))
        #expect(visibleWidth(unicode) == 10 * (full ? 2_000 : 100))
        report("styled-width", frames: frames, elapsed: elapsed)
    }

    private func report(_ name: String, frames: Int, elapsed: Duration, bytes: Int? = nil) {
        let parts = elapsed.components
        let milliseconds = Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
        let written = bytes.map { ", \($0 / frames) output bytes/frame" } ?? ""
        print("B2 benchmark \(name): \(milliseconds / Double(frames)) ms/frame (\(frames) frames\(written))")
    }

    private func frame(_ renderer: AltScreenRenderer, root: Component, terminal: B2NullTerminal) -> LayoutFrame {
        let layout = renderer.renderLayout(root: root, width: terminal.columns, height: terminal.rows, requestRender: {})
        renderer.present(TuiRenderFrame(
            lines: layout.lines, cursor: nil, width: terminal.columns, height: terminal.rows,
            clearOnShrink: false, hasOverlayEntries: false, hasVisibleOverlay: false,
            useSystemCursor: false, layoutFrame: layout
        ))
        return layout
    }

    private func measure(_ name: String, frames: Int, renderer: AltScreenRenderer,
                         root: Component, terminal: B2NullTerminal, beforeFrame: (Int) -> Void = { _ in }) {
        let startBytes = terminal.bytesWritten
        let elapsed = ContinuousClock().measure {
            for index in 0..<frames {
                beforeFrame(index)
                _ = frame(renderer, root: root, terminal: terminal)
            }
        }
        report(name, frames: frames, elapsed: elapsed, bytes: terminal.bytesWritten - startBytes)
    }

    @Test("Large Markdown transcript: steady, scrolling, streaming, and resizing")
    func largeTranscript() {
        let user = """
        ## User request

        Please inspect this implementation carefully and report the relevant behavior.

        - preserve correctness
        - include concrete evidence
        """
        let assistant = """
        ## Analysis

        Representative prose with **inline styles**, a [link](https://example.com), and enough words to wrap across terminal rows at realistic widths.

        1. First item with explanatory text and a concrete example.
        2. Second item with more explanatory text and another example.
        3. Third item that ensures list rendering is represented.

        ```ts
        function render(width: number): string[] {
          const lines: string[] = [];
          for (const child of children) {
            const childLines = child.render(width);
            for (const line of childLines) lines.push(line);
          }
          const height = lines.length;
          const start = Math.max(0, from);
          const end = Math.min(height, start + count);
          const visible = lines.slice(start, end);
          updateLayout(height, viewportHeight);
          return visible;
        }
        ```

        > A quoted conclusion with enough text to exercise wrapping and inline rendering in the real Markdown component.

        Final paragraph with a concise recommendation and a note about correctness tests.
        """
        let header = Container()
        header.addChild(Text("pi benchmark\nheader line", paddingX: 0, paddingY: 0))
        let resources = Container()
        resources.addChild(Text("resource", paddingX: 0, paddingY: 0))
        let chat = Container()
        let components = full ? 2_500 : 24
        var messages: [MiniTui.Markdown] = []
        for index in 0..<components {
            let message = MiniTui.Markdown(index.isMultiple(of: 2) ? user : assistant,
                paddingX: 1, paddingY: 0, theme: defaultMarkdownTheme)
            messages.append(message)
            chat.addChild(message)
        }
        let document = Container()
        document.addChild(header)
        document.addChild(resources)
        document.addChild(chat)
        let scroll = ScrollView(document, options: ScrollViewOptions(primary: true))
        let root = VStack(children: [
            .entry(StackEntry(scroll, options: StackEntryOptions(basis: .points(0), grow: 1, minSize: 1))),
            .component(VStack([Text("editor\nfooter", paddingX: 0, paddingY: 0)])),
        ])
        let terminal = B2NullTerminal()
        terminal.rows = 50
        let renderer = AltScreenRenderer(terminal: terminal)
        renderer.setLayoutRoot(root)
        renderer.start()
        defer { renderer.stop(preserveScreen: true) }
        _ = frame(renderer, root: root, terminal: terminal)
        let totalLines = document.render(width: terminal.columns).count
        #expect(totalLines > terminal.rows)
        scroll.scrollTo(totalLines / 2)
        for _ in 0..<(full ? 20 : 2) { _ = frame(renderer, root: root, terminal: terminal) }
        print("B2 benchmark transcript: \(components) Markdown components, \(totalLines) lines")
        measure("steady", frames: full ? 200 : 8, renderer: renderer, root: root, terminal: terminal)
        let beforeScroll = scroll.scrollTop
        measure("scroll", frames: full ? 200 : 8, renderer: renderer, root: root, terminal: terminal) { _ in scroll.scrollBy(1) }
        #expect(scroll.scrollTop > beforeScroll)
        measure("streaming", frames: full ? 100 : 4, renderer: renderer, root: root, terminal: terminal) { index in
            messages.last?.setText(assistant + "\n\nstream " + String(repeating: "x", count: index + 1))
        }
        measure("resize", frames: full ? 10 : 2, renderer: renderer, root: root, terminal: terminal) { index in
            terminal.columns = index.isMultiple(of: 2) ? 79 : 80
        }
        let last = frame(renderer, root: root, terminal: terminal)
        #expect(last.lines.count == terminal.rows)
        #expect(last.lines.allSatisfy { visibleWidth($0) <= terminal.columns })
    }

    @Test("Static and editor-update render churn")
    func renderChurn() {
        let transcript = Container()
        for index in 0..<150 {
            let line = index.isMultiple(of: 3)
                ? "\u{001B}[1m\u{001B}[36muser \(index)\u{001B}[39m\u{001B}[22m message with \u{001B}[33mstyled\u{001B}[39m content padding padding"
                : "assistant \(index) plain response line with enough text to be representative of a transcript row"
            transcript.addChild(Text(line, paddingX: 1, paddingY: 0))
        }
        let editor = B2BenchmarkEditor()
        let scroll = ScrollView(transcript, options: ScrollViewOptions(follow: .end, primary: true, scrollbar: .auto))
        let dock = VStack(children: [
            .entry(StackEntry(Text("status: idle", paddingX: 1, paddingY: 0), options: StackEntryOptions(shrink: 1, minSize: 0))),
            .entry(StackEntry(editor, options: StackEntryOptions(shrink: 1, minSize: 3))),
            .entry(StackEntry(Text("~/workspaces/pi main 100k tokens", paddingX: 1, paddingY: 0), options: StackEntryOptions(shrink: 1, minSize: 1))),
        ])
        let root = VStack(children: [
            .entry(StackEntry(scroll, options: StackEntryOptions(basis: .points(0), grow: 1, minSize: 1))),
            .entry(StackEntry(dock, options: StackEntryOptions(basis: .auto, grow: 0, shrink: 1, minSize: 1))),
        ])
        let terminal = B2NullTerminal()
        terminal.columns = 100
        let renderer = AltScreenRenderer(terminal: terminal)
        renderer.setLayoutRoot(root)
        renderer.start()
        defer { renderer.stop(preserveScreen: true) }
        for _ in 0..<(full ? 20 : 2) { _ = frame(renderer, root: root, terminal: terminal) }
        let frames = full ? 300 : 30
        let beforeStatic = terminal.bytesWritten
        measure("static", frames: frames, renderer: renderer, root: root, terminal: terminal)
        let staticBytes = terminal.bytesWritten - beforeStatic
        let beforeEditor = terminal.bytesWritten
        measure("editor", frames: frames, renderer: renderer, root: root, terminal: terminal) { index in
            editor.text += String(Unicode.Scalar(97 + index % 26)!)
        }
        #expect(editor.text.count == frames)
        #expect(terminal.bytesWritten - beforeEditor > staticBytes)
        #expect(scroll.isFollowingEnd)
    }

    @Test("Cold search, cached search, and renderer match navigation")
    func searchScenarios() async {
        let lineCount = full ? 100_000 : 2_000
        let lines = (0..<lineCount).map { "line \($0) " + ($0.isMultiple(of: 97) ? "needle" : "plain transcript") }
        let index = AltScreenSearchIndex()
        var initial = AltScreenSearchResult(matches: [], changed: false)
        let cold = ContinuousClock().measure { initial = index.search(lines: lines, query: "needle") }
        #expect(initial.changed)
        #expect(initial.matches.count == (lineCount - 1) / 97 + 1)
        report("search cold (\(lineCount) lines)", frames: 1, elapsed: cold)
        let frames = full ? 100 : 10
        let cached = ContinuousClock().measure {
            for _ in 0..<frames {
                let result = index.search(lines: lines, query: "needle")
                #expect(!result.changed)
                #expect(result.matches == initial.matches)
            }
        }
        report("search cached", frames: frames, elapsed: cached)
        let terminal = B2NullTerminal()
        let tui = TUI(terminal: terminal)
        let renderer = tui.enableAltScreen()
        let content = B2BenchmarkLines(lines)
        let scroll = ScrollView(content, options: ScrollViewOptions(primary: true))
        renderer.setLayoutRoot(scroll)
        #expect(tui.switchRenderer(to: .altScreen))
        tui.start()
        defer { tui.stop() }
        await tui.waitForRender()
        terminal.sendInput("\u{001B}[102;6u")
        terminal.sendInput("needle")
        await Task.yield()
        await tui.waitForRender()
        let clock = ContinuousClock()
        let start = clock.now
        let navigationFrames = full ? 100 : 4
        for _ in 0..<navigationFrames {
            terminal.sendInput("\u{0007}")
            await Task.yield()
            await tui.waitForRender()
        }
        report("search navigation", frames: navigationFrames, elapsed: start.duration(to: clock.now))
        #expect(scroll.scrollTop > 0)
        #expect(!scroll.isFollowingEnd)
    }
}
