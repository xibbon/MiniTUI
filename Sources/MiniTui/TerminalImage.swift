import Foundation

/// Terminal image protocols supported by the renderer.
public enum ImageProtocol: String {
    case kitty
    case iterm2
}

private let kittyPrefix = "\u{001B}_G"
private let iterm2Prefix = "\u{001B}]1337;File="

/// Check if a line contains terminal image escape sequences.
/// Returns true if the line contains Kitty or iTerm2 image data.
public func isImageLine(_ line: String) -> Bool {
    // Fast path: sequence at line start (single-row images)
    if line.hasPrefix(kittyPrefix) || line.hasPrefix(iterm2Prefix) {
        return true
    }
    // Slow path: sequence elsewhere (multi-row images have cursor-up prefix)
    return line.contains(kittyPrefix) || line.contains(iterm2Prefix)
}

/// Terminal capability flags used for rendering.
public struct TerminalCapabilities {
    /// Supported image protocol, if any.
    public let images: ImageProtocol?
    /// Whether true color output is supported.
    public let trueColor: Bool
    /// Whether hyperlinks are supported.
    public let hyperlinks: Bool

    /// Create a capabilities struct.
    public init(images: ImageProtocol?, trueColor: Bool, hyperlinks: Bool) {
        self.images = images
        self.trueColor = trueColor
        self.hyperlinks = hyperlinks
    }
}

/// Pixel dimensions of a single terminal cell.
public struct CellDimensions {
    /// Cell width in pixels.
    public let widthPx: Int
    /// Cell height in pixels.
    public let heightPx: Int

    /// Create cell dimensions.
    public init(widthPx: Int, heightPx: Int) {
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

/// Pixel dimensions of an image.
public struct ImageDimensions {
    /// Image width in pixels.
    public let widthPx: Int
    /// Image height in pixels.
    public let heightPx: Int

    /// Create image dimensions.
    public init(widthPx: Int, heightPx: Int) {
        self.widthPx = widthPx
        self.heightPx = heightPx
    }
}

/// Options that influence image rendering.
public struct ImageRenderOptions {
    /// Maximum width in terminal cells.
    public let maxWidthCells: Int?
    /// Maximum height in terminal cells.
    public let maxHeightCells: Int?
    /// Preserve aspect ratio when scaling.
    public let preserveAspectRatio: Bool?

    /// Create image render options.
    public init(maxWidthCells: Int? = nil, maxHeightCells: Int? = nil, preserveAspectRatio: Bool? = nil) {
        self.maxWidthCells = maxWidthCells
        self.maxHeightCells = maxHeightCells
        self.preserveAspectRatio = preserveAspectRatio
    }
}

private final class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private let cachedCapabilities = LockedValue<TerminalCapabilities?>(nil)
private let cellDimensions = LockedValue(CellDimensions(widthPx: 9, heightPx: 18))

/// Return the current terminal cell dimensions.
public func getCellDimensions() -> CellDimensions {
    return cellDimensions.get()
}

/// Update the cached terminal cell dimensions.
public func setCellDimensions(_ dims: CellDimensions) {
    cellDimensions.set(dims)
}

/// Detect terminal capabilities from environment variables.
public func detectCapabilities() -> TerminalCapabilities {
    let env = ProcessInfo.processInfo.environment
    let termProgram = env["TERM_PROGRAM"]?.lowercased() ?? ""
    let term = env["TERM"]?.lowercased() ?? ""
    let colorTerm = env["COLORTERM"]?.lowercased() ?? ""

    if env["KITTY_WINDOW_ID"] != nil || termProgram == "kitty" || term.contains("kitty") {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true)
    }

    if termProgram == "ghostty" || term.contains("ghostty") || env["GHOSTTY_RESOURCES_DIR"] != nil {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true)
    }

    if env["WEZTERM_PANE"] != nil || termProgram == "wezterm" || term.contains("wezterm") {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true)
    }

    if env["ITERM_SESSION_ID"] != nil || termProgram == "iterm.app" {
        return TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: true)
    }

    if termProgram == "vscode" {
        return TerminalCapabilities(images: nil, trueColor: true, hyperlinks: true)
    }

    if termProgram == "alacritty" {
        return TerminalCapabilities(images: nil, trueColor: true, hyperlinks: true)
    }

    let trueColor = colorTerm == "truecolor" || colorTerm == "24bit"
    return TerminalCapabilities(images: nil, trueColor: trueColor, hyperlinks: true)
}

/// Return cached terminal capabilities, detecting once if needed.
public func getCapabilities() -> TerminalCapabilities {
    if let cached = cachedCapabilities.get() {
        return cached
    }
    let detected = detectCapabilities()
    cachedCapabilities.set(detected)
    return detected
}

/// Clear the cached terminal capabilities.
public func resetCapabilitiesCache() {
    cachedCapabilities.set(nil)
}

