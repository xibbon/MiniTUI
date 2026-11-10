import Foundation

// Generated from pi-mono v1.5.2 cjkPunctuationRegex by the test resource generator.
// Node 22.23.1, ICU 78.2, Unicode 17.0.
private let cjkPunctuationRanges: [(UInt32, UInt32)] = [
    (0xB7, 0xB7),
    (0x2014, 0x2014),
    (0x2018, 0x2019),
    (0x201C, 0x201D),
    (0x2026, 0x2026),
    (0x3001, 0x3003),
    (0x3008, 0x3011),
    (0x3014, 0x301F),
    (0x3030, 0x3030),
    (0x303D, 0x303D),
    (0x30A0, 0x30A0),
    (0x30FB, 0x30FB),
    (0xFE45, 0xFE46),
    (0xFF01, 0xFF01),
    (0xFF08, 0xFF09),
    (0xFF0C, 0xFF0C),
    (0xFF0E, 0xFF0E),
    (0xFF1A, 0xFF1B),
    (0xFF1F, 0xFF1F),
    (0xFF3B, 0xFF3B),
    (0xFF3D, 0xFF3D),
    (0xFF5B, 0xFF5B),
    (0xFF5D, 0xFF5D),
    (0xFF61, 0xFF65),
    (0x16FE2, 0x16FE2),
]

/// Match the punctuation boundary used by the tagged TUI for CJK text.
func isCJKPunctuation(_ scalar: Unicode.Scalar) -> Bool {
    let value = scalar.value
    var lower = 0
    var upper = cjkPunctuationRanges.count
    while lower < upper {
        let middle = lower + (upper - lower) / 2
        let range = cjkPunctuationRanges[middle]
        if value < range.0 {
            upper = middle
        } else if value > range.1 {
            lower = middle + 1
        } else {
            return true
        }
    }
    return false
}

func isCJKPunctuation(_ character: Character) -> Bool {
    character.unicodeScalars.contains(where: isCJKPunctuation)
}
