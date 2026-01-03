import Foundation

extension String {
    func index(at offset: Int) -> Index {
        let clamped = max(0, min(offset, count))
        return index(startIndex, offsetBy: clamped)
    }

    func character(at offset: Int) -> Character? {
        guard offset >= 0 && offset < count else { return nil }
        return self[index(at: offset)]
    }

    func substring(from start: Int, length: Int) -> String {
        guard length > 0 else { return "" }
        let startIndex = index(at: start)
        let endIndex = index(startIndex, offsetBy: max(0, min(length, count - start)))
        return String(self[startIndex..<endIndex])
    }

    func prefixCharacters(_ count: Int) -> String {
        guard count > 0 else { return "" }
        let endIndex = index(at: count)
        return String(self[startIndex..<endIndex])
    }

    func suffixCharacters(_ count: Int) -> String {
        guard count > 0 else { return "" }
        let startIndex = index(endIndex, offsetBy: -max(0, min(count, self.count)))
        return String(self[startIndex..<endIndex])
    }
}
