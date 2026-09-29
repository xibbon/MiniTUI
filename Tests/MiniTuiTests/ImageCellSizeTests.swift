import Testing
@testable import MiniTui

@Suite("Image cell size")
@MainActor
struct ImageCellSizeTests {
    @Test("Kitty uses the less distorted row count")
    func kittyRows() {
        let cells = CellDimensions(widthPx: 9, heightPx: 18)
        let image = ImageDimensions(widthPx: 615, heightPx: 86)
        #expect(calculateImageCellSize(imageDimensions: image, maxWidthCells: 60,
            cellDimensions: cells, optimizeAspectRatio: true) == ImageCellSize(columns: 60, rows: 4))
        #expect(calculateImageCellSize(imageDimensions: image, maxWidthCells: 60,
            cellDimensions: cells) == ImageCellSize(columns: 60, rows: 5))
        #expect(calculateImageCellSize(imageDimensions: ImageDimensions(widthPx: 1200, heightPx: 12),
            maxWidthCells: 60, cellDimensions: cells, optimizeAspectRatio: true).rows == 1)
    }

    @Test("Kitty keeps the ceiling when it fits better")
    func ceilingRows() {
        #expect(calculateImageCellSize(
            imageDimensions: ImageDimensions(widthPx: 615, heightPx: 86), maxWidthCells: 60,
            cellDimensions: CellDimensions(widthPx: 15, heightPx: 28), optimizeAspectRatio: true
        ) == ImageCellSize(columns: 60, rows: 5))
    }

    @Test("height limits use different Kitty and iTerm2 column counts")
    func heightLimited() {
        let image = ImageDimensions(widthPx: 400, heightPx: 900)
        let cells = CellDimensions(widthPx: 14, heightPx: 28)
        #expect(calculateImageCellSize(imageDimensions: image, maxWidthCells: 30, maxHeightCells: 15,
            cellDimensions: cells, optimizeAspectRatio: true) == ImageCellSize(columns: 13, rows: 15))
        #expect(calculateImageCellSize(imageDimensions: image, maxWidthCells: 30, maxHeightCells: 15,
            cellDimensions: cells) == ImageCellSize(columns: 14, rows: 15))
    }

    @Test("Kitty keeps at least one cell for thin images")
    func thinWidths() {
        let cells = CellDimensions(widthPx: 1, heightPx: 1)
        for (width, columns) in [(1, 1), (140, 1), (149, 2)] {
            #expect(calculateImageCellSize(
                imageDimensions: ImageDimensions(widthPx: width, heightPx: 1000),
                maxWidthCells: 30, maxHeightCells: 10,
                cellDimensions: cells, optimizeAspectRatio: true
            ) == ImageCellSize(columns: columns, rows: 10))
        }
    }

    @Test("image component passes its height limit to the renderer")
    func componentHeightLimit() {
        defer { setCapabilities(nil) }
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        let image = Image(base64Data: "AAAA", mimeType: "image/png",
            theme: ImageTheme(fallbackColor: { $0 }),
            options: ImageOptions(maxWidthCells: 30, maxHeightCells: 3),
            dimensions: ImageDimensions(widthPx: 400, heightPx: 900))
        #expect(image.render(width: 32).count == 3)
    }

    @Test("Kitty placements use optimized cells while iTerm2 keeps ceiling cells")
    func protocolReservations() throws {
        let savedCells = getCellDimensions()
        defer {
            setCellDimensions(savedCells)
            setCapabilities(nil)
        }
        setCellDimensions(CellDimensions(widthPx: 9, heightPx: 18))
        let image = ImageDimensions(widthPx: 615, heightPx: 86)
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        let kitty = try #require(renderImage(base64Data: "AAAA", imageDimensions: image,
            options: ImageRenderOptions(maxWidthCells: 60)))
        #expect(kitty.columns == 60 && kitty.rows == 4)
        #expect(kitty.sequence.contains(",c=60,r=4"))

        setCapabilities(TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: true))
        let iterm = try #require(renderImage(base64Data: "AAAA", imageDimensions: image,
            options: ImageRenderOptions(maxWidthCells: 60)))
        #expect(iterm.columns == 60 && iterm.rows == 5)
        #expect(iterm.sequence.contains("width=60;height=auto"))

        setCellDimensions(CellDimensions(widthPx: 14, heightPx: 28))
        let tall = ImageDimensions(widthPx: 400, heightPx: 900)
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        let tallKitty = try #require(renderImage(base64Data: "AAAA", imageDimensions: tall,
            options: ImageRenderOptions(maxWidthCells: 30, maxHeightCells: 15)))
        #expect(tallKitty.columns == 13 && tallKitty.rows == 15)
        setCapabilities(TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: true))
        let tallITerm = try #require(renderImage(base64Data: "AAAA", imageDimensions: tall,
            options: ImageRenderOptions(maxWidthCells: 30, maxHeightCells: 15)))
        #expect(tallITerm.columns == 14 && tallITerm.rows == 15)
    }
}
