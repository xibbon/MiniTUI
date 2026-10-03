import Foundation
#if canImport(os)
import os
#else
import Synchronization
#endif

let osc8HyperlinkCloseBell = "\u{001B}]8;;\u{0007}"
let osc8HyperlinkCloseStringTerminator = "\u{001B}]8;;\u{001B}\\"

/// Terminal image protocols supported by the renderer.
public enum ImageProtocol: String, Sendable {
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
public struct TerminalCapabilities: Sendable {
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
public struct CellDimensions: Sendable {
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
public struct ImageDimensions: Sendable {
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
    /// Kitty image ID. Callers can reuse this ID for updates.
    public let imageId: Int?
    /// Whether Kitty moves the cursor after image placement. The default is true.
    public let moveCursor: Bool?

    /// Create image render options.
    public init(
        maxWidthCells: Int? = nil,
        maxHeightCells: Int? = nil,
        preserveAspectRatio: Bool? = nil,
        imageId: Int? = nil,
        moveCursor: Bool? = nil
    ) {
        self.maxWidthCells = maxWidthCells
        self.maxHeightCells = maxHeightCells
        self.preserveAspectRatio = preserveAspectRatio
        self.imageId = imageId
        self.moveCursor = moveCursor
    }
}

/// Immutable lock storage gives all shared values checked Sendable conformance.
private final class LockedValue<T: Sendable>: Sendable {
    #if canImport(os)
    private let storage: OSAllocatedUnfairLock<T>
    init(_ value: T) { storage = OSAllocatedUnfairLock(initialState: value) }
    #else
    private let storage: Mutex<T>
    init(_ value: T) { storage = Mutex(value) }
    #endif
    func get() -> T { storage.withLock { $0 } }
    func set(_ value: T) { storage.withLock { $0 = value } }
    func update<R: Sendable>(_ body: @Sendable (inout T) -> R) -> R { storage.withLock(body) }
}

/// nil means auto-detect; .some(nil) explicitly disables images.
public struct TerminalCapabilityOverrides: Sendable, Equatable {
    public var images: ImageProtocol??
    public var trueColor: Bool?
    public var hyperlinks: Bool?
    public init(images: ImageProtocol?? = nil, trueColor: Bool? = nil, hyperlinks: Bool? = nil) {
        self.images = images; self.trueColor = trueColor; self.hyperlinks = hyperlinks
    }
}

struct CapabilityState: Sendable {
    var cached: TerminalCapabilities?
    var overrides = TerminalCapabilityOverrides()
}

private let capabilityState = LockedValue(CapabilityState())
private let cellDimensions = LockedValue(CellDimensions(widthPx: 9, heightPx: 18))

struct KittyImageMetadata: Sendable {
    let imageID: UInt32
    let columns: Int
    let rows: Int
    let widthPx: Int
    let heightPx: Int
    let transmissionGeneration: Int
}

struct KittyImagePlacement: Sendable {
    let imageID: UInt32
    let transmissionGeneration: Int
    let transmissionBytes: Int
    let estimatedDecodedBytes: Int
    let rows: Int
    let sequence: String
    let replacementLine: String
}

private struct KittyMetadataRegistry: Sendable {
    var values: [UInt32: KittyImageMetadata] = [:]
    var insertionOrder: [UInt32] = []
    var transmissionGeneration = 0
}

private let kittyMetadataRegistry = LockedValue(KittyMetadataRegistry())

private func kittyTransmission(in line: String) -> String? {
    guard let firstStart = line.range(of: kittyPrefix)?.lowerBound else { return nil }
    var commandStart = firstStart
    while true {
        guard let controlsEnd = line[commandStart...].firstIndex(of: ";"),
              let terminator = line[controlsEnd...].range(of: "\u{001B}\\") else {
            return nil
        }
        let controlsStart = line.index(commandStart, offsetBy: kittyPrefix.count)
        let controls = line[controlsStart..<controlsEnd].split(separator: ",")
        let transmissionEnd = terminator.upperBound
        if !controls.contains("m=1") {
            return String(line[firstStart..<transmissionEnd])
        }
        guard transmissionEnd < line.endIndex, line[transmissionEnd...].hasPrefix(kittyPrefix) else {
            return nil
        }
        commandStart = transmissionEnd
    }
}

private func kittyImageID(in line: String) -> UInt32? {
    guard let commandStart = line.range(of: kittyPrefix)?.lowerBound,
          let controlsEnd = line[commandStart...].firstIndex(of: ";") else {
        return nil
    }
    let controlsStart = line.index(commandStart, offsetBy: kittyPrefix.count)
    for control in line[controlsStart..<controlsEnd].split(separator: ",") {
        guard control.hasPrefix("i=") else { continue }
        return UInt32(control.dropFirst(2))
    }
    return nil
}

func registerKittyImageMetadata(
    imageID: UInt32,
    columns: Int,
    rows: Int,
    widthPx: Int,
    heightPx: Int
) {
    kittyMetadataRegistry.update { registry in
        registry.transmissionGeneration += 1
        registry.insertionOrder.removeAll { $0 == imageID }
        registry.insertionOrder.append(imageID)
        registry.values[imageID] = KittyImageMetadata(
            imageID: imageID,
            columns: columns,
            rows: rows,
            widthPx: widthPx,
            heightPx: heightPx,
            transmissionGeneration: registry.transmissionGeneration
        )
        if registry.values.count > 1_000 {
            let oldestID = registry.insertionOrder.removeFirst()
            registry.values.removeValue(forKey: oldestID)
        }
    }
}

func getKittyImageMetadata(_ line: String) -> KittyImageMetadata? {
    guard let imageID = kittyImageID(in: line) else { return nil }
    return kittyMetadataRegistry.get().values[imageID]
}

/// Read only the first command's controls to find the placement height.
func getKittyImagePlacementRows(_ line: String) -> Int? {
    guard let commandStart = line.range(of: kittyPrefix)?.upperBound,
          let controlsEnd = line[commandStart...].firstIndex(of: ";") else {
        return nil
    }
    if let rows = explicitKittyImageRows(line[commandStart..<controlsEnd]) { return rows }
    return getKittyImageMetadata(line)?.rows
}

private func explicitKittyImageRows(_ controls: Substring) -> Int? {
    for control in controls.split(separator: ",") where control.hasPrefix("r=") {
        let value = control.dropFirst(2)
        guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { continue }
        guard let rows = Int(value), rows > 0 else { return nil }
        return rows
    }
    return nil
}

func getKittyImagePlacement(_ line: String) -> KittyImagePlacement? {
    guard let firstRange = line.range(of: kittyPrefix),
          let metadata = getKittyImageMetadata(line) else {
        return nil
    }
    let firstStart = firstRange.lowerBound
    var commandStart = firstStart
    var transmissionEnd: String.Index?
    while true {
        guard let controlsEnd = line[commandStart...].firstIndex(of: ";"),
              let terminator = line[controlsEnd...].range(of: "\u{001B}\\") else {
            return nil
        }
        let controlsStart = line.index(commandStart, offsetBy: kittyPrefix.count)
        let controls = line[controlsStart..<controlsEnd].split(separator: ",")
        transmissionEnd = terminator.upperBound
        if !controls.contains("m=1") { break }
        guard terminator.upperBound < line.endIndex,
              line[terminator.upperBound...].hasPrefix(kittyPrefix) else {
            return nil
        }
        commandStart = terminator.upperBound
    }
    guard let transmissionEnd,
          let controlsEnd = line[firstStart...].firstIndex(of: ";") else {
        return nil
    }
    let controlsStart = line.index(firstStart, offsetBy: kittyPrefix.count)
    let placementKeys: Set<String> = [
        "i", "p", "x", "y", "w", "h", "X", "Y", "c", "r", "C", "U",
        "z", "P", "Q", "H", "V",
    ]
    let controls = line[controlsStart..<controlsEnd]
        .split(separator: ",")
        .map(String.init)
        .filter { placementKeys.contains(String($0.split(separator: "=", maxSplits: 1)[0])) }
    let placement = kittyPrefix + "a=p,q=2," + controls.joined(separator: ",") + "\u{001B}\\"
    let transmission = line[firstStart..<transmissionEnd]
    let replacement = String(line[..<firstStart]) + placement + String(line[transmissionEnd...])
    return KittyImagePlacement(
        imageID: metadata.imageID,
        transmissionGeneration: metadata.transmissionGeneration,
        transmissionBytes: transmission.utf8.count,
        estimatedDecodedBytes: metadata.widthPx * metadata.heightPx * 4,
        rows: explicitKittyImageRows(line[controlsStart..<controlsEnd]) ?? metadata.rows,
        sequence: placement,
        replacementLine: replacement
    )
}

func cropKittyImageLine(_ line: String, hiddenRows: Int, visibleRows: Int) -> String {
    guard let metadata = getKittyImageMetadata(line),
          hiddenRows >= 0,
          hiddenRows < metadata.rows,
          visibleRows > 0,
          let commandStart = line.range(of: "\u{001B}_G")?.lowerBound,
          let controlsEnd = line[commandStart...].firstIndex(of: ";") else {
        return line
    }

    let croppedRows = min(visibleRows, metadata.rows - hiddenRows)
    if hiddenRows == 0, croppedRows == metadata.rows { return line }
    let sourceY = metadata.heightPx * hiddenRows / metadata.rows
    let sourceEnd = Int(ceil(Double(metadata.heightPx * (hiddenRows + croppedRows)) / Double(metadata.rows)))
    let sourceHeight = max(1, min(metadata.heightPx, sourceEnd) - sourceY)
    let controlsStart = line.index(commandStart, offsetBy: 3)
    var controls = line[controlsStart..<controlsEnd]
        .split(separator: ",")
        .map(String.init)
        .filter { control in
            !control.hasPrefix("y=") && !control.hasPrefix("h=") && !control.hasPrefix("r=")
        }
    controls.append("y=\(sourceY)")
    controls.append("h=\(sourceHeight)")
    controls.append("r=\(croppedRows)")
    let suffixStart = line.index(after: controlsEnd)
    return String(line[..<commandStart])
        + "\u{001B}_G"
        + controls.joined(separator: ",")
        + ";"
        + String(line[suffixStart...])
}

/// Return the current terminal cell dimensions.
public func getCellDimensions() -> CellDimensions {
    return cellDimensions.get()
}

/// Update the cached terminal cell dimensions.
public func setCellDimensions(_ dims: CellDimensions) {
    cellDimensions.set(dims)
}

/// Detect terminal capabilities from environment variables.
///
/// v0.67.6: hyperlinks default to `false` for unknown terminals, and are forced `false` under
/// tmux/screen (including nested sessions where the outer terminal would otherwise advertise
/// OSC 8). This prevents markdown link URLs from disappearing on terminals that silently
/// swallow OSC 8 sequences.
public func detectCapabilities(_ tmuxForwardsHyperlink: () -> Bool = { false }) -> TerminalCapabilities {
    detectCapabilities(environment: ProcessInfo.processInfo.environment, tmuxForwardsHyperlink: tmuxForwardsHyperlink)
}

/// Detect terminal capabilities from an explicit environment. This keeps capability checks
/// deterministic for tests while the public entry point uses the process environment.
func detectCapabilities(environment env: [String: String], tmuxForwardsHyperlink: () -> Bool = { false }) -> TerminalCapabilities {
    let hyperlinks: Bool? = env["PI_HYPERLINKS"] == "1" ? true : env["PI_HYPERLINKS"] == "0" ? false : nil
    let detected = detectCapabilitiesFromEnvironment(env) { hyperlinks ?? tmuxForwardsHyperlink() }
    let imageValue = env["PI_IMAGE_PROTOCOL"]?.lowercased()
    let images: ImageProtocol?
    switch imageValue {
    case "kitty": images = .kitty
    case "iterm2": images = .iterm2
    case "none", "0": images = nil
    default: images = detected.images
    }
    let trueColor = env["PI_TRUE_COLOR"] == "1" ? true : env["PI_TRUE_COLOR"] == "0" ? false : detected.trueColor
    return TerminalCapabilities(images: images, trueColor: trueColor, hyperlinks: hyperlinks ?? detected.hyperlinks)
}

func isWezTerm(environment env: [String: String]) -> Bool {
    env["WEZTERM_PANE"] != nil
        || env["TERM_PROGRAM"]?.lowercased() == "wezterm"
        || env["TERM"]?.lowercased().contains("wezterm") == true
}

private func detectCapabilitiesFromEnvironment(_ env: [String: String], tmuxForwardsHyperlink: () -> Bool) -> TerminalCapabilities {
    let termProgram = env["TERM_PROGRAM"]?.lowercased() ?? ""
    let term = env["TERM"]?.lowercased() ?? ""
    let colorTerm = env["COLORTERM"]?.lowercased() ?? ""

    // tmux/screen swallow OSC 8 sequences silently. Force hyperlinks off even when the outer
    // terminal would otherwise support them.
    let isMultiplexed = term.hasPrefix("screen") || term.hasPrefix("tmux") ||
        env["TMUX"] != nil || env["STY"] != nil

    let hyperlinks = !isMultiplexed || tmuxForwardsHyperlink()

    if env["KITTY_WINDOW_ID"] != nil || termProgram == "kitty" || term.contains("kitty") {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: hyperlinks)
    }

