import Testing
import MiniTui

@Test("empty query matches everything with score 0")
func fuzzyMatchEmptyQuery() {
    let result = fuzzyMatch("", "anything")
    #expect(result.matches)
    #expect(result.score == 0)
}

@Test("query longer than text does not match")
func fuzzyMatchQueryLongerThanText() {
    let result = fuzzyMatch("longquery", "short")
    #expect(!result.matches)
}

@Test("exact match scores well")
func fuzzyMatchExactMatchScore() {
    let result = fuzzyMatch("test", "test")
    #expect(result.matches)
    #expect(result.score < 0)
}

@Test("characters must appear in order")
func fuzzyMatchOrderMatters() {
    let matchInOrder = fuzzyMatch("abc", "aXbXc")
    #expect(matchInOrder.matches)

    let matchOutOfOrder = fuzzyMatch("abc", "cba")
    #expect(!matchOutOfOrder.matches)
}

@Test("case insensitive matching")
func fuzzyMatchCaseInsensitive() {
    let result = fuzzyMatch("ABC", "abc")
    #expect(result.matches)

    let result2 = fuzzyMatch("abc", "ABC")
    #expect(result2.matches)
}

@Test("consecutive matches score better than scattered matches")
func fuzzyMatchConsecutiveScore() {
    let consecutive = fuzzyMatch("foo", "foobar")
    let scattered = fuzzyMatch("foo", "fxoxoxbar")
    #expect(consecutive.matches)
    #expect(scattered.matches)
    #expect(consecutive.score < scattered.score)
}

@Test("word boundary matches score better")
func fuzzyMatchWordBoundary() {
    let atBoundary = fuzzyMatch("fb", "foo-bar")
    let notAtBoundary = fuzzyMatch("fb", "afbx")
    #expect(atBoundary.matches)
    #expect(notAtBoundary.matches)
    #expect(atBoundary.score < notAtBoundary.score)
}

@Test("fuzzyFilter returns all items when query is empty")
func fuzzyFilterEmptyQuery() {
    let items = ["alpha", "beta", "gamma"]
    let result = fuzzyFilter(items, query: "") { $0 }
    #expect(result == items)
}

@Test("fuzzyFilter matches all tokens")
func fuzzyFilterMultipleTokens() {
    let items = ["foo bar", "foo baz", "bar baz"]
    let result = fuzzyFilter(items, query: "foo ba") { $0 }
    #expect(result == ["foo bar", "foo baz"])
}
