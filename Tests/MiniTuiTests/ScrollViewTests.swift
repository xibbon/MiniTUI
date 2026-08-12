import Testing
@testable import MiniTui

@MainActor
private final class ScrollContentComponent: Component {
    var lines: [String]

    init(count: Int) {
        lines = (0..<count).map(String.init)
    }

    func render(width: Int) -> [String] {
        lines
    }
}

@Suite("ScrollView layout")
@MainActor
struct ScrollViewTests {
    @Test("scrollTop clamps and scrollbar thumb tracks its position")
    func clampAndGeometry() {
        let content = ScrollContentComponent(count: 10)
        let scrollView = ScrollView(content, options: ScrollViewOptions(scrollbar: .always))
        var renderRequests = 0
        var frame = renderLayoutFrame(root: scrollView, width: 10, height: 4) {
            renderRequests += 1
        }
        let topGeometry = getScrollbarGeometry(frame.root)
        #expect(topGeometry?.thumbHeight == 2)
        #expect(topGeometry?.thumbTop == 0)
        #expect(topGeometry?.maxScrollTop == 6)

        scrollView.scrollTo(100)
        #expect(scrollView.scrollTop == 6)
        frame = renderLayoutFrame(root: scrollView, width: 10, height: 4) {
            renderRequests += 1
        }
        let bottomGeometry = getScrollbarGeometry(frame.root)
        #expect(bottomGeometry?.thumbTop == 2)
        #expect(renderRequests > 0)

        content.lines = ["short", "content"]
        scrollView.invalidate()
        _ = renderLayoutFrame(root: scrollView, width: 10, height: 4) {
            renderRequests += 1
        }
        #expect(scrollView.scrollTop == 0)
    }

    @Test("full-height content has no automatic scrollbar")
    func noScrollbarForFullHeightContent() {
        let scrollView = ScrollView(
            ScrollContentComponent(count: 4),
            options: ScrollViewOptions(scrollbar: .auto)
        )
        let frame = renderLayoutFrame(root: scrollView, width: 10, height: 4) {}
        #expect(getScrollbarGeometry(frame.root) == nil)
    }

    @Test("scroll view hit testing returns innermost first")
    func nestedHitTestOrder() {
        let inner = ScrollView(ScrollContentComponent(count: 3))
        let outer = ScrollView(inner)
        let frame = renderLayoutFrame(root: outer, width: 8, height: 3) {}

        let matches = getScrollViewsAt(frame: frame, x: 0, y: 0)
        #expect(matches.count == 2)
        #expect(matches[0] === inner)
        #expect(matches[1] === outer)
        #expect(getScrollViewBox(frame: frame, scrollView: inner)?.scrollView === inner)
    }
}
