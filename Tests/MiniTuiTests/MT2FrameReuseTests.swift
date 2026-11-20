import Foundation
import Testing
@testable import MiniTui

@MainActor
private final class MT2CountingComponent: Component, Focusable {
    var lines: [String]
    var renders = 0
    var widths: [Int] = []
    var focused = false
    var showFocus = false
    var useCapability = false
    var copyOnRender = false

    init(_ lines: [String]) { self.lines = lines }

    func render(width: Int) -> [String] {
        renders += 1
        widths.append(width)
        if useCapability { return [getCapabilities().trueColor ? "color" : "plain"] }
        if showFocus { return [focused ? "focused\(systemCursorMarker)" : "idle"] }
        return copyOnRender ? lines.map { String($0) } : lines
    }
}

@MainActor
private func mt2Settle(_ tui: TUI) async {
    await Task.yield()
    await tui.waitForRender()
    await Task.yield()
    await tui.waitForRender()
}

@MainActor
private func mt2Start(_ root: Component, width: Int = 20, height: Int = 4)
    async -> (TUI, AltScreenRenderer, VirtualTerminal) {
    let terminal = VirtualTerminal(columns: width, rows: height)
    let tui = TUI(terminal: terminal)
    let renderer = tui.enableAltScreen(options: AltScreenRendererOptions(wheelScrollLines: .lines(1)))
    renderer.setLayoutRoot(root)
    #expect(tui.switchRenderer(to: .altScreen))
    tui.start()
    await mt2Settle(tui)
    return (tui, renderer, terminal)
}

@Suite("MT2 frame reuse", .serialized)
@MainActor
struct MT2FrameReuseTests {
    @Test("reuses earlier frame output without accumulating widths")
    func earlierFrameWidths() {
        let component = MT2CountingComponent(["line"])
        let first = renderLayoutFrame(root: component, width: 10, height: 2) {}
        let reused = renderLayoutFrame(root: component, width: 10, height: 2,
            requestRender: {}, reusableOutput: first)
        #expect(component.widths == [10])
        let narrower = renderLayoutFrame(root: component, width: 8, height: 2,
            requestRender: {}, reusableOutput: reused)
        #expect(component.widths == [10, 8])
        #expect(narrower.renderCache[ObjectIdentifier(component)].map { Set($0.keys) } == Set([8]))
        _ = renderLayoutFrame(root: component, width: 10, height: 2,
            requestRender: {}, reusableOutput: narrower)
        #expect(component.widths == [10, 8, 10])
    }

    @Test("scrolls without re-rendering components until content changes")
    func scrollReuse() async {
        let component = MT2CountingComponent((1...10).map { "line \($0)" })
        let scroll = ScrollView(component, options: .init(follow: .end, primary: true))
        let (tui, renderer, terminal) = await mt2Start(scroll)
        defer { tui.stop() }
        let initial = component.renders
        terminal.sendInput("\u{1B}[<64;1;1M")
        await mt2Settle(tui)
        renderer.scrollBy(-1)
        await mt2Settle(tui)
        #expect(component.renders == initial)
        #expect(terminal.getViewport()[0].contains("line 5"))
        scroll.scrollBy(-1)
        await mt2Settle(tui)
        #expect(component.renders == initial)
        #expect(renderer.getScreenLines()[0].contains("line 4"))
        component.lines = ["changed"]
        tui.requestRender()
        await mt2Settle(tui)
        #expect(component.renders > initial)
        #expect(terminal.getViewport()[0].contains("changed"))
        let beforeForce = component.renders
        tui.requestRender(force: true)
        await mt2Settle(tui)
        #expect(component.renders > beforeForce)
    }

