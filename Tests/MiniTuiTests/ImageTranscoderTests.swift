import Foundation
import Testing
@testable import MiniTui

@Suite("Image transcoding", .serialized)
@MainActor
struct ImageTranscoderTests {
    private let jpeg = Data("jpeg".utf8).base64EncodedString()
    // PNG signature and IHDR dimensions for a 40x10 image.
    private let png = Data([
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x28, 0x00, 0x00, 0x00, 0x0a,
    ]).base64EncodedString()

    private func withState(_ body: () throws -> Void) rethrows {
        let savedCells = getCellDimensions()
        defer {
            setImageTranscoder(nil)
            setCapabilities(nil)
            setCellDimensions(savedCells)
        }
        setImageTranscoder(nil)
        setCapabilities(.init(images: .kitty, trueColor: true, hyperlinks: true))
        setCellDimensions(.init(widthPx: 10, heightPx: 10))
        try body()
    }

    private func image(_ data: String, mimeType: String = "image/jpeg") -> Image {
        Image(base64Data: data, mimeType: mimeType, theme: .init(fallbackColor: { $0 }),
            dimensions: .init(widthPx: 20, heightPx: 20))
    }

    @Test("sends converted PNG data sized from the PNG")
    func convertedDimensions() throws {
        try withState {
            setImageTranscoder { data, _ in data == jpeg ? png : nil }
            let lines = image(jpeg).render(width: 20)
            let first = try #require(lines.first)
            #expect(first.contains("f=100") && first.contains(";\(png)\u{1B}\\"))
            #expect(lines.count == 5)
            let metadata = try #require(getKittyImageMetadata(first))
            #expect(metadata.widthPx == 40 && metadata.heightPx == 10)
        }
    }

    @Test("renders a text fallback until a working transcoder is registered")
    func registrationRetry() {
        withState {
            let image = Image(base64Data: jpeg, mimeType: "image/jpeg", theme: .init(fallbackColor: { $0 }))
            #expect(image.render(width: 80)[0].hasPrefix("[Image: [image/jpeg]"))
            #expect(image.getImageId() == nil)
            setImageTranscoder { _, _ in nil }
            image.invalidate()
            #expect(image.render(width: 80)[0].hasPrefix("[Image: [image/jpeg]"))
            setImageTranscoder { data, _ in data == jpeg ? png : nil }
            image.invalidate()
            #expect(image.render(width: 80)[0].contains("\u{1B}_G"))
        }
    }

    @Test("converts each image once")
    func instanceRetention() {
        withState {
            var calls: [String] = []
            setImageTranscoder { data, _ in
                calls.append(data)
                return data == jpeg ? png : nil
            }
            let original = image(jpeg)
            _ = original.render(width: 80)
            _ = image(jpeg).render(width: 20)
            for index in 0..<40 { _ = image("other-\(index)").render(width: 20) }
            original.invalidate()
            _ = original.render(width: 40)
            #expect(calls.filter { $0 == jpeg }.count == 1)
        }
    }

    @Test("does not convert PNG data or iTerm2 output")
    func protocolBypass() {
        withState {
            var calls: [String] = []
            setImageTranscoder { data, _ in
                calls.append(data)
                return png
            }
            #expect(image(png, mimeType: "image/png").render(width: 20)[0].contains(";\(png)\u{1B}\\"))
            setCapabilities(.init(images: .iterm2, trueColor: true, hyperlinks: true))
            #expect(image(jpeg).render(width: 20).last?.hasSuffix(":\(jpeg)\u{7}") == true)
            setCapabilities(.init(images: nil, trueColor: true, hyperlinks: true))
            #expect(!isImageLine(image(jpeg).render(width: 20)[0]))
            #expect(calls.isEmpty)
        }
    }

    @Test("shared cache keeps failures and uses only the source data as its key")
    func cachedFailures() {
        withState {
            var calls: [String] = []
            setImageTranscoder { data, mime in
                calls.append(data + mime)
                return nil
            }
            let original = image(jpeg)
            _ = original.render(width: 80)
            original.invalidate()
            _ = original.render(width: 40)
            _ = image(jpeg, mimeType: "image/webp").render(width: 20)
            #expect(calls == [jpeg + "image/jpeg"])
            setImageTranscoder { data, _ in
                calls.append(data)
                return png
            }
            original.invalidate()
            #expect(isImageLine(original.render(width: 80)[0]))
            #expect(calls.count == 2)
        }
    }