    if termProgram == "ghostty" || term.contains("ghostty") || env["GHOSTTY_RESOURCES_DIR"] != nil {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: hyperlinks)
    }

    if isWezTerm(environment: env) {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: hyperlinks)
    }

    // Warp supports Kitty graphics and OSC 8 hyperlinks.
    if termProgram == "warpterminal" || env["WARP_SESSION_ID"] != nil || env["WARP_TERMINAL_SESSION_UUID"] != nil {
        return TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: hyperlinks)
    }

    if env["ITERM_SESSION_ID"] != nil || termProgram == "iterm.app" {
        return TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: hyperlinks)
    }

    if termProgram == "vscode" {
        return TerminalCapabilities(images: nil, trueColor: true, hyperlinks: hyperlinks)
    }

    if termProgram == "alacritty" || termProgram == "zed" {
        return TerminalCapabilities(images: nil, trueColor: true, hyperlinks: hyperlinks)
    }

    let trueColor = colorTerm == "truecolor" || colorTerm == "24bit" || term.hasSuffix("-direct")
    // Unknown terminal: don't claim OSC 8 support to avoid silent link drops.
    return TerminalCapabilities(images: nil, trueColor: trueColor, hyperlinks: false)
}

/// v0.67.6: test override for terminal capabilities. Pass `nil` to reset to detection.
public func setCapabilities(_ capabilities: TerminalCapabilities?) {
    capabilityState.update { $0.cached = capabilities }
}

