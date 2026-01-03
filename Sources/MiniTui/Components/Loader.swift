import Foundation

/// Animated spinner with a message that re-renders on a timer.
@MainActor
public class Loader: Text {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
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
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.currentFrame = (self.currentFrame + 1) % self.frames.count
            self.updateDisplay()
        }
        timer.resume()
        self.timer = timer
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

    private func updateDisplay() {
        let frame = frames[currentFrame]
        setText("\(spinnerColorFn(frame)) \(messageColorFn(message))")
        ui?.requestRender()
    }
}
