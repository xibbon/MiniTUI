import Testing
@testable import MiniTui

@Suite("Wheel scroll acceleration")
struct WheelScrollTests {
    private func counts(_ accelerator: WheelScrollAccelerator, _ times: [Double], direction: Int = 1) -> [Int] {
        times.map { accelerator.next(direction: direction, now: $0) }
    }

    @Test("fixed line counts ignore event timing")
    func fixedLines() {
        let accelerator = WheelScrollAccelerator(lines: .lines(3), accelerate: true)
        #expect(counts(accelerator, [0, 10, 20, 1000]) == [3, 3, 3, 3])
        accelerator.setLines(.lines(0))
        #expect(accelerator.next(direction: 1, now: 2000) == 1)
    }

    @Test("local macOS input stays at one line")
    func nativeAcceleration() {
        let accelerator = WheelScrollAccelerator(lines: .auto, accelerate: false)
        #expect(counts(accelerator, [0, 10, 20, 30]) == [1, 1, 1, 1])
    }

    @Test("auto mode follows wheel speed")
    func wheelSpeed() {
        let accelerator = WheelScrollAccelerator(lines: .auto, accelerate: true)
        #expect(counts(accelerator, [0, 150, 300, 450]) == [1, 1, 1, 1])
        #expect(counts(accelerator, [1000, 1050, 1100, 1150]) == [1, 2, 2, 2])
        #expect(counts(accelerator, [2000, 2020, 2040, 2060]) == [1, 5, 5, 5])
        #expect(counts(accelerator, [3000, 3010, 3020, 3030]) == [1, 6, 6, 6])
    }

    @Test("one notch can have several events")
    func burst() {
        let accelerator = WheelScrollAccelerator(lines: .auto, accelerate: true)
        #expect(counts(accelerator, [0, 3, 6, 9]) == [1, 1, 1, 1])
    }

    @Test("direction changes and pauses reset the gesture")
    func reset() {
        let accelerator = WheelScrollAccelerator(lines: .auto, accelerate: true)
        #expect(counts(accelerator, [0, 20, 40]) == [1, 5, 5])
        #expect(accelerator.next(direction: -1, now: 60) == 1)
        #expect(counts(accelerator, [500, 520]) == [1, 5])
        accelerator.setLines(.auto)
        #expect(accelerator.next(direction: 1, now: 540) == 1)
    }

    @Test("fractional lines carry to later events")
    func fraction() {
        let accelerator = WheelScrollAccelerator(lines: .auto, accelerate: true)
        #expect(counts(accelerator, [0, 40, 80, 120, 160]) == [1, 2, 3, 2, 3])
    }
}