    @Test("content requests, child changes, width changes and focus invalidate output")
    func invalidation() async {
        let first = MT2CountingComponent(["old"])
        let root = Container()
        root.addChild(first)
        let (tui, renderer, terminal) = await mt2Start(root)
        defer { tui.stop() }
        first.lines = ["new"]
        tui.requestRender()
        await mt2Settle(tui)
        #expect(terminal.getViewport()[0].contains("new"))
        let second = MT2CountingComponent(["child"])
        root.addChild(second)
        #expect(root.render(width: 20).contains("child"))
        tui.requestRender()
        await mt2Settle(tui)
        #expect(renderer.getScreenLines().contains { $0.contains("child") })
        root.removeChild(second)
        tui.requestRender()
        await mt2Settle(tui)
        #expect(!renderer.getScreenLines().joined().contains("child"))
        let beforeWidth = first.renders
        terminal.resize(columns: 18, rows: 4)
        await mt2Settle(tui)
        #expect(first.renders > beforeWidth)
        #expect(first.widths.contains(18))
        first.showFocus = true
        tui.setFocus(first)
        tui.requestRender()
        await mt2Settle(tui)
        #expect(terminal.getViewport()[0].contains("focused"))
        tui.setFocus(nil)
        renderer.scrollBy(0)
        tui.requestViewRender()
        await mt2Settle(tui)
        #expect(terminal.getViewport()[0].contains("idle"))
    }

    @Test("overlay open and close show current content")
    func overlay() async {
        let root = MT2CountingComponent(["base"])
        let (tui, _, terminal) = await mt2Start(root)
        defer { tui.stop() }
        let dialog = MT2CountingComponent(["dialog"])
        let handle = tui.showOverlay(dialog)
        await mt2Settle(tui)
        #expect(terminal.getViewport().joined().contains("dialog"))
        handle.hide()
        await mt2Settle(tui)
        #expect(!terminal.getViewport().joined().contains("dialog"))
    }

    @Test("keeps search matches current across view-only scroll frames and content changes")
    func searchMatches() async {
        var lines = (1...12).map { "line \($0)" }
        lines[4] = "line 5 needle one"
        let component = MT2CountingComponent(lines)
        let scroll = ScrollView(component, options: .init(follow: .end, primary: true))
        let (tui, renderer, terminal) = await mt2Start(scroll, width: 60, height: 8)
        defer { tui.stop() }
        terminal.sendInput("\u{1B}[102;6u")
        terminal.sendInput("needle")
        await mt2Settle(tui)
        #expect(renderer.getScreenLines().joined().contains("1/1"))
        let afterQuery = component.renders
        for _ in 0..<3 { terminal.sendInput("\u{1B}[<65;1;4M") }
        await mt2Settle(tui)
        #expect(scroll.scrollTop > 0)
        #expect(component.renders == afterQuery)
        lines[10] = "line 11 needle two"
        component.lines = lines
        tui.requestRender()
        await mt2Settle(tui)
        #expect(renderer.getScreenLines().joined().contains("1/2"))
        terminal.sendInput("\u{1B}[103;6u")
        await mt2Settle(tui)
        #expect(renderer.getScreenLines().joined().contains("2/2"))
        #expect(renderer.getScreenLines().map(stripTerminalSequences).joined().contains("line 11 needle two"))
    }

