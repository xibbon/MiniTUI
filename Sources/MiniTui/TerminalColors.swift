import Foundation

/// An RGB terminal color with 8-bit channels.
public struct RgbColor: Sendable, Equatable {
    public let r: Int
    public let g: Int
    public let b: Int

    public init(r: Int, g: Int, b: Int) {
        self.r = r
        self.g = g
        self.b = b
    }
}

/// A terminal's preferred color scheme, as reported by the palette notification protocol.
public enum TerminalColorScheme: String, Sendable, Equatable {
    case dark
    case light
}

/// The default colors and ANSI palette reported by a terminal.
public struct TerminalColors: Sendable, Equatable {
    public let foreground: RgbColor?
    public let background: RgbColor?
    /// Present only when the terminal reported valid colors for all 16 entries.
    public let palette: [RgbColor]?

    public init(foreground: RgbColor? = nil, background: RgbColor? = nil, palette: [RgbColor]? = nil) {
        self.foreground = foreground
        self.background = background
        self.palette = palette
    }
}

/// The target of an OSC color reply.
public enum OscColorTarget: Sendable, Equatable, Hashable {
    case foreground
    case background
    case palette(Int)
}

/// Parse one complete OSC 10, 11, or 4 color reply.
/// A reply with an invalid color has a target and a nil RGB value.
public func parseOscColorResponse(_ data: String) -> (target: OscColorTarget, rgb: RgbColor?)? {
    guard let response = parseOscColorResponsePrefix(data), response.length == data.count else { return nil }
    return (response.target, response.rgb)
}

/// Parse a color reply at the start of a terminal input batch.
func parseOscColorResponsePrefix(_ data: String) -> (target: OscColorTarget, rgb: RgbColor?, length: Int)? {
    let prefix = "\u{001B}]"
    guard data.hasPrefix(prefix) else { return nil }
    let bodyStart = data.index(data.startIndex, offsetBy: prefix.count)
    guard let semicolon = data[bodyStart...].firstIndex(of: ";") else { return nil }
    let selector = data[bodyStart..<semicolon]
    let target: OscColorTarget
    let valueStart: String.Index

    if selector == "10" {
        target = .foreground
        valueStart = data.index(after: semicolon)
    } else if selector == "11" {
        target = .background
        valueStart = data.index(after: semicolon)
    } else if selector == "4" {
        let indexStart = data.index(after: semicolon)
        guard let indexEnd = data[indexStart...].firstIndex(of: ";") else { return nil }
        let digits = data[indexStart..<indexEnd]
        guard (1...3).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let index = Int(digits) else { return nil }
        target = .palette(index)
        valueStart = data.index(after: indexEnd)
    } else {
        return nil
    }

    var cursor = valueStart
    while cursor < data.endIndex {
        let character = data[cursor]
        if character == "\u{0007}" {
            let end = data.index(after: cursor)
            return (target, parseOscColorValue(String(data[valueStart..<cursor])), data.distance(from: data.startIndex, to: end))
        }
        if character == "\u{001B}" {
            let next = data.index(after: cursor)
            guard next < data.endIndex, data[next] == "\\" else { return nil }
            let end = data.index(after: next)
            return (target, parseOscColorValue(String(data[valueStart..<cursor])), data.distance(from: data.startIndex, to: end))
        }
        cursor = data.index(after: cursor)
    }
    return nil
}

private func parseOscColorValue(_ rawValue: String) -> RgbColor? {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") {
        let hex = value.dropFirst()
        guard hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if hex.count == 6 {
            guard let r = Int(hex.prefix(2), radix: 16),
                  let g = Int(hex.dropFirst(2).prefix(2), radix: 16),
                  let b = Int(hex.dropFirst(4).prefix(2), radix: 16) else { return nil }
            return RgbColor(r: r, g: g, b: b)
        }
        if hex.count == 12 {
            guard let r = parseOscHexChannel(String(hex.prefix(4))),
                  let g = parseOscHexChannel(String(hex.dropFirst(4).prefix(4))),
                  let b = parseOscHexChannel(String(hex.dropFirst(8).prefix(4))) else { return nil }
            return RgbColor(r: r, g: g, b: b)
        }
        return nil
    }

    let channelText: Substring
    if value.lowercased().hasPrefix("rgba:") {
        channelText = value.dropFirst(5)
    } else if value.lowercased().hasPrefix("rgb:") {
        channelText = value.dropFirst(4)
    } else {
        channelText = value[...]
    }
    // Upstream reads the first three slash-separated values and ignores later fields.
    let channels = channelText.split(separator: "/", omittingEmptySubsequences: false)
    guard channels.count >= 3,
          let r = parseOscHexChannel(String(channels[0])),
          let g = parseOscHexChannel(String(channels[1])),
          let b = parseOscHexChannel(String(channels[2])) else { return nil }
    return RgbColor(r: r, g: g, b: b)
}

private func parseOscHexChannel(_ channel: String) -> Int? {
    guard !channel.isEmpty,
          channel.allSatisfy({ $0.isASCII && $0.isHexDigit }),
          let value = Int(channel, radix: 16) else { return nil }
    let maximum = pow(16.0, Double(channel.count)) - 1
    return Int((Double(value) / maximum * 255).rounded())
}

/// Parse a terminal color-scheme report (`CSI ? 997 ; 1 n` / `CSI ? 997 ; 2 n`).
public func parseTerminalColorSchemeReport(_ data: String) -> TerminalColorScheme? {
    guard let report = parseTerminalColorSchemeReportPrefix(data), report.length == data.count else { return nil }
    return report.scheme
}

/// Parse one or more color-scheme reports at the start of `data`.
/// The last report in the batch is the effective value.
func parseTerminalColorSchemeReportPrefix(_ data: String) -> (scheme: TerminalColorScheme, length: Int)? {
    let darkReport = "\u{001B}[?997;1n"
    let lightReport = "\u{001B}[?997;2n"
    var remainder = data[...]
    var scheme: TerminalColorScheme?
    var consumedLength = 0

    while !remainder.isEmpty {
        if remainder.hasPrefix(darkReport) {
            scheme = .dark
            remainder.removeFirst(darkReport.count)
            consumedLength += darkReport.count
        } else if remainder.hasPrefix(lightReport) {
            scheme = .light
            remainder.removeFirst(lightReport.count)
            consumedLength += lightReport.count
        } else {
            break
        }
    }

    guard let scheme else { return nil }
    return (scheme, consumedLength)
}

/// Parse a primary device attributes reply at the start of an input batch.
func parseDeviceAttributesResponsePrefix(_ data: String) -> Int? {
    let prefix = "\u{001B}[?"
    guard data.hasPrefix(prefix) else { return nil }
    var cursor = data.index(data.startIndex, offsetBy: prefix.count)
    while cursor < data.endIndex {
        let character = data[cursor]
        if character == "c" { return data.distance(from: data.startIndex, to: data.index(after: cursor)) }
        guard character == ";" || (character.isASCII && character.isNumber) else { return nil }
        cursor = data.index(after: cursor)
    }
    return nil
}
