import Foundation

/// Simple cancellation token for coordinating cancelable work.
///
/// SAFETY: cancellation state and handlers are protected by `lock`; handlers are
/// invoked outside the lock so callbacks can safely register more work.
public final class CancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [() -> Void] = []

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Create a new cancellation signal.
    public init() {}

    /// Cancel the signal and invoke all registered handlers once.
    public func cancel() {
        let handlersToRun: [() -> Void] = lock.withLock {
            guard !cancelled else { return [] }
            cancelled = true
            let snapshot = handlers
            handlers.removeAll()
            return snapshot
        }
        for handler in handlersToRun {
            handler()
        }
    }

    /// Register a handler to run on cancellation.
    public func onCancel(_ handler: @escaping () -> Void) {
        let shouldRunNow = lock.withLock {
            if cancelled {
                return true
            }
            handlers.append(handler)
            return false
        }
        if shouldRunNow {
            handler()
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
        let kb = getKeybindings()
        if kb.matches(data, TUIKeybinding.selectCancel) {
            cancellationSignal.cancel()
            onAbort?()
        }
    }

    /// Stop the loader animation.
    public func dispose() {
        stop()
    }
}