/// Allocate a random image ID for Kitty graphics protocol.
/// Returns a random ID in range [1, 0xffffffff] to avoid collisions.
public func allocateImageId() -> UInt32 {
    return UInt32.random(in: 1...0xfffffffe)
}

/// Delete a specific Kitty graphics image by ID.
public func deleteKittyImage(imageId: UInt32) -> String {
    return "\u{001B}_Ga=d,d=I,i=\(imageId)\u{001B}\\"
}

/// Delete all visible Kitty graphics images.
/// Uses uppercase 'A' to also free the image data.
public func deleteAllKittyImages() -> String {
    return "\u{001B}_Ga=d,d=A\u{001B}\\"
}

/// Encode base64 image data using the Kitty graphics protocol.
public func encodeKitty(
    base64Data: String,
    columns: Int? = nil,
    rows: Int? = nil,
    imageId: Int? = nil
) -> String {
    let chunkSize = 4096

    var params = ["a=T", "f=100", "q=2"]
    if let columns { params.append("c=\(columns)") }
    if let rows { params.append("r=\(rows)") }
    if let imageId { params.append("i=\(imageId)") }

    if base64Data.count <= chunkSize {
        return "\u{001B}_G" + params.joined(separator: ",") + ";" + base64Data + "\u{001B}\\"
    }

    var chunks: [String] = []
    var offset = 0
    var isFirst = true
    let count = base64Data.count

    while offset < count {
        let end = min(offset + chunkSize, count)
        let chunk = base64Data.substring(from: offset, length: end - offset)
        let isLast = end >= count

        if isFirst {
            chunks.append("\u{001B}_G" + params.joined(separator: ",") + ",m=1;" + chunk + "\u{001B}\\")
            isFirst = false
        } else if isLast {
            chunks.append("\u{001B}_Gm=0;" + chunk + "\u{001B}\\")
        } else {
            chunks.append("\u{001B}_Gm=1;" + chunk + "\u{001B}\\")
        }

        offset += chunkSize
    }

    return chunks.joined()
}

/// Encode base64 image data using the iTerm2 inline image protocol.
public func encodeITerm2(
    base64Data: String,
    width: String? = nil,
    height: String? = nil,
    name: String? = nil,
    preserveAspectRatio: Bool? = nil,
    inline: Bool = true
) -> String {
    var params: [String] = ["inline=\(inline ? 1 : 0)"]

    if let width { params.append("width=\(width)") }
    if let height { params.append("height=\(height)") }
    if let name {
        let nameBase64 = Data(name.utf8).base64EncodedString()
        params.append("name=\(nameBase64)")
    }
    if preserveAspectRatio == false {
        params.append("preserveAspectRatio=0")
    }

    return "\u{001B}]1337;File=" + params.joined(separator: ";") + ":" + base64Data + "\u{0007}"
}

/// Calculate the number of terminal rows an image should occupy.
public func calculateImageRows(
    imageDimensions: ImageDimensions,
    targetWidthCells: Int,
    cellDimensions: CellDimensions = CellDimensions(widthPx: 9, heightPx: 18)
) -> Int {
    let targetWidthPx = targetWidthCells * cellDimensions.widthPx
    let scale = Double(targetWidthPx) / Double(imageDimensions.widthPx)
    let scaledHeightPx = Double(imageDimensions.heightPx) * scale
    let rows = Int(ceil(scaledHeightPx / Double(cellDimensions.heightPx)))
    return max(1, rows)
}

/// Read PNG dimensions from base64 data.
public func getPngDimensions(_ base64Data: String) -> ImageDimensions? {
    guard let data = Data(base64Encoded: base64Data), data.count >= 24 else {
        return nil
    }

    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    if Array(data.prefix(4)) != signature {
        return nil
    }

    let width = data.readUInt32BE(at: 16)
    let height = data.readUInt32BE(at: 20)
    return ImageDimensions(widthPx: Int(width), heightPx: Int(height))
}

/// Read JPEG dimensions from base64 data.
public func getJpegDimensions(_ base64Data: String) -> ImageDimensions? {
    guard let data = Data(base64Encoded: base64Data), data.count >= 2 else {
        return nil
    }

    if data[0] != 0xFF || data[1] != 0xD8 {
        return nil
    }

    var offset = 2
    while offset + 9 < data.count {
        if data[offset] != 0xFF {
            offset += 1
            continue
        }

        let marker = data[offset + 1]
        if marker >= 0xC0 && marker <= 0xC2 {
            let height = data.readUInt16BE(at: offset + 5)
            let width = data.readUInt16BE(at: offset + 7)
            return ImageDimensions(widthPx: Int(width), heightPx: Int(height))
        }

        if offset + 3 >= data.count {
            return nil
        }
        let length = Int(data.readUInt16BE(at: offset + 2))
        if length < 2 {
            return nil
        }
        offset += 2 + length
    }

    return nil
}

