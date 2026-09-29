import Testing
@testable import MiniTui

@MainActor
@Suite("Kitty redraw image encoding", .serialized)
struct KittyRedrawImageTests {
    @Test("Kitty can suppress terminal cursor movement")
    func cursorControl() {
        let defaultSequence = encodeKitty(base64Data: "AAAA", columns: 2, rows: 2)
        #expect(defaultSequence.hasPrefix("\u{001B}_Ga=T,f=100,q=2,c=2,r=2;"))
        let stationary = encodeKitty(base64Data: "AAAA", columns: 2, rows: 2, moveCursor: false)
        #expect(stationary.hasPrefix("\u{001B}_Ga=T,f=100,q=2,C=1,c=2,r=2;"))
        let chunked = encodeKitty(base64Data: String(repeating: "A", count: 4097),
            columns: 2, rows: 2, moveCursor: false)
        #expect(chunked.hasPrefix("\u{001B}_Ga=T,f=100,q=2,C=1,c=2,r=2,m=1;"))
    }

    @Test("renderImage leaves IDs and cursor movement under caller control")
    func renderOptions() throws {
        let savedCells = getCellDimensions()
        defer {
            setCellDimensions(savedCells)
            setCapabilities(nil)
        }
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        setCellDimensions(CellDimensions(widthPx: 10, heightPx: 10))
        let dimensions = ImageDimensions(widthPx: 20, heightPx: 20)

        let defaultImage = try #require(renderImage(base64Data: "AAAA", imageDimensions: dimensions,
            options: ImageRenderOptions(maxWidthCells: 2)))
        #expect(defaultImage.rows == 2)
        #expect(defaultImage.imageId == nil)
        #expect(!defaultImage.sequence.contains(",C=1,"))
        #expect(getKittyImageMetadata(defaultImage.sequence) == nil)

        let stationary = try #require(renderImage(base64Data: "AAAA", imageDimensions: dimensions,
            options: ImageRenderOptions(maxWidthCells: 2, imageId: 42, moveCursor: false)))
        #expect(stationary.imageId == 42)
        #expect(stationary.sequence.contains(",C=1,c=2,r=2,i=42;"))
        #expect(getKittyImageMetadata(stationary.sequence)?.imageID == 42)
        #expect(getKittyImagePlacement(stationary.sequence)?.replacementLine.contains(",C=1,") == true)
    }

    @Test("Kitty metadata refreshes an ID and evicts the oldest transmission")
    func metadataRegistrationOrder() throws {
        defer { setCapabilities(nil) }
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        let dimensions = ImageDimensions(widthPx: 9, heightPx: 18)
        func register(_ id: Int) throws -> String {
            try #require(renderImage(base64Data: "AAAA", imageDimensions: dimensions,
                options: ImageRenderOptions(imageId: id))?.sequence)
        }

        let first = try register(100_000)
        let firstGeneration = try #require(getKittyImageMetadata(first)?.transmissionGeneration)
        _ = try register(100_001)
        let refreshed = try register(100_000)
        let refreshedGeneration = try #require(getKittyImageMetadata(refreshed)?.transmissionGeneration)
        #expect(refreshedGeneration > firstGeneration)
        for id in 100_002...101_000 { _ = try register(id) }
        #expect(getKittyImageMetadata(first) != nil)
        #expect(getKittyImageMetadata("\u{001B}_Gi=100001;AAAA\u{001B}\\") == nil)
    }

    @Test("Image keeps one Kitty ID across invalidation and width changes")
    func componentID() throws {
        let savedCells = getCellDimensions()
        defer {
            setCellDimensions(savedCells)
            setCapabilities(nil)
        }
        setCapabilities(TerminalCapabilities(images: .kitty, trueColor: true, hyperlinks: true))
        setCellDimensions(CellDimensions(widthPx: 10, heightPx: 10))
        let image = Image(base64Data: "AAAA", mimeType: "image/png",
            theme: ImageTheme(fallbackColor: { $0 }),
            options: ImageOptions(maxWidthCells: 2),
            dimensions: ImageDimensions(widthPx: 20, heightPx: 20))
        #expect(image.getImageId() == nil)
        let first = image.render(width: 4)
        let assignedID = try #require(image.getImageId())
        #expect(assignedID > 0)
        #expect(first.count == 2 && first[1].isEmpty)
        #expect(first[0].hasPrefix("\u{001B}_Ga=T,f=100,q=2,C=1,c=2,r=2,i=\(assignedID);"))
        image.invalidate()
        let second = image.render(width: 4)
        #expect(image.getImageId() == assignedID)
        #expect(second[0] == first[0])
        _ = image.render(width: 3)
        #expect(image.getImageId() == assignedID)
        let explicit = Image(base64Data: "AAAA", mimeType: "image/png",
            theme: ImageTheme(fallbackColor: { $0 }),
            options: ImageOptions(maxWidthCells: 2, imageId: 77),
            dimensions: ImageDimensions(widthPx: 20, heightPx: 20))
        #expect(explicit.getImageId() == 77)
        #expect(explicit.render(width: 4)[0].contains(",i=77;"))
    }

    @Test("iTerm2 keeps its last-line image placement")
    func itermPlacement() {
        let savedCells = getCellDimensions()
        defer {
            setCellDimensions(savedCells)
            setCapabilities(nil)
        }
        setCapabilities(TerminalCapabilities(images: .iterm2, trueColor: true, hyperlinks: true))
        setCellDimensions(CellDimensions(widthPx: 10, heightPx: 10))
        let image = Image(base64Data: "AAAA", mimeType: "image/png",
            theme: ImageTheme(fallbackColor: { $0 }),
            options: ImageOptions(maxWidthCells: 2),
            dimensions: ImageDimensions(widthPx: 20, heightPx: 20))
        let lines = image.render(width: 4)
        #expect(lines.count == 2)
        #expect(lines[0].isEmpty)
        #expect(lines[1].hasPrefix("\u{001B}[1A\u{001B}]1337;File="))
        #expect(image.getImageId() == nil)
    }
}
