import Testing
import MiniTui

@MainActor
@Test("Ctrl-D triggers onEnd only when input is empty")
func ctrlDEndsInputWhenEmpty() {
    let input = Input()
    var didEnd = false
    var submitted: String?

    input.onEnd = {
        didEnd = true
    }
    input.onSubmit = { value in
        submitted = value
    }

    input.handleInput("\u{0004}")

    #expect(didEnd)
    #expect(submitted == nil)
    #expect(input.getValue() == "")
}

@MainActor
@Test("Ctrl-D deletes forward when input is not empty")
func ctrlDDeletesWhenNotEmpty() {
    let input = Input()
    var didEnd = false
    var submitted: String?

    input.setValue("hello")
    input.handleInput("\u{0001}")
    input.onEnd = {
        didEnd = true
    }
    input.onSubmit = { value in
        submitted = value
    }

    input.handleInput("\u{0004}")

    #expect(!didEnd)
    #expect(submitted == nil)
    #expect(input.getValue() == "ello")
}

@MainActor
@Test("Ctrl-U kill can be yanked back in input")
func ctrlUKillCanBeYankedBack() {
    let input = Input()
    input.setValue("one two three")
    input.handleInput("\u{0005}") // Ctrl+E

    input.handleInput("\u{0015}") // Ctrl+U
    #expect(input.getValue() == "")

    input.handleInput("\u{0019}") // Ctrl+Y
    #expect(input.getValue() == "one two three")
}

@MainActor
@Test("input yank-pop cycles kill ring entries")
func inputYankPopCyclesKillRing() {
    let input = Input()
    input.setValue("one two three")
    input.handleInput("\u{0005}") // Ctrl+E

    input.handleInput("\u{0015}") // Ctrl+U kills "one two three"
    input.handleInput("x") // Break kill chain
    input.handleInput("\u{0015}") // Ctrl+U kills "x"
    input.handleInput("\u{0019}") // Ctrl+Y yanks "x"
    #expect(input.getValue() == "x")

    input.handleInput("\u{001B}y") // Alt+Y yank-pop -> "one two three"
    #expect(input.getValue() == "one two three")
}

// MARK: - Wide character input tests

@MainActor
@Test("wide character input stores CJK text correctly")
func wideCharInputStoresCorrectly() {
    let input = Input()
    input.setValue("你好世界") // 4 CJK chars = 8 visible columns
    #expect(input.getValue() == "你好世界")
}

@MainActor
@Test("wide character input supports cursor movement")
func wideCharCursorMovement() {
    let input = Input()
    input.setValue("你好世界")
    // Move to beginning with Ctrl+A, then delete forward with Ctrl+D
    input.handleInput("\u{0001}") // Ctrl+A = beginning of line
    input.handleInput("\u{0004}") // Ctrl+D = delete forward
    #expect(input.getValue() == "好世界")
}

@MainActor
@Test("wide character input handles mixed ASCII and CJK")
func wideCharMixedContent() {
    let input = Input()
    input.setValue("hello你好world")
    #expect(input.getValue() == "hello你好world")
    // Kill line (Ctrl+U) should clear everything
    input.handleInput("\u{0005}") // Ctrl+E = end of line
    input.handleInput("\u{0015}") // Ctrl+U = kill line
    #expect(input.getValue() == "")
    // Yank it back
    input.handleInput("\u{0019}") // Ctrl+Y = yank
    #expect(input.getValue() == "hello你好world")
}
