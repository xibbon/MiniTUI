import Foundation

final class KillBuffer: @unchecked Sendable {
    static let shared = KillBuffer()

    private var contents = ""
    private var lastActionWasKill = false
    private let lock = NSLock()

    func registerKill(_ text: String, append: Bool, prepend: Bool = false) {
        withLock {
            if append && lastActionWasKill {
                if prepend {
                    contents = text + contents
                } else {
                    contents += text
                }
            } else {
                contents = text
            }
            lastActionWasKill = true
        }
    }

    func breakChain() {
        withLock {
            lastActionWasKill = false
        }
    }

    func yank() -> String {
        return withLock {
            contents
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

public protocol KillBufferAware: Component {}
