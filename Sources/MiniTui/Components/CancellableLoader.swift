import Foundation

/// Simple cancellation token for coordinating cancelable work.
public final class CancellationSignal: @unchecked Sendable {
    private(set) var isCancelled = false
    private var handlers: [() -> Void] = []

    /// Create a new cancellation signal.
    public init() {}

    /// Cancel the signal and invoke all registered handlers once.
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        for handler in handlers {
            handler()
        }
        handlers.removeAll()
    }

    /// Register a handler to run on cancellation.
    public func onCancel(_ handler: @escaping () -> Void) {
        if isCancelled {
            handler()
        } else {
            handlers.append(handler)
        }
    }
}

/// Loader that can be cancelled with Escape and exposes a cancellation signal.
public final class CancellableLoader: Loader {
    private let cancellationSignal = CancellationSignal()
    /// Called when the loader is aborted via Escape.
    public var onAbort: (() -> Void)?

    /// Expose the cancellation signal for consumers.
    public var signal: CancellationSignal {
        return cancellationSignal
    }

    /// Return true after cancellation.
    public var aborted: Bool {
        return cancellationSignal.isCancelled
    }

    /// Handle Escape to cancel the loader.
    public override func handleInput(_ data: String) {
        let kb = getEditorKeybindings()
        if kb.matches(data, .selectCancel) {
            cancellationSignal.cancel()
            onAbort?()
        }
    }

    /// Stop the loader animation.
    public func dispose() {
        stop()
    }
}
