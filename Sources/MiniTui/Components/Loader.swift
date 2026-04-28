import Foundation

/// v0.68.0: customizable working-indicator frames + animation interval. Pass `frames: [single]`
/// for a static indicator, an empty `frames` array for a hidden indicator (caller renders its
/// own working state), or omit to keep the default Braille spinner. `intervalMs` defaults to 80.
public struct LoaderIndicatorOptions: Sendable {
    public var frames: [String]?
    public var intervalMs: Int?

    public init(frames: [String]? = nil, intervalMs: Int? = nil) {
        self.frames = frames
        self.intervalMs = intervalMs
    }
}

/// Animated spinner with a message that re-renders on a timer.
@MainActor
public class Loader: Text {
    private static let defaultFrames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private static let defaultIntervalMs = 80

    private var frames: [String] = Loader.defaultFrames
    private var intervalMs: Int = Loader.defaultIntervalMs
    private var currentFrame = 0
    private var timer: DispatchSourceTimer?
    private weak var ui: TUI?

    private let spinnerColorFn: (String) -> String
    private let messageColorFn: (String) -> String
    private var message: String

    /// Create and start a loader tied to a TUI instance.
    public init(
        ui: TUI,
        spinnerColorFn: @escaping (String) -> String,
        messageColorFn: @escaping (String) -> String,
        message: String = "Loading..."
    ) {
        self.ui = ui
        self.spinnerColorFn = spinnerColorFn
        self.messageColorFn = messageColorFn
        self.message = message
        super.init("", paddingX: 1, paddingY: 0, customBgFn: nil)
        start()
    }

    /// Render the loader with a leading blank line for spacing.
    public override func render(width: Int) -> [String] {
        return [""] + super.render(width: width)
    }

    /// Start the animation timer.
    public func start() {
        updateDisplay()
        if frames.count > 1 {
            scheduleTimer()
        }
    }

    /// Stop the animation timer.
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Update the displayed message.
    public func setMessage(_ message: String) {
        self.message = message
        updateDisplay()
    }

    /// v0.68.0: replace the loader frames and animation interval at runtime.
    /// - `options.frames == nil` keeps existing frames; `[]` hides the indicator entirely;
    ///   single-element array becomes a static indicator (no timer).
    /// - `options.intervalMs == nil` keeps existing interval.
    /// v0.68.0 also: custom frames render verbatim (no theme accent override) — extension
    /// authors own coloring when they customize. Apply by passing identity color closures
    /// via the standard initializer; this method only changes frames/interval.
    public func setIndicator(_ options: LoaderIndicatorOptions) {
        if let newFrames = options.frames {
            frames = newFrames
            currentFrame = 0
        }
        if let newInterval = options.intervalMs {
            intervalMs = newInterval
        }
        timer?.cancel()
        timer = nil
        updateDisplay()
        if frames.count > 1 {
            scheduleTimer()
        }
    }

    private func scheduleTimer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + .milliseconds(intervalMs), repeating: .milliseconds(intervalMs))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.currentFrame = (self.currentFrame + 1) % self.frames.count
            self.updateDisplay()
        }
        timer.resume()
        self.timer = timer
    }

    private func updateDisplay() {
        if frames.isEmpty {
            // Hidden indicator: render only the message (callers own working-state UI).
            setText(messageColorFn(message))
            ui?.requestRender()
            return
        }
        let frame = frames[currentFrame]
        setText("\(spinnerColorFn(frame)) \(messageColorFn(message))")
        ui?.requestRender()
    }
}
