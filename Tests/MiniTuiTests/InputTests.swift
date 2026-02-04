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
