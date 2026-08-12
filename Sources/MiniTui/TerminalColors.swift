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

/// Return whether `data` is a complete OSC 11 background-color response.
public func isOsc11BackgroundColorResponse(_ data: String) -> Bool {
    let prefix = "\u{001B}]11;"
    guard data.hasPrefix(prefix), data.count > prefix.count else { return false }
    guard data.hasSuffix("\u{0007}") || data.hasSuffix("\u{001B}\\") else { return false }

    let terminatorLength = data.hasSuffix("\u{0007}") ? 1 : 2
    let valueEnd = data.index(data.endIndex, offsetBy: -terminatorLength)
    let valueStart = data.index(data.startIndex, offsetBy: prefix.count)
    let value = data[valueStart..<valueEnd]
    return !value.unicodeScalars.contains { $0.value == 0x07 || $0.value == 0x1B }
}

/// Parse the RGB value from a complete OSC 11 background-color response.
public func parseOsc11BackgroundColor(_ data: String) -> RgbColor? {
    guard isOsc11BackgroundColorResponse(data) else { return nil }

    let prefix = "\u{001B}]11;"
    let terminatorLength = data.hasSuffix("\u{0007}") ? 1 : 2
    let valueStart = data.index(data.startIndex, offsetBy: prefix.count)
    let valueEnd = data.index(data.endIndex, offsetBy: -terminatorLength)
    let value = String(data[valueStart..<valueEnd]).trimmingCharacters(in: .whitespacesAndNewlines)

    if value.hasPrefix("#") {
        let hex = String(value.dropFirst())
        if hex.count == 6, let r = Int(hex.prefix(2), radix: 16),
           let g = Int(hex.dropFirst(2).prefix(2), radix: 16),
           let b = Int(hex.dropFirst(4).prefix(2), radix: 16) {
            return RgbColor(r: r, g: g, b: b)
        }
        if hex.count == 12,
           let r = parseOscHexChannel(String(hex.prefix(4))),
           let g = parseOscHexChannel(String(hex.dropFirst(4).prefix(4))),
           let b = parseOscHexChannel(String(hex.dropFirst(8).prefix(4))) {
            return RgbColor(r: r, g: g, b: b)
        }
        return nil
    }

    let lowercased = value.lowercased()
    let rgbValue: String
    if lowercased.hasPrefix("rgb:") {
        rgbValue = String(value.dropFirst(4))
    } else if lowercased.hasPrefix("rgba:") {
        rgbValue = String(value.dropFirst(5))
    } else {
        rgbValue = value
    }

    let channels = rgbValue.split(separator: "/", omittingEmptySubsequences: false)
    guard channels.count == 3,
          let r = parseOscHexChannel(String(channels[0])),
          let g = parseOscHexChannel(String(channels[1])),
          let b = parseOscHexChannel(String(channels[2])) else {
        return nil
    }
    return RgbColor(r: r, g: g, b: b)
}

/// Parse a terminal color-scheme report (`CSI ? 997 ; 1 n` / `CSI ? 997 ; 2 n`).
public func parseTerminalColorSchemeReport(_ data: String) -> TerminalColorScheme? {
    guard let report = parseTerminalColorSchemeReportPrefix(data), report.length == data.count else {
        return nil
    }
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

private func parseOscHexChannel(_ channel: String) -> Int? {
    guard !channel.isEmpty,
          channel.unicodeScalars.allSatisfy({
              (48...57).contains($0.value) || (65...70).contains($0.value) || (97...102).contains($0.value)
          }),
          let value = Int(channel, radix: 16) else {
        return nil
    }

    let maximum = pow(16.0, Double(channel.count)) - 1
    guard maximum > 0 else { return nil }
    return Int((Double(value) / maximum * 255).rounded())
}