/// Read GIF dimensions from base64 data.
public func getGifDimensions(_ base64Data: String) -> ImageDimensions? {
    guard let data = Data(base64Encoded: base64Data), data.count >= 10 else {
        return nil
    }

    let signature = String(decoding: data.prefix(6), as: UTF8.self)
    if signature != "GIF87a" && signature != "GIF89a" {
        return nil
    }

    let width = data.readUInt16LE(at: 6)
    let height = data.readUInt16LE(at: 8)
    return ImageDimensions(widthPx: Int(width), heightPx: Int(height))
}

/// Read WebP dimensions from base64 data.
public func getWebpDimensions(_ base64Data: String) -> ImageDimensions? {
    guard let data = Data(base64Encoded: base64Data), data.count >= 30 else {
        return nil
    }

    let riff = String(decoding: data.prefix(4), as: UTF8.self)
    let webp = String(decoding: data.subdata(in: 8..<12), as: UTF8.self)
    if riff != "RIFF" || webp != "WEBP" {
        return nil
    }

    let chunk = String(decoding: data.subdata(in: 12..<16), as: UTF8.self)
    if chunk == "VP8 " {
        guard data.count >= 30 else { return nil }
        let width = data.readUInt16LE(at: 26) & 0x3FFF
        let height = data.readUInt16LE(at: 28) & 0x3FFF
        return ImageDimensions(widthPx: Int(width), heightPx: Int(height))
    } else if chunk == "VP8L" {
        guard data.count >= 25 else { return nil }
        let bits = data.readUInt32LE(at: 21)
        let width = Int(bits & 0x3FFF) + 1
        let height = Int((bits >> 14) & 0x3FFF) + 1
        return ImageDimensions(widthPx: width, heightPx: height)
    } else if chunk == "VP8X" {
        guard data.count >= 30 else { return nil }
        let width = Int(data[24] | (data[25] << 8) | (data[26] << 16)) + 1
        let height = Int(data[27] | (data[28] << 8) | (data[29] << 16)) + 1
        return ImageDimensions(widthPx: width, heightPx: height)
    }

    return nil
}

/// Dispatch to the appropriate decoder based on mime type.
public func getImageDimensions(_ base64Data: String, mimeType: String) -> ImageDimensions? {
    switch mimeType {
    case "image/png":
        return getPngDimensions(base64Data)
    case "image/jpeg":
        return getJpegDimensions(base64Data)
    case "image/gif":
        return getGifDimensions(base64Data)
    case "image/webp":
        return getWebpDimensions(base64Data)
    default:
        return nil
    }
}

/// Render an image using supported terminal protocols.
public func renderImage(
    base64Data: String,
    imageDimensions: ImageDimensions,
    options: ImageRenderOptions = ImageRenderOptions()
) -> (sequence: String, rows: Int)? {
    let caps = getCapabilities()
    guard let images = caps.images else {
        return nil
    }

    let maxWidth = options.maxWidthCells ?? 80
    let rows = calculateImageRows(imageDimensions: imageDimensions, targetWidthCells: maxWidth, cellDimensions: getCellDimensions())

    switch images {
    case .kitty:
        let sequence = encodeKitty(base64Data: base64Data, columns: maxWidth, rows: rows, imageId: nil)
        return (sequence, rows)
    case .iterm2:
        let sequence = encodeITerm2(
            base64Data: base64Data,
            width: String(maxWidth),
            height: "auto",
            name: nil,
            preserveAspectRatio: options.preserveAspectRatio ?? true,
            inline: true
        )
        return (sequence, rows)
    }
}

/// Return a human-readable fallback label for an image.
public func imageFallback(_ mimeType: String, dimensions: ImageDimensions? = nil, filename: String? = nil) -> String {
    var parts: [String] = []
    if let filename { parts.append(filename) }
    parts.append("[\(mimeType)]")
    if let dimensions { parts.append("\(dimensions.widthPx)x\(dimensions.heightPx)") }
    return "[Image: \(parts.joined(separator: " "))]"
}

private extension Data {
    func readUInt16BE(at offset: Int) -> UInt16 {
        let high = UInt16(self[offset]) << 8
        let low = UInt16(self[offset + 1])
        return high | low
    }

    func readUInt16LE(at offset: Int) -> UInt16 {
        let low = UInt16(self[offset])
        let high = UInt16(self[offset + 1]) << 8
        return high | low
    }

    func readUInt32BE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset]) << 24
        let b1 = UInt32(self[offset + 1]) << 16
        let b2 = UInt32(self[offset + 2]) << 8
        let b3 = UInt32(self[offset + 3])
        return b0 | b1 | b2 | b3
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
