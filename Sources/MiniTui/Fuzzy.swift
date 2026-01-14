import Foundation

/// Result of a fuzzy match operation.
public struct FuzzyMatch: Sendable, Equatable {
    public let matches: Bool
    public let score: Double

    public init(matches: Bool, score: Double) {
        self.matches = matches
        self.score = score
    }
}

/// Return whether all characters in the query appear in order (case-insensitive).
/// Lower score means a better match.
public func fuzzyMatch(_ query: String, _ text: String) -> FuzzyMatch {
    let queryLower = query.lowercased()
    let textLower = text.lowercased()

    if queryLower.isEmpty {
        return FuzzyMatch(matches: true, score: 0)
    }

    if queryLower.count > textLower.count {
        return FuzzyMatch(matches: false, score: 0)
    }

    let queryChars = Array(queryLower)
    let textChars = Array(textLower)
    var queryIndex = 0
    var score = 0.0
    var lastMatchIndex: Int? = nil
    var consecutiveMatches = 0

    for i in 0..<textChars.count {
        if queryIndex >= queryChars.count {
            break
        }
        if textChars[i] != queryChars[queryIndex] {
            continue
        }

        let isWordBoundary: Bool
        if i == 0 {
            isWordBoundary = true
        } else {
            let prev = textChars[i - 1]
            isWordBoundary = prev == " " || prev == "\t" || prev == "\n" || "-_./:".contains(prev)
        }

        if let last = lastMatchIndex, last == i - 1 {
            consecutiveMatches += 1
            score -= Double(consecutiveMatches * 5)
        } else {
            consecutiveMatches = 0
            if let last = lastMatchIndex {
                score += Double(i - last - 1) * 2
            }
        }

        if isWordBoundary {
            score -= 10
        }

        score += Double(i) * 0.1
        lastMatchIndex = i
        queryIndex += 1
    }

    if queryIndex < queryChars.count {
        return FuzzyMatch(matches: false, score: 0)
    }

    return FuzzyMatch(matches: true, score: score)
}

/// Filter and sort items by fuzzy match quality (best matches first).
/// Supports space-separated tokens; all tokens must match.
public func fuzzyFilter<T>(_ items: [T], query: String, getText: (T) -> String) -> [T] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
        return items
    }

    let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
    if tokens.isEmpty {
        return items
    }

    var results: [(item: T, score: Double)] = []
    results.reserveCapacity(items.count)

    for item in items {
        let text = getText(item)
        var totalScore = 0.0
        var allMatch = true

        for token in tokens {
            let match = fuzzyMatch(token, text)
            if match.matches {
                totalScore += match.score
            } else {
                allMatch = false
                break
            }
        }

        if allMatch {
            results.append((item: item, score: totalScore))
        }
    }

    results.sort { $0.score < $1.score }
    return results.map { $0.item }
}
