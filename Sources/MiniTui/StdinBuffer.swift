import Foundation

private let esc = "\u{001B}"
private let bracketedPasteStart = "\u{001B}[200~"
private let bracketedPasteEnd = "\u{001B}[201~"

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

public final class StdinBuffer {
    public var onData: ((String) -> Void)?
    public var onPaste: ((String) -> Void)?

    private var buffer = ""
    private var timeoutWorkItem: DispatchWorkItem?
    private let timeoutSeconds: TimeInterval
    private var pasteMode = false
    private var pasteBuffer = ""

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
            onData?("")
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

                onPaste?(pastedContent)

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
                    onData?(sequence)
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

                onPaste?(pastedContent)

                if !remaining.isEmpty {
                    process(remaining)
                }
            }
            return
        }

        let result = extractCompleteSequences(buffer)
        buffer = result.remainder

        for sequence in result.sequences {
            onData?(sequence)
        }

        if !buffer.isEmpty {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let flushed = self.flush()
                for sequence in flushed {
                    self.onData?(sequence)
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

    private func decode(_ data: Data) -> String {
        if data.count == 1, let byte = data.first, byte > 127 {
            let value = byte - 128
            if let scalar = UnicodeScalar(Int(value)) {
                return esc + String(scalar)
            }
        }
        return String(decoding: data, as: UTF8.self)
    }
}