    @Test("shared cache has exactly 32 entries and refreshes hits before eviction")
    func exactLRU() {
        withState {
            var calls: [String] = []
            setImageTranscoder { data, _ in
                calls.append(data)
                return png
            }
            for index in 0..<32 { _ = image("source-\(index)").render(width: 20) }
            _ = image("source-0").render(width: 20)
            #expect(calls.count == 32)
            _ = image("source-32").render(width: 20)
            _ = image("source-0").render(width: 20)
            #expect(calls.count == 33)
            _ = image("source-1").render(width: 20)
            #expect(calls.count == 34 && calls.last == "source-1")
        }
    }

    @Test("failed sources are tried again after shared cache eviction")
    func failureEviction() {
        withState {
            var calls: [String] = []
            setImageTranscoder { data, _ in
                calls.append(data)
                return nil
            }
            _ = image(jpeg).render(width: 20)
            for index in 0..<32 { _ = image("other-\(index)").render(width: 20) }
            _ = image(jpeg).render(width: 20)
            #expect(calls.filter { $0 == jpeg }.count == 2)
        }
    }

    @Test("hook registration clears shared entries while instances keep successful PNG data")
    func hookReplacement() {
        withState {
            setImageTranscoder { _, _ in png }
            let original = image(jpeg)
            let first = original.render(width: 20)
            var calls = 0
            setImageTranscoder { _, _ in
                calls += 1
                return nil
            }
            original.invalidate()
            #expect(original.render(width: 20) == first)
            #expect(!isImageLine(image(jpeg).render(width: 20)[0]))
            #expect(calls == 1)
            setImageTranscoder(nil)
            #expect(!isImageLine(image("new-source").render(width: 20)[0]))
        }
    }

    @Test("Kitty compares the PNG MIME type exactly")
    func exactMimeType() {
        withState {
            var mimes: [String] = []
            setImageTranscoder { _, mime in
                mimes.append(mime)
                return png
            }
            _ = image(png, mimeType: "image/png").render(width: 20)
            _ = image(png, mimeType: "Image/PNG").render(width: 20)
            #expect(mimes == ["Image/PNG"])
        }
    }

    @Test("fallback uses source details and truncates styled text to the render width")
    func boundedFallback() {
        withState {
            let source = Image(base64Data: jpeg, mimeType: "image/jpeg",
                theme: .init(fallbackColor: { "\u{1B}[31m" + $0 + "\u{1B}[0m" }),
                options: .init(filename: "source.jpg"), dimensions: .init(widthPx: 20, heightPx: 30))
            let fallback = imageFallback("image/jpeg", dimensions: .init(widthPx: 20, heightPx: 30), filename: "source.jpg")
            #expect(stripTerminalSequences(source.render(width: 80)[0]) == fallback)
            #expect(source.render(width: 12)[0] == truncateToWidth("\u{1B}[31m" + fallback + "\u{1B}[0m", maxWidth: 12))
            #expect(visibleWidth(source.render(width: 12)[0]) == 12)
            #expect(source.render(width: 0) == [""])
            setCapabilities(.init(images: nil, trueColor: true, hyperlinks: true))
            source.invalidate()
            #expect(visibleWidth(source.render(width: 8)[0]) == 8)
        }
    }

    @Test("converted data without PNG dimensions uses source dimensions")
    func sourceDimensionFallback() throws {
        try withState {
            setImageTranscoder { _, _ in "AAAA" }
            let lines = image(jpeg).render(width: 20)
            #expect(lines.count == 18)
            let metadata = try #require(getKittyImageMetadata(lines[0]))
            #expect(metadata.widthPx == 20 && metadata.heightPx == 20)
        }
    }

    @Test("empty converted data produces a source text fallback")
    func emptyConversion() {
        withState {
            setImageTranscoder { _, _ in "" }
            #expect(image(jpeg).render(width: 80) == [imageFallback("image/jpeg", dimensions: .init(widthPx: 20, heightPx: 20))])
        }
    }
}
