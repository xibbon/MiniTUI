import Foundation
import MiniTui

private struct Cell {
    var char: Character
    var italic: Bool
}

final class VirtualTerminal: Terminal {
    private var inputHandler: ((String) -> Void)?
    private var resizeHandler: (() -> Void)?
    private var buffer: [[Cell]]
    private var cursorRow: Int = 0
    private var cursorCol: Int = 0
    private var italicActive = false
    private var lastFrame: [String] = []

    private let blankCell = Cell(char: " ", italic: false)

    var columns: Int
    var rows: Int

    init(columns: Int = 80, rows: Int = 24) {
        self.columns = columns
        self.rows = rows
        self.buffer = Array(repeating: Array(repeating: blankCell, count: columns), count: rows)
    }

    var kittyProtocolActive: Bool {
        return true
    }

    func start(onInput: @escaping (String) -> Void, onResize: @escaping () -> Void) {
        inputHandler = onInput
        resizeHandler = onResize
    }

    func stop() {
        inputHandler = nil
        resizeHandler = nil
    }

    func write(_ data: String) {
        if let frame = parseFrame(from: data) {
            lastFrame = frame
        }
        var index = data.startIndex
        while index < data.endIndex {
            let char = data[index]
            if char == "\u{001B}" {
                index = handleEscapeSequence(in: data, from: index)
                continue
            }
            if char == "\r" {
                cursorCol = 0
                index = data.index(after: index)
                continue
            }
            if char == "\n" {
                cursorRow += 1
                cursorCol = 0
                clampCursorRow()
                index = data.index(after: index)
                continue
            }

            if let scalar = char.unicodeScalars.first, scalar.value < 32 {
                index = data.index(after: index)
                continue
            }

            if cursorCol >= columns {
                cursorCol = 0
                cursorRow += 1
                clampCursorRow()
            }

            if cursorRow >= 0 && cursorCol >= 0 {
                buffer[cursorRow][cursorCol] = Cell(char: char, italic: italicActive)
            }
            cursorCol += 1
            index = data.index(after: index)
        }
    }

    func moveBy(lines: Int) {
        cursorRow += lines
        clampCursorRow()
    }

    func hideCursor() {}

    func showCursor() {}

    func clearLine() {
        clearLine(mode: 0)
    }

    func clearFromCursor() {
        clearScreen(mode: 0)
    }

    func clearScreen() {
        clearScreen(mode: 2)
    }

    func setTitle(_ title: String) {}

    func sendInput(_ data: String) {
        inputHandler?(data)
    }

