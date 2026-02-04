import Testing
import Foundation
@testable import MiniTui

@Suite("StdinBuffer", .serialized)
struct StdinBufferTests {

    // MARK: - Regular Characters

    @Suite("Regular Characters")
    struct RegularCharactersTests {
        @Test("should pass through regular characters immediately")
        func passRegularCharacters() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("a")
            #expect(emittedSequences == ["a"])
        }

        @Test("should pass through multiple regular characters")
        func passMultipleCharacters() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("abc")
            #expect(emittedSequences == ["a", "b", "c"])
        }

        @Test("should handle unicode characters")
        func handleUnicode() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("hello 世界")
            #expect(emittedSequences == ["h", "e", "l", "l", "o", " ", "世", "界"])
        }
    }

    // MARK: - Complete Escape Sequences

    @Suite("Complete Escape Sequences")
    struct CompleteEscapeSequencesTests {
        @Test("should pass through complete mouse SGR sequences")
        func passMouseSGR() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            let mouseSeq = "\u{001B}[<35;20;5m"
            buffer.process(mouseSeq)
            #expect(emittedSequences == [mouseSeq])
        }

        @Test("should pass through complete arrow key sequences")
        func passArrowKeys() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            let upArrow = "\u{001B}[A"
            buffer.process(upArrow)
            #expect(emittedSequences == [upArrow])
        }

        @Test("should pass through complete function key sequences")
        func passFunctionKeys() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            let f1 = "\u{001B}[11~"
            buffer.process(f1)
            #expect(emittedSequences == [f1])
        }

        @Test("should pass through meta key sequences")
        func passMetaKey() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            let metaA = "\u{001B}a"
            buffer.process(metaA)
            #expect(emittedSequences == [metaA])
        }

        @Test("should pass through SS3 sequences")
        func passSS3() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            let ss3 = "\u{001B}OA"
            buffer.process(ss3)
            #expect(emittedSequences == [ss3])
        }
    }

    // MARK: - Partial Escape Sequences

    @Suite("Partial Escape Sequences")
    struct PartialEscapeSequencesTests {
        @Test("should buffer incomplete mouse SGR sequence")
        func bufferIncompleteMouse() async throws {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}")
            #expect(emittedSequences == [])
            #expect(buffer.getBuffer() == "\u{001B}")

            buffer.process("[<35")
            #expect(emittedSequences == [])
            #expect(buffer.getBuffer() == "\u{001B}[<35")

            buffer.process(";20;5m")
            #expect(emittedSequences == ["\u{001B}[<35;20;5m"])
            #expect(buffer.getBuffer() == "")
        }

        @Test("should buffer incomplete CSI sequence")
        func bufferIncompleteCSI() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[")
            #expect(emittedSequences == [])

            buffer.process("1;")
            #expect(emittedSequences == [])

            buffer.process("5H")
            #expect(emittedSequences == ["\u{001B}[1;5H"])
        }

        @Test("should buffer split across many chunks")
        func bufferSplitChunks() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}")
            buffer.process("[")
            buffer.process("<")
            buffer.process("3")
            buffer.process("5")
            buffer.process(";")
            buffer.process("2")
            buffer.process("0")
            buffer.process(";")
            buffer.process("5")
            buffer.process("m")

            #expect(emittedSequences == ["\u{001B}[<35;20;5m"])
        }

        @Test("should flush incomplete sequence after timeout")
        func flushAfterTimeout() async throws {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<35")
            #expect(emittedSequences == [])

            // Wait for timeout
            try await Task.sleep(nanoseconds: 15_000_000)

            #expect(emittedSequences == ["\u{001B}[<35"])
        }
    }

    // MARK: - Mixed Content

    @Suite("Mixed Content")
    struct MixedContentTests {
        @Test("should handle characters followed by escape sequence")
        func charsFollowedByEscape() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("abc\u{001B}[A")
            #expect(emittedSequences == ["a", "b", "c", "\u{001B}[A"])
        }

        @Test("should handle escape sequence followed by characters")
        func escapeFollowedByChars() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[Aabc")
            #expect(emittedSequences == ["\u{001B}[A", "a", "b", "c"])
        }

        @Test("should handle multiple complete sequences")
        func multipleCompleteSequences() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[A\u{001B}[B\u{001B}[C")
            #expect(emittedSequences == ["\u{001B}[A", "\u{001B}[B", "\u{001B}[C"])
        }

        @Test("should handle partial sequence with preceding characters")
        func partialWithPrecedingChars() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("abc\u{001B}[<35")
            #expect(emittedSequences == ["a", "b", "c"])
            #expect(buffer.getBuffer() == "\u{001B}[<35")

            buffer.process(";20;5m")
            #expect(emittedSequences == ["a", "b", "c", "\u{001B}[<35;20;5m"])
        }
    }

    // MARK: - Kitty Keyboard Protocol

    @Suite("Kitty Keyboard Protocol")
    struct KittyKeyboardProtocolTests {
        @Test("should handle Kitty CSI u press events")
        func kittyPressEvents() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Press 'a' in Kitty protocol
            buffer.process("\u{001B}[97u")
            #expect(emittedSequences == ["\u{001B}[97u"])
        }

        @Test("should handle Kitty CSI u release events")
        func kittyReleaseEvents() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Release 'a' in Kitty protocol
            buffer.process("\u{001B}[97;1:3u")
            #expect(emittedSequences == ["\u{001B}[97;1:3u"])
        }

        @Test("should handle batched Kitty press and release")
        func batchedKittyPressRelease() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Press 'a', release 'a' batched together (common over SSH)
            buffer.process("\u{001B}[97u\u{001B}[97;1:3u")
            #expect(emittedSequences == ["\u{001B}[97u", "\u{001B}[97;1:3u"])
        }

        @Test("should handle multiple batched Kitty events")
        func multipleBatchedKittyEvents() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Press 'a', release 'a', press 'b', release 'b'
            buffer.process("\u{001B}[97u\u{001B}[97;1:3u\u{001B}[98u\u{001B}[98;1:3u")
            #expect(emittedSequences == ["\u{001B}[97u", "\u{001B}[97;1:3u", "\u{001B}[98u", "\u{001B}[98;1:3u"])
        }

        @Test("should handle Kitty arrow keys with event type")
        func kittyArrowKeys() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Up arrow press with event type
            buffer.process("\u{001B}[1;1:1A")
            #expect(emittedSequences == ["\u{001B}[1;1:1A"])
        }

        @Test("should handle Kitty functional keys with event type")
        func kittyFunctionalKeys() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Delete key release
            buffer.process("\u{001B}[3;1:3~")
            #expect(emittedSequences == ["\u{001B}[3;1:3~"])
        }

        @Test("should handle plain characters mixed with Kitty sequences")
        func plainCharsMixedWithKitty() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Plain 'a' followed by Kitty release
            buffer.process("a\u{001B}[97;1:3u")
            #expect(emittedSequences == ["a", "\u{001B}[97;1:3u"])
        }

        @Test("should handle Kitty sequence followed by plain characters")
        func kittyFollowedByPlainChars() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[97ua")
            #expect(emittedSequences == ["\u{001B}[97u", "a"])
        }

        @Test("should handle rapid typing simulation with Kitty protocol")
        func rapidTypingKitty() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            // Simulates typing "hi" quickly with releases interleaved
            buffer.process("\u{001B}[104u\u{001B}[104;1:3u\u{001B}[105u\u{001B}[105;1:3u")
            #expect(emittedSequences == ["\u{001B}[104u", "\u{001B}[104;1:3u", "\u{001B}[105u", "\u{001B}[105;1:3u"])
        }
    }

    // MARK: - Mouse Events

    @Suite("Mouse Events")
    struct MouseEventsTests {
        @Test("should handle mouse press event")
        func mousePress() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<0;10;5M")
            #expect(emittedSequences == ["\u{001B}[<0;10;5M"])
        }

        @Test("should handle mouse release event")
        func mouseRelease() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<0;10;5m")
            #expect(emittedSequences == ["\u{001B}[<0;10;5m"])
        }

        @Test("should handle mouse move event")
        func mouseMove() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<35;20;5m")
            #expect(emittedSequences == ["\u{001B}[<35;20;5m"])
        }

        @Test("should handle split mouse events")
        func splitMouseEvents() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<3")
            buffer.process("5;1")
            buffer.process("5;")
            buffer.process("10m")
            #expect(emittedSequences == ["\u{001B}[<35;15;10m"])
        }

        @Test("should handle multiple mouse events")
        func multipleMouseEvents() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<35;1;1m\u{001B}[<35;2;2m\u{001B}[<35;3;3m")
            #expect(emittedSequences == ["\u{001B}[<35;1;1m", "\u{001B}[<35;2;2m", "\u{001B}[<35;3;3m"])
        }

        @Test("should handle old-style mouse sequence (ESC[M + 3 bytes)")
        func oldStyleMouse() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[M abc")
            #expect(emittedSequences == ["\u{001B}[M ab", "c"])
        }

        @Test("should buffer incomplete old-style mouse sequence")
        func bufferIncompleteOldStyleMouse() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[M")
            #expect(buffer.getBuffer() == "\u{001B}[M")

            buffer.process(" a")
            #expect(buffer.getBuffer() == "\u{001B}[M a")

            buffer.process("b")
            #expect(emittedSequences == ["\u{001B}[M ab"])
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCasesTests {
        @Test("should handle empty input")
        func handleEmptyInput() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("")
            // Empty string emits an empty data event
            #expect(emittedSequences == [""])
        }

        @Test("should handle lone escape character with timeout")
        func loneEscapeWithTimeout() async throws {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}")
            #expect(emittedSequences == [])

            // After timeout, should emit
            try await Task.sleep(nanoseconds: 15_000_000)
            #expect(emittedSequences == ["\u{001B}"])
        }

        @Test("should handle lone escape character with explicit flush")
        func loneEscapeWithFlush() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}")
            #expect(emittedSequences == [])

            let flushed = buffer.flush()
            #expect(flushed == ["\u{001B}"])
        }

        @Test("should handle buffer input")
        func handleBufferInput() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            let data = Data("\u{001B}[A".utf8)
            buffer.process(data)
            #expect(emittedSequences == ["\u{001B}[A"])
        }

        @Test("should handle very long sequences")
        func handleLongSequences() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            let longSeq = "\u{001B}[" + String(repeating: "1;", count: 50) + "H"
            buffer.process(longSeq)
            #expect(emittedSequences == [longSeq])
        }
    }

    // MARK: - Flush

    @Suite("Flush")
    struct FlushTests {
        @Test("should flush incomplete sequences")
        func flushIncomplete() {
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            buffer.process("\u{001B}[<35")
            let flushed = buffer.flush()
            #expect(flushed == ["\u{001B}[<35"])
            #expect(buffer.getBuffer() == "")
        }

        @Test("should return empty array if nothing to flush")
        func flushEmpty() {
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            let flushed = buffer.flush()
            #expect(flushed == [])
        }

        @Test("should emit flushed data via timeout")
        func flushViaTimeout() async throws {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<35")
            #expect(emittedSequences == [])

            // Wait for timeout to flush
            try await Task.sleep(nanoseconds: 15_000_000)
            #expect(emittedSequences == ["\u{001B}[<35"])
        }
    }

    // MARK: - Clear

    @Suite("Clear")
    struct ClearTests {
        @Test("should clear buffered content without emitting")
        func clearBufferedContent() {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<35")
            #expect(buffer.getBuffer() == "\u{001B}[<35")

            buffer.clear()
            #expect(buffer.getBuffer() == "")
            #expect(emittedSequences == [])
        }
    }

    // MARK: - Bracketed Paste

    @Suite("Bracketed Paste")
    struct BracketedPasteTests {
        @Test("should emit paste event for complete bracketed paste")
        func completeBracketedPaste() {
            var emittedSequences: [String] = []
            var emittedPaste: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }
            _ = buffer.on(.paste) { data in
                emittedPaste.append(data)
            }

            let pasteStart = "\u{001B}[200~"
            let pasteEnd = "\u{001B}[201~"
            let content = "hello world"

            buffer.process(pasteStart + content + pasteEnd)

            #expect(emittedPaste == ["hello world"])
            #expect(emittedSequences == [])  // No data events during paste
        }

        @Test("should handle paste arriving in chunks")
        func pasteInChunks() {
            var emittedSequences: [String] = []
            var emittedPaste: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }
            _ = buffer.on(.paste) { data in
                emittedPaste.append(data)
            }

            buffer.process("\u{001B}[200~")
            #expect(emittedPaste == [])

            buffer.process("hello ")
            #expect(emittedPaste == [])

            buffer.process("world\u{001B}[201~")
            #expect(emittedPaste == ["hello world"])
            #expect(emittedSequences == [])
        }

        @Test("should handle paste with input before and after")
        func pasteWithInputBeforeAfter() {
            var emittedSequences: [String] = []
            var emittedPaste: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }
            _ = buffer.on(.paste) { data in
                emittedPaste.append(data)
            }

            buffer.process("a")
            buffer.process("\u{001B}[200~pasted\u{001B}[201~")
            buffer.process("b")

            #expect(emittedSequences == ["a", "b"])
            #expect(emittedPaste == ["pasted"])
        }

        @Test("should handle paste with newlines")
        func pasteWithNewlines() {
            var emittedSequences: [String] = []
            var emittedPaste: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }
            _ = buffer.on(.paste) { data in
                emittedPaste.append(data)
            }

            buffer.process("\u{001B}[200~line1\nline2\nline3\u{001B}[201~")

            #expect(emittedPaste == ["line1\nline2\nline3"])
            #expect(emittedSequences == [])
        }

        @Test("should handle paste with unicode")
        func pasteWithUnicode() {
            var emittedSequences: [String] = []
            var emittedPaste: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }
            _ = buffer.on(.paste) { data in
                emittedPaste.append(data)
            }

            buffer.process("\u{001B}[200~Hello 世界 🎉\u{001B}[201~")

            #expect(emittedPaste == ["Hello 世界 🎉"])
            #expect(emittedSequences == [])
        }
    }

    // MARK: - Destroy

    @Suite("Destroy")
    struct DestroyTests {
        @Test("should clear buffer on destroy")
        func clearBufferOnDestroy() {
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            buffer.process("\u{001B}[<35")
            #expect(buffer.getBuffer() == "\u{001B}[<35")

            buffer.destroy()
            #expect(buffer.getBuffer() == "")
        }

        @Test("should clear pending timeouts on destroy")
        func clearTimeoutsOnDestroy() async throws {
            var emittedSequences: [String] = []
            let buffer = StdinBuffer(options: StdinBufferOptions(timeout: 0.01))
            _ = buffer.on(.data) { sequence in
                emittedSequences.append(sequence)
            }

            buffer.process("\u{001B}[<35")
            buffer.destroy()

            // Wait longer than timeout
            try await Task.sleep(nanoseconds: 15_000_000)

            // Should not have emitted anything
            #expect(emittedSequences == [])
        }
    }
}
