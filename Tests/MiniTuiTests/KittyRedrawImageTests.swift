import Testing
@testable import MiniTui

@MainActor
@Suite("Kitty redraw image encoding", .serialized)
struct KittyRedrawImageTests {
    @Test("reads explicit placement rows without registered metadata")
    func explicitPlacementRows() {
        let sequence = encodeKitty(base64Data: "AAAA", columns: 2, rows: 3, moveCursor: false)
        #expect(getKittyImagePlacementRows(sequence) == 3)
    }

    @Test("creates placement-only commands for uploaded and cropped images")
    func croppedPlacementCommand() throws {
        registerKittyImageMetadata(imageID: 42, columns: 3, rows: 3, widthPx: 100, heightPx: 100)
        let transmission = encodeKitty(base64Data: String(repeating: "A", count: 8192),
            columns: 3, rows: 3, imageId: 42, moveCursor: false)
        let line = "left " + cropKittyImageLine(transmission, hiddenRows: 2, visibleRows: 1) + " right"
        let placement = try #require(getKittyImagePlacement(line))
        #expect(getKittyImagePlacementRows(line) == 1)
        #expect(placement.transmissionBytes == line.utf8.count - "left ".utf8.count - " right".utf8.count)
        #expect(placement.estimatedDecodedBytes == 100 * 100 * 4)
        #expect(placement.rows == 1)
        #expect(placement.sequence == "\u{1B}_Ga=p,q=2,C=1,c=3,i=42,y=66,h=34,r=1\u{1B}\\")
        #expect(placement.replacementLine == "left " + placement.sequence + " right")
        #expect(!placement.replacementLine.contains("AAAA"))
    }

    @Test("placement rows prefer positive controls and otherwise use registered metadata")
    func placementRowsPrecedence() throws {
        registerKittyImageMetadata(imageID: 103_190, columns: 2, rows: 4, widthPx: 20, heightPx: 40)
        for (controls, expected) in [("", 4), (",r=2", 2), (",r=0", 4), (",r=-1", 4),
            (",r=bad", 4), (",r=0,r=2", 4), (",r=bad,r=2", 2), (",r=02", 2)] {
            let line = "left \u{1B}_Gi=103190\(controls);AAAA,r=99\u{1B}\\ right"
            #expect(getKittyImagePlacementRows(line) == expected)
            #expect(try #require(getKittyImagePlacement(line)).rows == expected)
        }
        #expect(getKittyImagePlacementRows("\u{1B}_Gr=0;AAAA\u{1B}\\") == nil)
        #expect(getKittyImagePlacementRows("\u{1B}_G;r=99\u{1B}\\") == nil)
        #expect(getKittyImagePlacementRows("\u{1B}_Gr=3\u{1B}\\") == nil)
        #expect(getKittyImagePlacementRows("text") == nil)
    }

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
