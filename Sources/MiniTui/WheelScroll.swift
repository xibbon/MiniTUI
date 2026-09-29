import Foundation

/// The number of lines moved for each wheel event.
public enum WheelScrollLines: Sendable, Equatable, ExpressibleByIntegerLiteral {
    case auto
    case lines(Int)

    public init(integerLiteral value: Int) {
        self = .lines(value)
    }
}

/// Converts wheel events to line counts. Pass a monotonic time in milliseconds to `next`.
public final class WheelScrollAccelerator {
    private var lines: WheelScrollLines
    private let accelerate: Bool
    private var lastTime = -Double.infinity
    private var lastDirection = 0
    private var averageGap: Double?
    private var carry = 0.0

    public init(
        lines: WheelScrollLines = .auto,
        accelerate: Bool? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.lines = lines
        self.accelerate = accelerate ?? !Self.terminalAcceleratesWheel(environment: environment)
    }

    public func setLines(_ lines: WheelScrollLines) {
        self.lines = lines
        reset()
    }

    /// Returns a positive line count for one event at `now` milliseconds.
    public func next(direction: Int, now: Double) -> Int {
        if case let .lines(count) = lines { return max(1, count) }
        if !accelerate { return 1 }

        let gap = now - lastTime
        let sameGesture = direction == lastDirection && gap <= 200
        lastTime = now
        lastDirection = direction
        if !sameGesture {
            averageGap = nil
            carry = 0
            return 1
        }
        if gap < 5 { return 1 }

        averageGap = averageGap.map { ($0 + gap) / 2 } ?? gap
        let value = min(6, max(1, 100 / averageGap!)) + carry
        let whole = Int(floor(value))
        carry = value - Double(whole)
        return whole
    }

    private func reset() {
        lastTime = -.infinity
        lastDirection = 0
        averageGap = nil
        carry = 0
    }

    private static func terminalAcceleratesWheel(environment: [String: String]) -> Bool {
        #if os(macOS)
        return environment["SSH_CONNECTION"] == nil
            && environment["SSH_CLIENT"] == nil
            && environment["SSH_TTY"] == nil
        #else
        return false
        #endif
    }
}
