import Foundation

final class KillBuffer: @unchecked Sendable {
    static let shared = KillBuffer()

    private var ring: [String] = []
    private var lastActionWasKill = false
    private let lock = NSLock()

    func registerKill(_ text: String, append: Bool, prepend: Bool = false) {
        withLock {
            guard !text.isEmpty else { return }
            if append && lastActionWasKill {
                let lastEntry = ring.popLast() ?? ""
                if prepend {
                    ring.append(text + lastEntry)
                } else {
                    ring.append(lastEntry + text)
                }
            } else {
                ring.append(text)
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
            ring.last ?? ""
        }
    }

    func rotate() -> String {
        return withLock {
            guard ring.count > 1 else { return ring.last ?? "" }
            let lastEntry = ring.removeLast()
            ring.insert(lastEntry, at: 0)
            return ring.last ?? ""
        }
    }

    func hasMultipleEntries() -> Bool {
        return withLock {
            ring.count > 1
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

public protocol KillBufferAware: Component {}