/// v0.67.6: build an OSC 8 hyperlink escape sequence wrapping `text` with the given URL.
/// Caller should consult `getCapabilities().hyperlinks` before using this — the helper itself
/// always emits the escape so it can be unit-tested independently of capability detection.
public func hyperlink(_ text: String, url: String) -> String {
    "\u{001B}]8;;\(url)\u{001B}\\\(text)" + osc8HyperlinkCloseStringTerminator
}

/// Return cached terminal capabilities, detecting once if needed.
public func getCapabilities() -> TerminalCapabilities {
    capabilityState.update { state in
        if let cached = state.cached { return cached }
        let detected = detectCapabilities { state.overrides.hyperlinks ?? false }
        let result = TerminalCapabilities(images: state.overrides.images ?? detected.images,
            trueColor: state.overrides.trueColor ?? detected.trueColor,
            hyperlinks: state.overrides.hyperlinks ?? detected.hyperlinks)
        state.cached = result
        return result
    }
}

/// Return the color mode after applying terminal capability overrides.
public func getTerminalColorMode(_ capabilities: TerminalCapabilities = getCapabilities()) -> TerminalColorMode {
    capabilities.trueColor ? .truecolor : .color256
}

/// Replace the override set. Keep the cache when the set is unchanged.
public func setCapabilityOverrides(_ overrides: TerminalCapabilityOverrides) {
    capabilityState.update { state in
        guard state.overrides != overrides else { return }
        state.overrides = overrides
        state.cached = nil
    }
}

