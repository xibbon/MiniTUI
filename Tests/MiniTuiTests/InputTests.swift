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