    @Test("loader frame changes invalidate cached component output")
    func loaderAdvance() async {
        let terminal = VirtualTerminal(columns: 30, rows: 4)
        let tui = TUI(terminal: terminal)
        let renderer = tui.enableAltScreen()
        #expect(tui.switchRenderer(to: .altScreen))
        let loader = Loader(ui: tui, spinnerColorFn: { $0 }, messageColorFn: { $0 })
        loader.setIndicator(.init(frames: ["A"], intervalMs: 10))
        renderer.setLayoutRoot(loader)
        tui.start()
        defer { loader.stop(); tui.stop() }
        await mt2Settle(tui)
        #expect(terminal.getViewport().joined().contains("A Loading..."))
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            loader.onFrameAdvancedForTesting = {
                loader.stop()
                continuation.resume()
            }
            loader.setIndicator(.init(frames: ["A", "B"], intervalMs: 10))
        }
        await mt2Settle(tui)
        #expect(renderer.getScreenLines().map(stripTerminalSequences).joined().contains("B Loading..."))
    }

    @Test("capability changes render current component output")
    func capability() async {
        let old = getCapabilities()
        defer { setCapabilities(old) }
        setCapabilities(TerminalCapabilities(images: nil, trueColor: false, hyperlinks: false))
        let component = MT2CountingComponent([])
        component.useCapability = true
        let (tui, _, terminal) = await mt2Start(component)
        defer { tui.stop() }
        #expect(terminal.getViewport()[0].contains("plain"))
        setCapabilities(TerminalCapabilities(images: nil, trueColor: true, hyperlinks: false))
        tui.requestRender()
        await mt2Settle(tui)
        #expect(terminal.getViewport()[0].contains("color"))
    }

    @Test("inline renderer renders on each content request")
    func inline() async {
        let terminal = VirtualTerminal(columns: 20, rows: 4)
        let tui = TUI(terminal: terminal)
        let component = MT2CountingComponent(["old"])
        tui.addChild(component)
        tui.start()
        defer { tui.stop() }
        await mt2Settle(tui)
        let initial = component.renders
        component.lines = ["new"]
        tui.requestRender()
        await mt2Settle(tui)
        #expect(component.renders > initial)
        #expect(terminal.getViewport().joined().contains("new"))
    }

    @Test("opt-in 20000-line wheel frame benchmark")
    func wheelBenchmark() async {
        guard ProcessInfo.processInfo.environment["MINITUI_MT2_BENCH"] == "1" else { return }

        func run(markContentChanged: Bool) async -> (Int, [Double]) {
            let leaf = MT2CountingComponent((1...20_000).map { "transcript line \($0)" })
            leaf.copyOnRender = true
            let inner = Container()
            inner.addChild(leaf)
            let middle = Container()
            middle.addChild(inner)
            let outer = Container()
            outer.addChild(middle)
            let scroll = ScrollView(outer, options: .init(primary: true))
            let (tui, _, terminal) = await mt2Start(scroll, width: 80, height: 24)
            defer { tui.stop() }
            let initial = leaf.renders
            var milliseconds: [Double] = []
            for _ in 0..<100 {
                let start = DispatchTime.now().uptimeNanoseconds
                if markContentChanged { tui.requestRender() }
                terminal.sendInput("\u{1B}[<65;1;1M")
                await mt2Settle(tui)
                let end = DispatchTime.now().uptimeNanoseconds
                milliseconds.append(Double(end - start) / 1_000_000)
            }
            return (leaf.renders - initial, milliseconds)
        }

        let before = await run(markContentChanged: true)
        let after = await run(markContentChanged: false)
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        print("MT2 benchmark: before=\(before.0) renders, \(median(before.1)) ms/frame median; " +
              "after=\(after.0) renders, \(median(after.1)) ms/frame median")

        func layoutOnly(reuse: Bool) -> (Int, Double) {
            let leaf = MT2CountingComponent((1...20_000).map { "transcript line \($0)" })
            leaf.copyOnRender = true
            let inner = Container(); inner.addChild(leaf)
            let middle = Container(); middle.addChild(inner)
            let outer = Container(); outer.addChild(middle)
            let scroll = ScrollView(outer, options: .init(primary: true))
            var frame = renderLayoutFrame(root: scroll, width: 80, height: 24) {}
            let initial = leaf.renders
            var milliseconds: [Double] = []
            for _ in 0..<100 {
                scroll.scrollBy(1)
                let start = DispatchTime.now().uptimeNanoseconds
                frame = renderLayoutFrame(root: scroll, width: 80, height: 24,
                    requestRender: {}, reusableOutput: reuse ? frame : nil)
                milliseconds.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            return (leaf.renders - initial, median(milliseconds))
        }
        let layoutBefore = layoutOnly(reuse: false)
        let layoutAfter = layoutOnly(reuse: true)
        print("MT2 layout-only: before=\(layoutBefore.0) renders, \(layoutBefore.1) ms/frame median; " +
              "after=\(layoutAfter.0) renders, \(layoutAfter.1) ms/frame median")
        #expect(before.0 >= 100)
        #expect(after.0 == 0)
        #expect(layoutBefore.0 == 100)
        #expect(layoutAfter.0 == 0)
    }
}
