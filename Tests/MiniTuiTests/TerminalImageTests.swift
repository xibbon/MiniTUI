import Testing
import Foundation
@testable import MiniTui

@Suite("isImageLine")
struct IsImageLineTests {

    // MARK: - iTerm2 image protocol

    @Suite("iTerm2 image protocol")
    struct ITerm2Tests {
        @Test("should detect iTerm2 image escape sequence at start of line")
        func detectITerm2AtStart() {
            // iTerm2 image escape sequence: ESC ]1337;File=...
            let iterm2ImageLine = "\u{001B}]1337;File=size=100,100;inline=1:base64encodeddata==\u{0007}"
            #expect(isImageLine(iterm2ImageLine) == true)
        }

        @Test("should detect iTerm2 image escape sequence with text before it")
        func detectITerm2WithTextBefore() {
            // Simulating a line that has text then image data (bug scenario)
            let lineWithTextAndImage = "Some text \u{001B}]1337;File=size=100,100;inline=1:base64data==\u{0007} more text"
            #expect(isImageLine(lineWithTextAndImage) == true)
        }

        @Test("should detect iTerm2 image escape sequence in middle of long line")
        func detectITerm2InMiddle() {
            // Simulate a very long line with image data in the middle
            let longLineWithImage =
                "Text before image..." + "\u{001B}]1337;File=inline=1:verylongbase64data==" + "...text after"
            #expect(isImageLine(longLineWithImage) == true)
        }

        @Test("should detect iTerm2 image escape sequence at end of line")
        func detectITerm2AtEnd() {
            let lineWithImageAtEnd = "Regular text ending with \u{001B}]1337;File=inline=1:base64data==\u{0007}"
            #expect(isImageLine(lineWithImageAtEnd) == true)
        }

        @Test("should detect minimal iTerm2 image escape sequence")
        func detectMinimalITerm2() {
            let minimalImageLine = "\u{001B}]1337;File=:\u{0007}"
            #expect(isImageLine(minimalImageLine) == true)
        }
    }

    // MARK: - Kitty image protocol

    @Suite("Kitty image protocol")
    struct KittyTests {
        @Test("should detect Kitty image escape sequence at start of line")
        func detectKittyAtStart() {
            // Kitty image escape sequence: ESC _G
            let kittyImageLine = "\u{001B}_Ga=T,f=100,t=f,d=base64data...\u{001B}\\\u{001B}_Gm=i=1;\u{001B}\\"
            #expect(isImageLine(kittyImageLine) == true)
        }

        @Test("should detect Kitty image escape sequence with text before it")
        func detectKittyWithTextBefore() {
            // Bug scenario: text + image data in same line
            let lineWithTextAndKittyImage = "Output: \u{001B}_Ga=T,f=100;data...\u{001B}\\\u{001B}_Gm=i=1;\u{001B}\\"
            #expect(isImageLine(lineWithTextAndKittyImage) == true)
        }

        @Test("should detect Kitty image escape sequence with padding")
        func detectKittyWithPadding() {
            // Kitty protocol adds padding to escape sequences
            let kittyWithPadding = "  \u{001B}_Ga=T,f=100...\u{001B}\\\u{001B}_Gm=i=1;\u{001B}\\  "
            #expect(isImageLine(kittyWithPadding) == true)
        }
    }

    // MARK: - Bug regression tests

    @Suite("Bug regression tests")
    struct BugRegressionTests {
        @Test("should detect image sequences in very long lines (304k+ chars)")
        func detectInVeryLongLines() {
            // This simulates the crash scenario: a line with 304,401 chars
            // containing image escape sequences somewhere
            let base64Char = String(repeating: "A", count: 100)  // 100 chars of base64-like data
            let imageSequence = "\u{001B}]1337;File=size=800,600;inline=1:"

            // Build a long line with image sequence
            let longLine =
                "Text prefix " +
                imageSequence +
                String(repeating: base64Char, count: 3000) +  // ~300,000 chars
                " suffix"

            #expect(longLine.count > 300000)
            #expect(isImageLine(longLine) == true)
        }

