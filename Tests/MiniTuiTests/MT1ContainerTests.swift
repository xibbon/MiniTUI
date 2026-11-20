import Testing
@testable import MiniTui

@MainActor
private final class ChangingLines: Component {
    var lines: [String]
    var renders = 0
    var hits = 0

    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { renders += 1; return lines }
    func handleMouse(_ event: TuiMouseEvent) -> TuiMouseEventResult? {
        hits += 1
        return TuiMouseEventResult(handled: true)
    }
}

@MainActor
private final class DecoratingContainer: Container {
    override func render(width: Int) -> [String] {
        var lines = super.render(width: width)
        if !lines.isEmpty { lines[0] = "host:" + lines[0] }
        return lines
    }
}

@MainActor
@Suite("container output reuse")
struct MT1ContainerTests {
    @Test("returns the same lines while children are unchanged")
    func unchanged() {
        let child = ChangingLines(["hello", ""])
        let inner = Container()
        inner.addChild(child)
        let outer = Container()
        outer.addChild(inner)
        let first = outer.render(width: 20)
        let innerBuilds = inner.childRecordRebuildCount
        let outerBuilds = outer.childRecordRebuildCount
        #expect(outer.render(width: 20) == first)
        #expect(inner.childRecordRebuildCount == innerBuilds)
        #expect(outer.childRecordRebuildCount == outerBuilds)
        #expect(child.renders == 2)
        child.lines[0] = "changed"
        #expect(outer.render(width: 20) == ["changed", ""])
        #expect(first == ["hello", ""])
        #expect(inner.childRecordRebuildCount == innerBuilds + 1)
        #expect(outer.childRecordRebuildCount == outerBuilds + 1)
    }

    @Test("re-renders when children are added or the width changes")
    func changedChildrenOrWidth() {
        let container = Container()
        container.addChild(ChangingLines(["a"]))
        #expect(container.render(width: 20) == ["a"])
        let initial = container.childRecordRebuildCount
        container.addChild(ChangingLines(["b"]))
        #expect(container.render(width: 20) == ["a", "b"])
        #expect(container.childRecordRebuildCount == initial + 1)
        #expect(container.render(width: 10) == ["a", "b"])
        #expect(container.childRecordRebuildCount == initial + 2)
    }

    @Test("reuses box output while its children are unchanged")
    func boxReuse() {
        let child = ChangingLines(["boxed"])
        let box = Box(paddingX: 1, paddingY: 0)
        box.addChild(child)
        let first = box.render(width: 20)
        #expect(box.render(width: 20) == first)
        #expect(box.childRecordRebuildCount == 1)
        #expect(box.outputRebuildCount == 1)
        child.lines = ["next"]
        #expect(box.render(width: 20).first?.contains("next") == true)
        #expect(box.outputRebuildCount == 2)
        #expect(first.first?.contains("boxed") == true)
    }

    @Test("dispatches mouse events by the rendered child heights")
    func mouseHeights() {
        let first = ChangingLines(["a", "b"])
        let second = ChangingLines(["c"])
        let container = Container()
        container.addChild(first)
        container.addChild(second)
        _ = container.render(width: 20)
        _ = container.handleMouse(TuiMouseEvent(type: .wheel, button: .none, x: 0, y: 2,
            screenX: 0, screenY: 2, width: 20, height: 3, wheelDelta: 1))
        _ = container.handleMouse(TuiMouseEvent(type: .wheel, button: .none, x: 0, y: 1,
            screenX: 0, screenY: 1, width: 20, height: 3, wheelDelta: 1))
        #expect(first.hits == 1)
        #expect(second.hits == 1)
    }

    @Test("a host changes a render snapshot without changing cached output")
    func hostSnapshot() {
        let child = ChangingLines(["raw"])
        let host = DecoratingContainer()
        host.addChild(child)
        let parent = Container()
        parent.addChild(host)
        let snapshot = parent.render(width: 20)
        var childSnapshot = child.render(width: 20)
        childSnapshot[0] = "changed by host"
        var hostSnapshot = host.render(width: 20)
        hostSnapshot[0] = "changed again"
        #expect(parent.render(width: 20) == snapshot)
        #expect(host.render(width: 20) == ["host:raw"])
        #expect(child.render(width: 20) == ["raw"])
        #expect(parent.childRecordRebuildCount == 1)
    }

    @Test("a new background formatter changes real lines despite an unchanged sample")
    func backgroundFormatter() {
        let box = Box(paddingX: 0, paddingY: 0, bgFn: { text in text == "test" ? text : "old:" + text })
        box.addChild(ChangingLines(["line"]))
        let old = box.render(width: 8)
        box.setBgFn { text in text == "test" ? text : "new:" + text }
        let new = box.render(width: 8)
        #expect(old.first?.hasPrefix("old:") == true)
        #expect(new.first?.hasPrefix("new:") == true)
    }

    @Test("invalidating the container clears its record")
    func invalidateRecord() {
        let container = Container()
        container.addChild(ChangingLines(["x"]))
        _ = container.render(width: 8)
        container.invalidate()
        _ = container.render(width: 8)
        #expect(container.childRecordRebuildCount == 2)
    }
}