/// Clear cached detection, retaining explicit overrides.
public func resetCapabilitiesCache() {
    capabilityState.update { $0.cached = nil }
}

/// Allocate a random image ID for Kitty graphics protocol.
/// Returns a random ID in range [1, 0xffffffff] to avoid collisions.
public func allocateImageId() -> UInt32 {
    return UInt32.random(in: 1...0xfffffffe)
}

/// Delete a specific Kitty graphics image by ID.
public func deleteKittyImage(imageId: UInt32) -> String {
    return "\u{001B}_Ga=d,d=I,i=\(imageId),q=2\u{001B}\\"
}

/// Delete all visible Kitty graphics images.
/// Uses uppercase 'A' to also free the image data.
public func deleteAllKittyImages() -> String {
    return "\u{001B}_Ga=d,d=A,q=2\u{001B}\\"
}

/// Delete all Kitty placements while retaining uploaded image data.
public func deleteAllKittyPlacements() -> String {
    return "\u{001B}_Ga=d,d=a,q=2\u{001B}\\"
}

/// Encode base64 image data using the Kitty graphics protocol.
public func encodeKitty(
    base64Data: String,
    columns: Int? = nil,
    rows: Int? = nil,
    imageId: Int? = nil,
    moveCursor: Bool? = nil
) -> String {
    let chunkSize = 4096

    var params = ["a=T", "f=100", "q=2"]
    if moveCursor == false { params.append("C=1") }
    if let columns { params.append("c=\(columns)") }
    if let rows { params.append("r=\(rows)") }
    if let imageId, imageId != 0 { params.append("i=\(imageId)") }

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
    let payloadSize = Data(base64Encoded: base64Data)?.count ?? 0
    var params: [String] = ["inline=\(inline ? 1 : 0)", "size=\(payloadSize)"]

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

/// The terminal cells reserved for an image.
public struct ImageCellSize: Sendable, Equatable {
    public let columns: Int
    public let rows: Int

    public init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
    }
}

