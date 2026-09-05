import Testing
@testable import MiniTui

@MainActor
private final class B2LayoutContent: Component {
    var lines: [String]
    var makeLines: ((Int) -> [String])?

    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { makeLines?(width) ?? lines }
}

@Suite("B2 layout painting and scroll follow")
@MainActor
struct B2LayoutTests {
    @Test("renders a proportional glyph scrollbar with an expanded active thumb")
    func scrollbarGlyphs() async throws {
        let source = ["abcd界", "abcde2", "abcde3", "abcde4", "abcde5", "abcde6", "abcde7", "abcde8"]
        let background = "\u{1B}[42m"
        let track = "\u{1B}[38;5;2m"
        let thumb = "\u{1B}[38;5;1m"
        let content = B2LayoutContent(source.map { background + $0 + "\u{1B}[49m" })
        let scroll = ScrollView(content, options: ScrollViewOptions(
            scrollbar: .auto,
            scrollbarTrackStyle: { track + $0 + "\u{1B}[39m" },
            scrollbarThumbStyle: { thumb + $0 + "\u{1B}[39m" },
            scrollbarHideDelayMilliseconds: 10
        ))
        func render() -> [String] { renderLayoutFrame(root: scroll, width: 6, height: 4) {}.lines }
        #expect(render().map(stripTerminalSequences) == Array(source.prefix(4)))
        scroll.scrollBy(2)
        var lines = render()
        #expect(lines.map(stripTerminalSequences) == ["abcde│", "abcde┃", "abcde┃", "abcde│"])
        #expect(lines.map { $0.contains(track) } == [true, false, false, true])
        #expect(lines.map { $0.contains(thumb) } == [false, true, true, false])
        scroll.setScrollbarActive(true)
        lines = render()
        #expect(lines.map(stripTerminalSequences) == ["abcde│", "abcde█", "abcde█", "abcde│"])
        #expect(lines[1].contains("\u{1B}[0m\u{1B}]8;;\u{7}" + background + thumb))
        scroll.setScrollbarActive(false)
        // The hide task must get an actor turn under a full-suite load.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while scroll.isScrollbarVisible && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(render().map(stripTerminalSequences) == Array(source[2..<6]))
        scroll.scrollToEnd()
        #expect(render().map(stripTerminalSequences) == ["abcde│", "abcde│", "abcde┃", "abcde┃"])
        scroll.scrollToStart()
        #expect(stripTerminalSequences(render()[0]) == "abcd ┃")
    }

    @Test("preserves only the underlying background beneath overlay scrollbar glyphs")
    func backgroundOnly() {
        let background = "\u{1B}[42m"
        let foreground = "\u{1B}[31m"
        let content = B2LayoutContent([])
        content.makeLines = { width in
            Array(repeating: background + String(repeating: "x", count: width - 1) + foreground + "│\u{1B}[39m\u{1B}[49m", count: 8)
        }
        let scroll = ScrollView(content, options: ScrollViewOptions(
            scrollbar: .auto, scrollbarTrackStyle: { $0 }, scrollbarThumbStyle: { $0 }
        ))
        _ = renderLayoutFrame(root: scroll, width: 6, height: 4) {}
        scroll.scrollBy(1)
        let lines = renderLayoutFrame(root: scroll, width: 6, height: 4) {}.lines
        #expect(lines.map(stripTerminalSequences) == ["xxxxx│", "xxxxx┃", "xxxxx┃", "xxxxx│"])
        for line in lines {
            #expect(!line.contains(foreground))
            #expect(line.contains("\u{1B}[0m\u{1B}]8;;\u{7}" + background))
        }
    }

    @Test("always-visible scrollbars reset content background in the reserved column")
    func reservedScrollbar() {
        let background = "\u{1B}[42m"
        let scroll = ScrollView(B2LayoutContent(Array(repeating: background + "abcde\u{1B}[49m", count: 8)), options: ScrollViewOptions(
            scrollbar: .always, scrollbarTrackStyle: { $0 }, scrollbarThumbStyle: { $0 }
        ))
        let frame = renderLayoutFrame(root: scroll, width: 6, height: 4) {}
        #expect(frame.root.children[0].rect.width == 5)
        #expect(frame.lines.map(stripTerminalSequences) == ["abcde┃", "abcde┃", "abcde│", "abcde│"])
        #expect(frame.lines.allSatisfy { $0.contains("\u{1B}[0m\u{1B}]8;;\u{7}┃") || $0.contains("\u{1B}[0m\u{1B}]8;;\u{7}│") })
    }

