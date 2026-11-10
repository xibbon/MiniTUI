import Foundation
import Testing
@testable import MiniTui

private struct CJKPunctuationFixture: Decodable {
    let source: String
    let node: String
    let icu: String
    let unicode: String
    let ranges: [[UInt32]]
}

@Test("CJK punctuation matches every Unicode scalar in the Node 22 upstream-regex fixture")
func cjkPunctuationMatchesUpstreamFixture() throws {
    let url = try #require(Bundle.module.url(forResource: "cjk-punctuation-v1.5.2", withExtension: "json"))
    let fixture = try JSONDecoder().decode(CJKPunctuationFixture.self, from: Data(contentsOf: url))
    #expect(fixture.source == "pi-mono v1.5.2 packages/tui/src/utils.ts cjkPunctuationRegex")
    #expect(fixture.node.hasPrefix("22."))
    #expect(fixture.unicode == "17.0")
    var rangeIndex = 0
    var mismatches: [UInt32] = []
    for value: UInt32 in 0...0x10FFFF {
        while rangeIndex < fixture.ranges.count, value > fixture.ranges[rangeIndex][1] {
            rangeIndex += 1
        }
        let expected = rangeIndex < fixture.ranges.count && value >= fixture.ranges[rangeIndex][0]
        guard let scalar = Unicode.Scalar(value) else { continue }
        if isCJKPunctuation(scalar) != expected { mismatches.append(value) }
    }
    #expect(mismatches.isEmpty, "Scalar mismatches: \(mismatches.map { String(format: "U+%04X", $0) })")
    for value: UInt32 in [0x301C, 0x3014, 0x3015, 0x3016, 0x3017, 0x301D, 0x301E, 0x30A0, 0x3003] {
        let character = Character(String(try #require(Unicode.Scalar(value))))
        #expect(isAutocompleteSeparator(character))
        #expect(isCJKPunctuation(character))
    }
    #expect(!isCJKPunctuation("字" as Character))
    #expect(!isAutocompleteSeparator("字"))
    // The tagged regex does not match these two characters despite the review's example list.
    #expect(!isCJKPunctuation(Character(String(try #require(Unicode.Scalar(0xFF5F))))))
    #expect(!isCJKPunctuation(Character(String(try #require(Unicode.Scalar(0xFF60))))))
}

@Test("OS ICU CJK punctuation agrees with the Node 22 fixture for every Unicode scalar")
func cjkPunctuationNodeVersusOSICU() throws {
    let url = try #require(Bundle.module.url(forResource: "cjk-punctuation-v1.5.2", withExtension: "json"))
    let fixture = try JSONDecoder().decode(CJKPunctuationFixture.self, from: Data(contentsOf: url))
    let pattern = #"(?:(?=\p{Punctuation})[\p{scx=Han}\p{scx=Hiragana}\p{scx=Katakana}\p{scx=Hangul}\p{scx=Bopomofo}]|[，．：；！？（）［］｛｝“”‘’…—])"#
    let regex = try NSRegularExpression(pattern: pattern)
    var rangeIndex = 0
    var differences: [UInt32] = []
    for value: UInt32 in 0...0x10FFFF {
        while rangeIndex < fixture.ranges.count, value > fixture.ranges[rangeIndex][1] {
            rangeIndex += 1
        }
        let nodeMatches = rangeIndex < fixture.ranges.count && value >= fixture.ranges[rangeIndex][0]
        guard let scalar = Unicode.Scalar(value) else { continue }
        let text = String(scalar)
        let icuMatches = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil
        if nodeMatches != icuMatches { differences.append(value) }
    }
    #expect(differences.isEmpty, "Node versus OS ICU differences: \(differences.map { String(format: "U+%04X", $0) })")
}
