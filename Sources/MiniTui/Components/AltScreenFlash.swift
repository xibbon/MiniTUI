import Foundation

/// Stacked transient messages composited by the alternate-screen renderer.
@MainActor
public final class AltScreenFlashContainer: Component {
    private struct Entry {
        let id: Int
        let message: String
        let task: Task<Void, Never>
    }

    private var entries: [Entry] = []
    private var nextID = 0
    private let requestRender: () -> Void

    public init(requestRender: @escaping () -> Void) {
        self.requestRender = requestRender
    }

    public func flash(_ message: String, durationMilliseconds: Int = 1_000) {
        let id = nextID
        nextID += 1
        let delay = max(0, durationMilliseconds)
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self,
                  let index = self.entries.firstIndex(where: { $0.id == id }) else {
                return
            }
            self.entries.remove(at: index)
            self.requestRender()
        }
        entries.append(Entry(id: id, message: message, task: task))
        requestRender()
    }

    public func dispose() {
        for entry in entries {
            entry.task.cancel()
        }
        entries.removeAll()
    }

    public func render(width: Int) -> [String] {
        entries.map { entry in
            let message = truncateToWidth(" \(entry.message) ", maxWidth: width, ellipsis: "")
            return "\u{001B}[7m" + message + "\u{001B}[27m"
        }
    }
}
