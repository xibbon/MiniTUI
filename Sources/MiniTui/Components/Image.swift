import Foundation

/// Theme configuration for image rendering.
public struct ImageTheme: Sendable {
    /// Style for fallback text when images are not supported.
    public let fallbackColor: @Sendable (String) -> String

    /// Create an image theme.
    public init(fallbackColor: @escaping @Sendable (String) -> String) {
        self.fallbackColor = fallbackColor
    }
}

/// Options that control how images are rendered.
public struct ImageOptions {
    /// Maximum width in terminal cells.
    public let maxWidthCells: Int?
    /// Maximum height in terminal cells.
    public let maxHeightCells: Int?
    /// Optional filename used for fallback text.
    public let filename: String?
    /// Kitty image ID. The component reuses this ID for updates when supplied.
    public let imageId: Int?

    /// Create image render options.
    public init(maxWidthCells: Int? = nil, maxHeightCells: Int? = nil, filename: String? = nil, imageId: Int? = nil) {
        self.maxWidthCells = maxWidthCells
        self.maxHeightCells = maxHeightCells
        self.filename = filename
        self.imageId = imageId
    }
}

/// Image renderer that uses Kitty/iTerm protocols when available.
public final class Image: Component {
    private let base64Data: String
    private let mimeType: String
    private let theme: ImageTheme
    private let options: ImageOptions
    private let dimensions: ImageDimensions
    private var imageId: Int?

    private var cachedLines: [String]?
    private var cachedWidth: Int?

    /// Create an image component.
    public init(
        base64Data: String,
        mimeType: String,
        theme: ImageTheme,
        options: ImageOptions = ImageOptions(),
        dimensions: ImageDimensions? = nil
    ) {
        self.base64Data = base64Data
        self.mimeType = mimeType
        self.theme = theme
        self.options = options
        self.dimensions = dimensions ?? getImageDimensions(base64Data, mimeType: mimeType) ?? ImageDimensions(widthPx: 800, heightPx: 600)
        imageId = options.imageId
    }

    /// Return the Kitty image ID, including an ID assigned on the first render.
    public func getImageId() -> Int? { imageId }

    /// Clear cached render state.
    public func invalidate() {
        cachedLines = nil
        cachedWidth = nil
    }

    /// Render the image or a fallback description.
    public func render(width: Int) -> [String] {
        if let cachedLines, cachedWidth == width {
            return cachedLines
        }

        let maxWidth = max(1, min(width - 2, options.maxWidthCells ?? 60))
        let cellDimensions = getCellDimensions()
        let defaultMaxHeight = max(1, Int(ceil(
            Double(maxWidth * cellDimensions.widthPx) / Double(cellDimensions.heightPx)
        )))
        let maxHeight = options.maxHeightCells ?? defaultMaxHeight
        let caps = getCapabilities()
        let lines: [String]

        if caps.images != nil {
            if caps.images == .kitty, imageId == nil {
                imageId = Int(allocateImageId())
            }
            if let result = renderImage(
                base64Data: base64Data,
                imageDimensions: dimensions,
                options: ImageRenderOptions(
                    maxWidthCells: maxWidth,
                    maxHeightCells: maxHeight,
                    imageId: imageId,
                    moveCursor: false
                )
            ) {
                if let resultImageId = result.imageId { imageId = resultImageId }
                var rendered: [String] = []
                if caps.images == .kitty {
                    rendered.append(result.sequence)
                    rendered.append(contentsOf: Array(repeating: "", count: max(0, result.rows - 1)))
                } else if result.rows > 1 {
                    rendered.append(contentsOf: Array(repeating: "", count: result.rows - 1))
                    let moveUp = "\u{001B}[\(result.rows - 1)A"
                    rendered.append(moveUp + result.sequence)
                } else {
                    rendered.append(result.sequence)
                }
                lines = rendered
            } else {
                let fallback = imageFallback(mimeType, dimensions: dimensions, filename: options.filename)
                lines = [theme.fallbackColor(fallback)]
            }
        } else {
            let fallback = imageFallback(mimeType, dimensions: dimensions, filename: options.filename)
            lines = [theme.fallbackColor(fallback)]
        }

        cachedLines = lines
        cachedWidth = width

        return lines
    }
}