    func resize(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        buffer = Array(repeating: Array(repeating: blankCell, count: columns), count: rows)
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, columns - 1)
        resizeHandler?()
    }

    func getViewport() -> [String] {
        if !lastFrame.isEmpty {
            var lines = lastFrame
            if lines.count < rows {
                lines.append(contentsOf: Array(repeating: "", count: rows - lines.count))
            } else if lines.count > rows {
                lines = Array(lines.suffix(rows))
            }
            return lines.map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : line.trimmedRight()
            }
        }

        return buffer.map { row in
            let line = String(row.map { $0.char })
            return line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : line.trimmedRight()
        }
    }

    func isItalic(row: Int, col: Int) -> Bool {
        guard row >= 0, row < buffer.count else { return false }
        guard col >= 0, col < buffer[row].count else { return false }
        return buffer[row][col].italic
    }

    @MainActor
    func flush() async {
        await Task.yield()
    }

    private func handleEscapeSequence(in data: String, from start: String.Index) -> String.Index {
        let nextIndex = data.index(after: start)
        guard nextIndex < data.endIndex else { return data.index(after: start) }
        let nextChar = data[nextIndex]

        if nextChar == "[" {
            return handleCsi(in: data, from: start)
        }
        if nextChar == "]" {
            return handleOsc(in: data, from: start)
        }
        if nextChar == "P" || nextChar == "_" {
            return handleStringTerminated(in: data, from: start)
        }

        return data.index(after: nextIndex)
    }

    private func parseFrame(from data: String) -> [String]? {
        guard let startRange = data.range(of: "\u{001B}[?2026h"),
              let endRange = data.range(of: "\u{001B}[?2026l", range: startRange.upperBound..<data.endIndex) else {
            return nil
        }

        let frameContent = String(data[startRange.upperBound..<endRange.lowerBound])
        let stripped = stripEscapes(frameContent)
        return stripped.components(separatedBy: "\r\n")
    }

    private func stripEscapes(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            if char == "\u{001B}" {
                index = skipEscape(in: text, from: index)
                continue
            }
            result.append(char)
            index = text.index(after: index)
        }
        return result
    }

    private func skipEscape(in text: String, from start: String.Index) -> String.Index {
        let nextIndex = text.index(after: start)
        guard nextIndex < text.endIndex else { return nextIndex }
        let nextChar = text[nextIndex]

        if nextChar == "[" {
            var index = text.index(nextIndex, offsetBy: 1)
            while index < text.endIndex {
                let scalar = text[index].unicodeScalars.first?.value ?? 0
                if scalar >= 0x40 && scalar <= 0x7E {
                    return text.index(after: index)
                }
                index = text.index(after: index)
            }
            return text.endIndex
        }

        if nextChar == "]" {
            var index = text.index(nextIndex, offsetBy: 1)
            while index < text.endIndex {
                if text[index] == "\u{0007}" {
                    return text.index(after: index)
                }
                if text[index] == "\u{001B}" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\\" {
                        return text.index(after: next)
                    }
                }
                index = text.index(after: index)
            }
            return text.endIndex
        }

        if nextChar == "P" || nextChar == "_" {
            var index = text.index(nextIndex, offsetBy: 1)
            while index < text.endIndex {
                if text[index] == "\u{001B}" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\\" {
                        return text.index(after: next)
                    }
                }
                index = text.index(after: index)
            }
            return text.endIndex
        }

        return text.index(after: nextIndex)
    }

    private func handleCsi(in data: String, from start: String.Index) -> String.Index {
        var index = data.index(start, offsetBy: 2)
        while index < data.endIndex {
            let scalar = data[index].unicodeScalars.first?.value ?? 0
            if scalar >= 0x40 && scalar <= 0x7E {
                let finalChar = data[index]
                let params = String(data[data.index(start, offsetBy: 2)..<index])
                applyCsi(finalChar: finalChar, params: params)
                return data.index(after: index)
            }
            index = data.index(after: index)
        }
        return data.endIndex
    }

    private func handleOsc(in data: String, from start: String.Index) -> String.Index {
        var index = data.index(start, offsetBy: 2)
        while index < data.endIndex {
            if data[index] == "\u{0007}" {
                return data.index(after: index)
            }
            if data[index] == "\u{001B}" {
                let next = data.index(after: index)
                if next < data.endIndex, data[next] == "\\" {
                    return data.index(after: next)
                }
            }
            index = data.index(after: index)
        }
        return data.endIndex
    }

    private func handleStringTerminated(in data: String, from start: String.Index) -> String.Index {
        var index = data.index(start, offsetBy: 2)
        while index < data.endIndex {
            if data[index] == "\u{001B}" {
                let next = data.index(after: index)
                if next < data.endIndex, data[next] == "\\" {
                    return data.index(after: next)
                }
            }
            index = data.index(after: index)
        }
        return data.endIndex
    }

    private func applyCsi(finalChar: Character, params: String) {
        let cleaned = params.replacingOccurrences(of: "?", with: "")
        let numbers = cleaned.split(separator: ";").compactMap { Int($0) }

        func paramOrDefault(_ defaultValue: Int) -> Int {
            return numbers.first ?? defaultValue
        }

        switch finalChar {
        case "A":
            let value = paramOrDefault(1)
            cursorRow = max(0, cursorRow - value)
        case "B":
            let value = paramOrDefault(1)
            cursorRow += value
            clampCursorRow()
        case "C":
            let value = paramOrDefault(1)
            cursorCol = min(columns - 1, cursorCol + value)
        case "D":
            let value = paramOrDefault(1)
            cursorCol = max(0, cursorCol - value)
        case "G":
            let value = paramOrDefault(1)
            cursorCol = max(0, min(columns - 1, value - 1))
        case "H", "f":
            let row = numbers.count > 0 ? max(1, numbers[0]) : 1
            let col = numbers.count > 1 ? max(1, numbers[1]) : 1
            cursorRow = max(0, row - 1)
            cursorCol = max(0, col - 1)
            clampCursorRow()
        case "J":
            let mode = paramOrDefault(0)
            clearScreen(mode: mode)
        case "K":
            let mode = paramOrDefault(0)
            clearLine(mode: mode)
        case "m":
            let codes = numbers.isEmpty ? [0] : numbers
            applySgr(codes)
        default:
            break
        }
    }

    private func applySgr(_ codes: [Int]) {
        for code in codes {
            switch code {
            case 0, 23:
                italicActive = false
            case 3:
                italicActive = true
            default:
                break
            }
        }
    }

    private func clearLine(mode: Int) {
        clampCursorRow()
        if mode == 2 {
            buffer[cursorRow] = Array(repeating: blankCell, count: columns)
        } else {
            let start = max(0, cursorCol)
            for col in start..<columns {
                buffer[cursorRow][col] = blankCell
            }
        }
    }

    private func clearScreen(mode: Int) {
        guard mode == 2 || mode == 3 || mode == 0 else { return }
        buffer = Array(repeating: Array(repeating: blankCell, count: columns), count: rows)
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, columns - 1)
    }

    private func clampCursorRow() {
        if cursorRow < 0 {
            cursorRow = 0
            return
        }
        if cursorRow >= rows {
            let overflow = cursorRow - rows + 1
            scrollDown(lines: overflow)
            cursorRow = rows - 1
        }
    }

    private func scrollDown(lines: Int) {
        guard lines > 0 else { return }
        for _ in 0..<lines {
            buffer.removeFirst()
            buffer.append(Array(repeating: blankCell, count: columns))
        }
    }
}

extension String {
    func trimmedRight() -> String {
        var result = self
        while let last = result.last, last == " " {
            result.removeLast()
        }
        return result
    }
}