    @Test("fitting content has no automatic scrollbar but always mode fills the track")
    func fittingContent() {
        let content = B2LayoutContent(["one", "two"])
        let automatic = ScrollView(content, options: ScrollViewOptions(scrollbar: .auto))
        _ = renderLayoutFrame(root: automatic, width: 6, height: 4) {}
        automatic.scrollBy(1)
        #expect(!automatic.isScrollbarVisible)
        let fixed = ScrollView(content, options: ScrollViewOptions(scrollbar: .always))
        let frame = renderLayoutFrame(root: fixed, width: 6, height: 4) {}
        #expect(frame.lines.map(stripTerminalSequences).allSatisfy { $0.hasSuffix("┃") })
    }

    @Test("thumb height is proportional with a two-cell minimum", arguments: [(21, 19), (40, 10), (80, 5), (200, 2), (400, 2)])
    func proportionalThumb(value: (Int, Int)) {
        let scroll = ScrollView(B2LayoutContent(Array(repeating: "x", count: value.0)), options: ScrollViewOptions(scrollbar: .auto))
        _ = renderLayoutFrame(root: scroll, width: 6, height: 20) {}
        scroll.scrollBy(1)
        let frame = renderLayoutFrame(root: scroll, width: 6, height: 20) {}
        #expect(frame.lines.map(stripTerminalSequences).filter { $0.hasSuffix("┃") }.count == value.1)
    }

    @Test("content growth follows the end without revealing an automatic scrollbar")
    func growthWithoutActivity() {
        let content = B2LayoutContent(Array(repeating: "line", count: 8))
        let scroll = ScrollView(content, options: ScrollViewOptions(follow: .end, scrollbar: .auto))
        _ = renderLayoutFrame(root: scroll, width: 6, height: 4) {}
        #expect(scroll.followEnd)
        #expect(scroll.scrollTop == 4)
        content.lines.append("new")
        let frame = renderLayoutFrame(root: scroll, width: 6, height: 4) {}
        #expect(scroll.scrollTop == 5)
        #expect(!scroll.isScrollbarVisible)
        #expect(!frame.lines.joined().contains("┃"))
    }

    @Test("updates the reserved scrollbar column at runtime")
    func runtimeScrollbar() {
        let scroll = ScrollView(Text("123456", paddingX: 0, paddingY: 0), options: ScrollViewOptions(scrollbar: .always))
        let stack = HStack(children: [.component(scroll)], options: StackOptions(align: .start))
        let always = renderLayoutFrame(root: stack, width: 6, height: 2) {}
        #expect(always.lines.map(stripTerminalSequences) == ["12345┃", "6    ┃"])
        #expect(always.root.children[0].children[0].rect.width == 5)
        scroll.setScrollbar(.hidden)
        let hidden = renderLayoutFrame(root: stack, width: 6, height: 2) {}
        #expect(stripTerminalSequences(hidden.lines[0]) == "123456")
        #expect(hidden.root.children[0].children[0].rect.width == 6)
    }

    @Test("disableFollow suppresses following at the current end through layout")
    func followSuppression() {
        let scroll = ScrollView(B2LayoutContent([]), options: ScrollViewOptions(follow: .end, scrollbar: .auto))
        var requests = 0
        scroll.updateLayout(contentHeight: 10, viewportHeight: 4) { requests += 1 }
        #expect(scroll.isFollowingEnd)
        scroll.scrollTo(6, options: ScrollViewScrollToOptions(disableFollow: true))
        #expect(!scroll.isFollowingEnd)
        #expect(requests == 1)
        #expect(!scroll.isScrollbarVisible)
        scroll.updateLayout(contentHeight: 10, viewportHeight: 4) { requests += 1 }
        #expect(!scroll.isFollowingEnd)
        scroll.scrollTo(6, options: ScrollViewScrollToOptions(disableFollow: true))
        #expect(requests == 1)
        scroll.updateLayout(contentHeight: 11, viewportHeight: 4) { requests += 1 }
        #expect(scroll.scrollTop == 6)
        #expect(!scroll.isFollowingEnd)
        scroll.updateLayout(contentHeight: 10, viewportHeight: 4) { requests += 1 }
        #expect(scroll.isFollowingEnd)
    }