private func chooseLessDistortedCellCount(upper: Int, ideal: Double) -> Int {
    guard upper > 1 else { return upper }
    let lower = upper - 1
    let upperDistortion = max(Double(upper) / ideal, ideal / Double(upper))
    let lowerDistortion = max(Double(lower) / ideal, ideal / Double(lower))
    return lowerDistortion < upperDistortion ? lower : upper
}

/// Calculate the cell size of an image, subject to width and height limits.
public func calculateImageCellSize(
    imageDimensions: ImageDimensions,
    maxWidthCells: Int,
    maxHeightCells: Int? = nil,
    cellDimensions: CellDimensions = CellDimensions(widthPx: 9, heightPx: 18),
    optimizeAspectRatio: Bool = false
) -> ImageCellSize {
    let maxWidth = max(1, maxWidthCells)
    let maxHeight = maxHeightCells.map { max(1, $0) }
    let imageWidth = Double(max(1, imageDimensions.widthPx))
    let imageHeight = Double(max(1, imageDimensions.heightPx))
    let cellWidth = Double(cellDimensions.widthPx)
    let cellHeight = Double(cellDimensions.heightPx)
    let widthScale = Double(maxWidth) * cellWidth / imageWidth
    let heightScale = maxHeight.map { Double($0) * cellHeight / imageHeight } ?? widthScale
    let scale = min(widthScale, heightScale)
    let scaledWidth = imageWidth * scale
    let scaledHeight = imageHeight * scale
    var columns = max(1, min(maxWidth, Int(ceil(scaledWidth / cellWidth))))
    var rows = max(1, Int(ceil(scaledHeight / cellHeight)))
    if let maxHeight { rows = min(maxHeight, rows) }
    guard optimizeAspectRatio else { return ImageCellSize(columns: columns, rows: rows) }

    if widthScale <= heightScale {
        let ideal = Double(columns) * cellWidth * imageHeight / (imageWidth * cellHeight)
        rows = chooseLessDistortedCellCount(upper: rows, ideal: ideal)
    } else {
        let ideal = Double(rows) * cellHeight * imageWidth / (imageHeight * cellWidth)
        columns = chooseLessDistortedCellCount(upper: columns, ideal: ideal)
    }
    return ImageCellSize(columns: columns, rows: rows)
}

/// Calculate the number of terminal rows an image should occupy.
public func calculateImageRows(
    imageDimensions: ImageDimensions,
    targetWidthCells: Int,
    cellDimensions: CellDimensions = CellDimensions(widthPx: 9, heightPx: 18)
) -> Int {
    calculateImageCellSize(
        imageDimensions: imageDimensions,
        maxWidthCells: targetWidthCells,
        cellDimensions: cellDimensions
    ).rows
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
) -> (sequence: String, columns: Int, rows: Int, imageId: Int?)? {
    let caps = getCapabilities()
    guard let images = caps.images else {
        return nil
    }

    let maxWidth = options.maxWidthCells ?? 80
    let size = calculateImageCellSize(
        imageDimensions: imageDimensions,
        maxWidthCells: maxWidth,
        maxHeightCells: options.maxHeightCells,
        cellDimensions: getCellDimensions(),
        optimizeAspectRatio: images == .kitty
    )

    switch images {
    case .kitty:
        if let imageId = options.imageId, let imageID = UInt32(exactly: imageId) {
            registerKittyImageMetadata(
                imageID: imageID,
                columns: size.columns,
                rows: size.rows,
                widthPx: imageDimensions.widthPx,
                heightPx: imageDimensions.heightPx
            )
        }
        let sequence = encodeKitty(
            base64Data: base64Data,
            columns: size.columns,
            rows: size.rows,
            imageId: options.imageId,
            moveCursor: options.moveCursor
        )
        return (sequence, size.columns, size.rows, options.imageId)
    case .iterm2:
        let sequence = encodeITerm2(
            base64Data: base64Data,
            width: String(size.columns),
            height: "auto",
            name: nil,
            preserveAspectRatio: options.preserveAspectRatio ?? true,
            inline: true
        )
        return (sequence, size.columns, size.rows, nil)
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
