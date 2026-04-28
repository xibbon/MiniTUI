import Foundation

private let esc = "\u{001B}"
private let bracketedPasteStart = "\u{001B}[200~"
private let bracketedPasteEnd = "\u{001B}[201~"

/// v0.70.1: decode CSI-u Ctrl+letter sequences inside bracketed-paste payloads.
///
/// When Kitty keyboard protocol is active and the user pastes text that contains a Ctrl+letter
/// sequence (e.g., the bytes `\x1B[99;5u` for Ctrl+c), the terminal forwards the escape literally
/// inside the bracketed paste. Without this fix, those escapes become visible characters in the
/// editor (`["` etc.). The upstream fix decodes printable Kitty Ctrl+letter sequences to their
/// printable lowercase character. Other escape sequences inside the paste are passed through
/// unchanged so binary content / unusual paste payloads aren't lossy.
private let pastedCtrlLetterRegex: NSRegularExpression = {
    // \x1B[<codepoint>;<modifier>u where codepoint is a lowercase ASCII letter (97–122)
    // and modifier == 5 (Ctrl alone, modifier_value = ctrl_bit + 1 = 4 + 1 = 5).
    return try! NSRegularExpression(pattern: "\\x1B\\[(9[7-9]|1[01][0-9]|12[0-2]);5u")
}()

private func decodeCtrlLetterEscapesInPaste(_ payload: String) -> String {
    let nsRange = NSRange(payload.startIndex..<payload.endIndex, in: payload)
    let matches = pastedCtrlLetterRegex.matches(in: payload, options: [], range: nsRange)
    guard !matches.isEmpty else { return payload }

    var result = ""
    var cursor = payload.startIndex
    for match in matches {
        guard let range = Range(match.range, in: payload),
              let codepointRange = Range(match.range(at: 1), in: payload),
              let codepoint = Int(payload[codepointRange]),
              let scalar = UnicodeScalar(codepoint) else {
            continue
        }
        result.append(contentsOf: payload[cursor..<range.lowerBound])
        result.append(Character(scalar))
        cursor = range.upperBound
    }
    result.append(contentsOf: payload[cursor...])
    return result
}

private enum SequenceStatus {
    case complete
    case incomplete
    case notEscape
}

private func isCompleteSequence(_ data: String) -> SequenceStatus {
    if !data.hasPrefix(esc) {
        return .notEscape
    }

    if data.count == 1 {
        return .incomplete
    }

    let afterEsc = String(data.dropFirst())

    if afterEsc.hasPrefix("[") {
        if afterEsc.hasPrefix("[M") {
            return data.count >= 6 ? .complete : .incomplete
        }
        return isCompleteCsiSequence(data)
    }

    if afterEsc.hasPrefix("]") {
        return isCompleteOscSequence(data)
    }

    if afterEsc.hasPrefix("P") {
        return isCompleteDcsSequence(data)
    }

    if afterEsc.hasPrefix("_") {
        return isCompleteApcSequence(data)
    }

    if afterEsc.hasPrefix("O") {
        return afterEsc.count >= 2 ? .complete : .incomplete
    }

    if afterEsc.count == 1 {
        return .complete
    }

    return .complete
}

private func isCompleteCsiSequence(_ data: String) -> SequenceStatus {
    if !data.hasPrefix("\(esc)[") {
        return .complete
    }

    if data.count < 3 {
        return .incomplete
    }

    let payload = String(data.dropFirst(2))
    guard let lastChar = payload.last, let lastScalar = lastChar.unicodeScalars.first else {
        return .incomplete
    }

    if lastScalar.value >= 0x40 && lastScalar.value <= 0x7E {
        if payload.hasPrefix("<") {
            if payload.range(of: "^<\\d+;\\d+;\\d+[Mm]$", options: .regularExpression) != nil {
                return .complete
            }
            if lastChar == "M" || lastChar == "m" {
                let inner = payload.dropFirst().dropLast()
                let parts = inner.split(separator: ";")
                let allDigits = parts.count == 3 && parts.allSatisfy { $0.allSatisfy(\.isNumber) }
                if allDigits {
                    return .complete
                }
            }
            return .incomplete
        }
        return .complete
    }

    return .incomplete
}

private func isCompleteOscSequence(_ data: String) -> SequenceStatus {
    if !data.hasPrefix("\(esc)]") {
        return .complete
    }

    if data.hasSuffix("\(esc)\\") || data.hasSuffix("\u{0007}") {
        return .complete
    }

    return .incomplete
}

private func isCompleteDcsSequence(_ data: String) -> SequenceStatus {
    if !data.hasPrefix("\(esc)P") {
        return .complete
    }

    if data.hasSuffix("\(esc)\\") {
        return .complete
    }

    return .incomplete
}

private func isCompleteApcSequence(_ data: String) -> SequenceStatus {
    if !data.hasPrefix("\(esc)_") {
        return .complete
    }

    if data.hasSuffix("\(esc)\\") {
        return .complete
    }

    return .incomplete
}

private func extractCompleteSequences(_ buffer: String) -> (sequences: [String], remainder: String) {
    var sequences: [String] = []
    var pos = 0

    while pos < buffer.count {
        let remaining = buffer.substring(from: pos, length: buffer.count - pos)
        if remaining.hasPrefix(esc) {
            var seqEnd = 1
            var found = false
            while seqEnd <= remaining.count {
                let candidate = remaining.substring(from: 0, length: seqEnd)
                let status = isCompleteSequence(candidate)

                switch status {
                case .complete:
                    sequences.append(candidate)
                    pos += seqEnd
                    found = true
                case .incomplete:
                    seqEnd += 1
                    continue
                case .notEscape:
                    sequences.append(candidate)
                    pos += seqEnd
                    found = true
                }
                if found { break }
            }

            if !found {
                return (sequences, remaining)
            }
        } else {
            sequences.append(remaining.substring(from: 0, length: 1))
            pos += 1
        }
    }

    return (sequences, "")
}

