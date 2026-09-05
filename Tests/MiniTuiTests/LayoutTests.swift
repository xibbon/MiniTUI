import Testing
@testable import MiniTui

@MainActor
private final class LayoutTestComponent: Component {
    var output: [String]
    private(set) var renderedWidths: [Int] = []

    init(_ output: [String]) {
        self.output = output
    }

    func render(width: Int) -> [String] {
        renderedWidths.append(width)
        return output
    }

    func invalidate() {
        renderedWidths.removeAll()
    }
}

@Suite("Constraint layout")
@MainActor
struct LayoutTests {
    @Test("VStack allocates fixed basis and divides grow and shrink space")
    func verticalSizing() {
        let fixed = VStack()
        fixed.addChild(LayoutTestComponent(["A"]), options: StackEntryOptions(basis: .points(2), shrink: 0))
        fixed.addChild(LayoutTestComponent(["B"]), options: StackEntryOptions(basis: .points(3), shrink: 0))
        let fixedFrame = renderLayoutFrame(root: fixed, width: 8, height: 8) {}
        #expect(fixedFrame.root.children.map(\.rect.height) == [2, 3])

        let growing = VStack()
        growing.addChild(LayoutTestComponent(["A"]), options: StackEntryOptions(basis: .points(2), grow: 1))
        growing.addChild(LayoutTestComponent(["B"]), options: StackEntryOptions(basis: .points(2), grow: 1))
        let growFrame = renderLayoutFrame(root: growing, width: 8, height: 10) {}
        #expect(growFrame.root.children.map(\.rect.height) == [6, 4])

        let shrinking = VStack()
        shrinking.addChild(LayoutTestComponent(["A"]), options: StackEntryOptions(basis: .points(5), shrink: 1))
        shrinking.addChild(LayoutTestComponent(["B"]), options: StackEntryOptions(basis: .points(5), shrink: 1))
        let shrinkFrame = renderLayoutFrame(root: shrinking, width: 8, height: 6) {}
        #expect(shrinkFrame.root.children.map(\.rect.height) == [2, 4])
    }

    @Test("minimum and maximum sizes clamp, including inside a nested stack")
    func sizeClampsAndNestedMinimum() {
        let clamped = VStack()
        clamped.addChild(LayoutTestComponent(["A"]), options: StackEntryOptions(basis: .points(1), minSize: 3))
        clamped.addChild(LayoutTestComponent(["B"]), options: StackEntryOptions(basis: .points(8), maxSize: 2))
        let clampFrame = renderLayoutFrame(root: clamped, width: 8, height: 8) {}
        #expect(clampFrame.root.children.map(\.rect.height) == [3, 2])

        let inner = VStack()
        inner.addChild(LayoutTestComponent(["nested"]), options: StackEntryOptions(basis: .points(1), minSize: 4))
        let outer = VStack([inner])
        let nestedFrame = renderLayoutFrame(root: outer, width: 8, height: 6) {}
        #expect(nestedFrame.root.children[0].rect.height == 4)
        #expect(nestedFrame.root.children[0].children[0].rect.height == 4)
    }

    @Test("viewport visibility removes hidden entries")
    func viewportVisibility() {
        let stack = VStack()
        stack.addChild(
            LayoutTestComponent(["hidden"]),
            options: StackEntryOptions(visible: { $0.width >= 20 })
        )
        stack.addChild(LayoutTestComponent(["shown"]))

        let frame = renderLayoutFrame(root: stack, width: 10, height: 3) {}
        #expect(frame.root.children.count == 1)
        #expect(stripTerminalSequences(frame.lines[0]).contains("shown"))
        #expect(!frame.lines.joined().contains("hidden"))
    }

    @Test("vertical gaps paint blank rows")
    func verticalGap() {
        let stack = VStack(children: [], options: StackOptions(gap: 2))
        stack.addChild(LayoutTestComponent(["A"]), options: StackEntryOptions(basis: .points(1)))
        stack.addChild(LayoutTestComponent(["B"]), options: StackEntryOptions(basis: .points(1)))

        let frame = renderLayoutFrame(root: stack, width: 4, height: 4) {}
        let plain = frame.lines.map(stripTerminalSequences)
        #expect(plain[0].hasPrefix("A"))
        #expect(plain[1].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(plain[2].trimmingCharacters(in: .whitespaces).isEmpty)
        #expect(plain[3].hasPrefix("B"))
    }

    @Test("each horizontal alignment mode positions child height correctly")
    func horizontalAlignment() {
        func childBox(for align: StackLayoutNode.Align) -> LayoutBox {
            let stack = HStack(children: [], options: StackOptions(align: align))
            stack.addChild(LayoutTestComponent(["X"]), options: StackEntryOptions(basis: .points(2)))
            return renderLayoutFrame(root: stack, width: 4, height: 5) {}.root.children[0]
        }

        let stretch = childBox(for: .stretch)
        #expect(stretch.rect.y == 0)
        #expect(stretch.rect.height == 5)
        let start = childBox(for: .start)
        #expect(start.rect.y == 0)
        #expect(start.rect.height == 1)
        let center = childBox(for: .center)
        #expect(center.rect.y == 2)
        #expect(center.rect.height == 1)
        let end = childBox(for: .end)
        #expect(end.rect.y == 4)
        #expect(end.rect.height == 1)
    }

    @Test("HStack splits width and clips children that ignore their allocation")
    func horizontalSplitAndClip() {
        let stack = HStack(children: [], options: StackOptions(gap: 1))
        stack.addChild(LayoutTestComponent(["ABCDEFG"]), options: StackEntryOptions(basis: .points(3), shrink: 0))
        stack.addChild(LayoutTestComponent(["XYZ123"]), options: StackEntryOptions(basis: .points(3), shrink: 0))

        let frame = renderLayoutFrame(root: stack, width: 7, height: 1) {}
        #expect(frame.root.children.map(\.rect.width) == [3, 3])
        #expect(stripTerminalSequences(frame.lines[0]) == "ABC XYZ")
    }

    @Test("plain children are measured by rendered lines and reused from the frame cache")
    func plainChildMeasurementAndCache() {
        let child = LayoutTestComponent(["one", "two"])
        let stack = VStack([child])
        let frame = renderLayoutFrame(root: stack, width: 8, height: 4) {}

        #expect(frame.root.children[0].rect.height == 2)
        #expect(child.renderedWidths == [8])
    }

    @Test("rendered frames have fixed height and preserve full-width source lines")
    func frameBounds() {
        let child = LayoutTestComponent(["this child ignores its width", "second", "third"])
        let frame = renderLayoutFrame(root: child, width: 5, height: 2) {}
        #expect(frame.lines.count == 2)
        #expect(frame.lines == Array(child.output.prefix(2)))

        let clamped = renderLayoutFrame(root: child, width: 0, height: 0) {}
        #expect(clamped.width == 1)
        #expect(clamped.height == 1)
        #expect(clamped.lines.count == 1)
        #expect(clamped.lines == Array(child.output.prefix(1)))
    }
}