        @Test("should detect image sequences when terminal doesn't support images")
        func detectRegardlessOfSupport() {
            // The bug occurred when getImageEscapePrefix() returned null
            // isImageLine should still detect image sequences regardless
            let lineWithImage = "Read image file [image/jpeg]\u{001B}]1337;File=inline=1:base64data==\u{0007}"
            #expect(isImageLine(lineWithImage) == true)
        }

        @Test("should detect image sequences with ANSI codes before them")
        func detectWithAnsiBefore() {
            // Text might have ANSI styling before image data
            let lineWithAnsiAndImage = "\u{001B}[31mError output \u{001B}]1337;File=inline=1:image==\u{0007}"
            #expect(isImageLine(lineWithAnsiAndImage) == true)
        }

        @Test("should detect image sequences with ANSI codes after them")
        func detectWithAnsiAfter() {
            let lineWithImageAndAnsi = "\u{001B}_Ga=T,f=100:data...\u{001B}\\\u{001B}_Gm=i=1;\u{001B}\\\u{001B}[0m reset"
            #expect(isImageLine(lineWithImageAndAnsi) == true)
        }
    }

    // MARK: - Negative cases - lines without images

    @Suite("Negative cases - lines without images")
    struct NegativeTests {
        @Test("should not detect images in plain text lines")
        func noDetectPlainText() {
            let plainText = "This is just a regular text line without any escape sequences"
            #expect(isImageLine(plainText) == false)
        }

        @Test("should not detect images in lines with only ANSI codes")
        func noDetectOnlyAnsi() {
            let ansiText = "\u{001B}[31mRed text\u{001B}[0m and \u{001B}[32mgreen text\u{001B}[0m"
            #expect(isImageLine(ansiText) == false)
        }

        @Test("should not detect images in lines with cursor movement codes")
        func noDetectCursorCodes() {
            let cursorCodes = "\u{001B}[1A\u{001B}[2KLine cleared and moved up"
            #expect(isImageLine(cursorCodes) == false)
        }

        @Test("should not detect images in lines with partial iTerm2 sequences")
        func noDetectPartialITerm2() {
            // Similar prefix but missing the complete sequence
            let partialSequence = "Some text with ]1337;File but missing ESC at start"
            #expect(isImageLine(partialSequence) == false)
        }

        @Test("should not detect images in lines with partial Kitty sequences")
        func noDetectPartialKitty() {
            // Similar prefix but missing the complete sequence
            let partialSequence = "Some text with _G but missing ESC at start"
            #expect(isImageLine(partialSequence) == false)
        }

        @Test("should not detect images in empty lines")
        func noDetectEmptyLine() {
            #expect(isImageLine("") == false)
        }

        @Test("should not detect images in lines with newlines only")
        func noDetectNewlinesOnly() {
            #expect(isImageLine("\n") == false)
            #expect(isImageLine("\n\n") == false)
        }
    }

    // MARK: - Mixed content scenarios

    @Suite("Mixed content scenarios")
    struct MixedContentTests {
        @Test("should detect images when line has both Kitty and iTerm2 sequences")
        func detectBothProtocols() {
            let mixedLine = "Kitty: \u{001B}_Ga=T...\u{001B}\\\u{001B}_Gm=i=1;\u{001B}\\ iTerm2: \u{001B}]1337;File=inline=1:data==\u{0007}"
            #expect(isImageLine(mixedLine) == true)
        }

        @Test("should detect image in line with multiple text and image segments")
        func detectMultipleSegments() {
            let complexLine = "Start \u{001B}]1337;File=img1==\u{0007} middle \u{001B}]1337;File=img2==\u{0007} end"
            #expect(isImageLine(complexLine) == true)
        }

        @Test("should not falsely detect image in line with file path containing keywords")
        func noFalseDetectFilePath() {
            // File path might contain "1337" or "File" but without escape sequences
            let filePathLine = "/path/to/File_1337_backup/image.jpg"
            #expect(isImageLine(filePathLine) == false)
        }
    }
}