public struct StdinBufferOptions: Sendable {
    /// Maximum time to wait for sequence completion (default: 10ms).
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 0.01) {
        self.timeout = timeout
    }
}

public enum StdinBufferEvent: String, Sendable {
    case data
    case paste
}

private final class StdinBufferListeners {
    private let lock = NSLock()
    private var listeners: [StdinBufferEvent: [UUID: (String) -> Void]] = [
        .data: [:],
        .paste: [:],
    ]

    func add(_ event: StdinBufferEvent, _ listener: @escaping (String) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        var eventListeners = listeners[event] ?? [:]
        eventListeners[id] = listener
        listeners[event] = eventListeners
        lock.unlock()
        return id
    }

    func remove(_ event: StdinBufferEvent, id: UUID) {
        lock.lock()
        var eventListeners = listeners[event] ?? [:]
        eventListeners[id] = nil
        listeners[event] = eventListeners
        lock.unlock()
    }

    func emit(_ event: StdinBufferEvent, payload: String) {
        let handlers: [(String) -> Void]
        lock.lock()
        if let values = listeners[event]?.values {
            handlers = Array(values)
        } else {
            handlers = []
        }
        lock.unlock()
        for handler in handlers {
            handler(payload)
        }
    }
}

public final class StdinBuffer {
    public var onData: ((String) -> Void)?
    public var onPaste: ((String) -> Void)?

    private var buffer = ""
    private var timeoutWorkItem: DispatchWorkItem?
    private let timeoutSeconds: TimeInterval
    private var pasteMode = false
    private var pasteBuffer = ""
    private let listeners = StdinBufferListeners()

    public init(options: StdinBufferOptions = StdinBufferOptions()) {
        self.timeoutSeconds = options.timeout
    }

    public func process(_ data: Data) {
        process(decode(data))
    }

    public func process(_ text: String) {
        if let timeoutWorkItem {
            timeoutWorkItem.cancel()
            self.timeoutWorkItem = nil
        }

        if text.isEmpty && buffer.isEmpty {
            emit(.data, payload: "")
            return
        }

        buffer += text

        if pasteMode {
            pasteBuffer += buffer
            buffer = ""

            if let endRange = pasteBuffer.range(of: bracketedPasteEnd) {
                let pastedContent = String(pasteBuffer[..<endRange.lowerBound])
                let remaining = String(pasteBuffer[endRange.upperBound...])

                pasteMode = false
                pasteBuffer = ""

                emit(.paste, payload: decodeCtrlLetterEscapesInPaste(pastedContent))

                if !remaining.isEmpty {
                    process(remaining)
                }
            }
            return
        }

        if let startRange = buffer.range(of: bracketedPasteStart) {
            if startRange.lowerBound != buffer.startIndex {
                let beforePaste = String(buffer[..<startRange.lowerBound])
                let result = extractCompleteSequences(beforePaste)
                for sequence in result.sequences {
                    emit(.data, payload: sequence)
                }
            }

            buffer = String(buffer[startRange.upperBound...])
            pasteMode = true
            pasteBuffer = buffer
            buffer = ""

            if let endRange = pasteBuffer.range(of: bracketedPasteEnd) {
                let pastedContent = String(pasteBuffer[..<endRange.lowerBound])
                let remaining = String(pasteBuffer[endRange.upperBound...])

                pasteMode = false
                pasteBuffer = ""

                emit(.paste, payload: decodeCtrlLetterEscapesInPaste(pastedContent))

                if !remaining.isEmpty {
                    process(remaining)
                }
            }
            return
        }

        let result = extractCompleteSequences(buffer)
        buffer = result.remainder

        for sequence in result.sequences {
            emit(.data, payload: sequence)
        }

        if !buffer.isEmpty {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let flushed = self.flush()
                for sequence in flushed {
                    self.emit(.data, payload: sequence)
                }
            }
            timeoutWorkItem = workItem
            DispatchQueue.global().asyncAfter(deadline: .now() + timeoutSeconds, execute: workItem)
        }
    }

    public func flush() -> [String] {
        if let timeoutWorkItem {
            timeoutWorkItem.cancel()
            self.timeoutWorkItem = nil
        }

        guard !buffer.isEmpty else { return [] }
        let sequences = [buffer]
        buffer = ""
        return sequences
    }

    public func clear() {
        if let timeoutWorkItem {
            timeoutWorkItem.cancel()
            self.timeoutWorkItem = nil
        }
        buffer = ""
        pasteMode = false
        pasteBuffer = ""
    }

    public func getBuffer() -> String {
        return buffer
    }

    public func destroy() {
        clear()
    }

    public func on(_ event: StdinBufferEvent, _ listener: @escaping (String) -> Void) -> UUID {
        return listeners.add(event, listener)
    }

    public func off(_ event: StdinBufferEvent, _ token: UUID) {
        listeners.remove(event, id: token)
    }

    private func decode(_ data: Data) -> String {
        if data.count == 1, let byte = data.first, byte > 127 {
            let value = byte - 128
            if let scalar = UnicodeScalar(Int(value)) {
                return esc + String(scalar)
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func emit(_ event: StdinBufferEvent, payload: String) {
        switch event {
        case .data:
            onData?(payload)
        case .paste:
            onPaste?(payload)
        }
        listeners.emit(event, payload: payload)
    }
}
