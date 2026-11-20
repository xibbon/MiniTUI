import Foundation
import Testing
@testable import MiniTui

@MainActor
private final class BenchmarkLeaf: Component {
    let lines: [String]
    init(_ lines: [String]) { self.lines = lines }
    func render(width: Int) -> [String] { lines }
}

@MainActor
@Suite("MT1 opt-in container benchmark")
struct MT1ContainerBenchmarkTests {
    @Test("prints three-level transcript reuse measurements when requested")
    func transcript() {
        guard ProcessInfo.processInfo.environment["MINITUI_MT1_BENCH"] == "1" else { return }
        let rows = (0..<20_000).map { "\($0): assistant transcript line" }
        let leaf = BenchmarkLeaf(rows)
        let inner = Container()
        inner.addChild(leaf)
        let middle = Container()
        middle.addChild(inner)
        let root = Container()
        root.addChild(middle)

        // The previous implementation concatenated once at every nesting level.
        func oldRender() -> [String] {
            var a: [String] = []
            a.append(contentsOf: leaf.render(width: 80))
            var b: [String] = []
            b.append(contentsOf: a)
            var c: [String] = []
            c.append(contentsOf: b)
            return c
        }
        func nanos(_ body: () -> Void) -> UInt64 {
            let start = DispatchTime.now().uptimeNanoseconds
            body()
            return DispatchTime.now().uptimeNanoseconds - start
        }
        func median(_ samples: [UInt64]) -> UInt64 {
            samples.sorted()[samples.count / 2]
        }
        let oldFirst = nanos { _ = oldRender() }
        let oldRepeated = median((0..<40).map { _ in nanos { _ = oldRender() } })
        let newFirst = nanos { _ = root.render(width: 80) }
        let newRepeated = median((0..<40).map { _ in nanos { _ = root.render(width: 80) } })
        #expect(root.childRecordRebuildCount == 1)
        #expect(middle.childRecordRebuildCount == 1)
        #expect(inner.childRecordRebuildCount == 1)
        // Line-buffer allocations: old 3 x 20,000 slots each render; new 3 on
        // the first render and zero on unchanged renders. Small parts arrays
        // and transient Swift runtime allocations are excluded from this count.
        print("MT1_CONTAINER_BENCH old_first_ns=\(oldFirst) old_repeat_median_ns=\(oldRepeated) new_first_ns=\(newFirst) new_repeat_median_ns=\(newRepeated) old_line_buffer_allocations=3/3 new_line_buffer_allocations=3/0 old_line_slots=60000/60000 new_line_slots=60000/0")
    }
}