    @Test("scrollBy re-arms following without movement or scrollbar activity")
    func scrollByRearmsFollow() {
        let scroll = ScrollView(B2LayoutContent([]), options: ScrollViewOptions(follow: .end, scrollbar: .auto))
        var requests = 0
        scroll.updateLayout(contentHeight: 10, viewportHeight: 4) { requests += 1 }
        scroll.scrollTo(6, options: ScrollViewScrollToOptions(disableFollow: true))
        #expect(scroll.scrollBy(0) == 0)
        #expect(!scroll.isFollowingEnd)
        #expect(scroll.scrollBy(1) == 1)
        #expect(scroll.isFollowingEnd)
        #expect(requests == 2)
        #expect(!scroll.isScrollbarVisible)
    }

    @Test("absolute scroll and end commands clear follow suppression")
    func explicitFollowCommands() {
        let scroll = ScrollView(B2LayoutContent([]), options: ScrollViewOptions(follow: .end))
        scroll.updateLayout(contentHeight: 10, viewportHeight: 4) {}
        scroll.scrollTo(6, options: ScrollViewScrollToOptions(disableFollow: true))
        scroll.scrollTo(6)
        #expect(scroll.isFollowingEnd)
        scroll.scrollTo(6, options: ScrollViewScrollToOptions(disableFollow: true))
        scroll.scrollToEnd()
        #expect(scroll.isFollowingEnd)
        scroll.scrollTo(6, options: ScrollViewScrollToOptions(disableFollow: true))
        scroll.scrollToStart()
        scroll.updateLayout(contentHeight: 4, viewportHeight: 4) {}
        #expect(scroll.isFollowingEnd)
    }

    @Test("active scrollbar changes request a render and prevent its timer from hiding it")
    func activeRequestsRender() async throws {
        let scroll = ScrollView(B2LayoutContent([]), options: ScrollViewOptions(scrollbar: .auto, scrollbarHideDelayMilliseconds: 10))
        var requests = 0
        scroll.updateLayout(contentHeight: 10, viewportHeight: 4) { requests += 1 }
        scroll.setScrollbarActive(true)
        #expect(scroll.isScrollbarActive)
        #expect(scroll.isScrollbarVisible)
        #expect(requests == 1)
        scroll.setScrollbarActive(true)
        #expect(requests == 1)
        try await Task.sleep(for: .milliseconds(40))
        #expect(scroll.isScrollbarVisible)
        scroll.setScrollbarActive(false)
        #expect(!scroll.isScrollbarActive)
        #expect(requests == 2)
        try await Task.sleep(for: .milliseconds(40))
        #expect(!scroll.isScrollbarVisible)
        #expect(requests == 3)
    }

    @Test("hidden automatic geometry is available only when content overflows")
    func hiddenGeometry() {
        let scroll = ScrollView(B2LayoutContent(Array(repeating: "x", count: 8)), options: ScrollViewOptions(scrollbar: .auto))
        let frame = renderLayoutFrame(root: scroll, width: 6, height: 4) {}
        #expect(getScrollbarGeometry(frame.root) == nil)
        #expect(getScrollbarGeometry(frame.root, includeHiddenAuto: true)?.column == 5)
        scroll.setScrollbar(.hidden)
        #expect(getScrollbarGeometry(frame.root, includeHiddenAuto: true) == nil)
        let fitting = ScrollView(B2LayoutContent(["x"]), options: ScrollViewOptions(scrollbar: .auto))
        let fitFrame = renderLayoutFrame(root: fitting, width: 6, height: 4) {}
        #expect(getScrollbarGeometry(fitFrame.root, includeHiddenAuto: true) == nil)
    }

    @Test("layout hit paths sort by layer before depth and respect clipping")
    func hitPathOrder() {
        let content = B2LayoutContent(["line"])
        let scroll = ScrollView(content)
        let frame = renderLayoutFrame(root: VStack([scroll]), width: 6, height: 4) {}
        let hits = getLayoutBoxesAt(frame: frame, x: 0, y: 0)
        #expect(hits.map { ObjectIdentifier($0.component) } == [ObjectIdentifier(content), ObjectIdentifier(scroll), ObjectIdentifier(frame.root.component)])
        frame.root.layer = 1
        #expect(getLayoutBoxesAt(frame: frame, x: 0, y: 0).first === frame.root)
        #expect(getLayoutBoxesAt(frame: frame, x: 6, y: 0).isEmpty)
    }

    @Test("full-width untouched rows retain source ANSI and omit padding")
    func fullWidthSource() {
        let source = "\u{1B}[31mshort\u{1B}[39m"
        let frame = renderLayoutFrame(root: B2LayoutContent([source]), width: 20, height: 2) {}
        #expect(frame.lines == [source, ""])
    }
}
