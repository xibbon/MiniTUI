import Foundation
import Testing
@testable import MiniTui

private func programStatusMessage(_ sequence: String) -> String? {
    guard let start = sequence.range(of: ":msg=")?.upperBound else { return nil }
    let encoded = sequence[start...].dropLast(2)
    guard let data = Data(base64Encoded: String(encoded)) else { return nil }
    return String(data: data, encoding: .utf8)
}

@Suite("OSC 7501 program status format")
struct ProgramStatusTests {
    @Test("Formats state, app, blocked kind, and a base64 message in order")
    func orderedFields() {
        #expect(formatProgramStatus(.init(state: .blocked, app: "pi", kind: .permission,
            message: "Allow bash?"))
            == "\u{1B}]7501;state=blocked:app=pi:kind=permission:msg=QWxsb3cgYmFzaD8=\u{1B}\\")
        #expect(formatProgramStatus(.init(state: .clear)) == "\u{1B}]7501;state=clear\u{1B}\\")
    }

    @Test("Omits kinds outside blocked, invalid app names, and empty messages")
    func omittedFields() {
        #expect(formatProgramStatus(.init(state: .working, app: "my app", kind: .auth, message: " \n "))
            == "\u{1B}]7501;state=working\u{1B}\\")
        #expect(formatProgramStatus(.init(state: .idle, app: String(repeating: "a", count: 32)))
            == "\u{1B}]7501;state=idle:app=\(String(repeating: "a", count: 32))\u{1B}\\")
        #expect(!formatProgramStatus(.init(state: .idle, app: String(repeating: "a", count: 33)))
            .contains("app="))
    }

    @Test("Replaces controls that cause terminals to discard status reports")
    func controls() {
        let sequence = formatProgramStatus(.init(state: .error,
            message: "first\nsecond\u{1B}[31m\u{9B}third\t"))
        #expect(programStatusMessage(sequence) == "first second [31m third")
    }

    @Test("Cuts long messages to 2048 UTF-8 bytes at a code point boundary")
    func accentedMessageLimit() {
        let sequence = formatProgramStatus(.init(state: .working, app: "pi",
            message: String(repeating: "é", count: 2_000)))
        let message = programStatusMessage(sequence)
        #expect(message == String(repeating: "é", count: 1_024))
        #expect(message?.count == 1_024)
        #expect(message?.utf8.count == 2_048)
        #expect(sequence.utf8.count <= 4_096)
    }

    @Test("Accepts query echoes with either terminator and future pairs")
    func replyRecognition() {
        #expect(programStatusQuery == "\u{1B}]7501;?\u{1B}\\")
        #expect(isProgramStatusReply(programStatusQuery))
        #expect(isProgramStatusReply("\u{1B}]7501;?\u{7}"))
        #expect(isProgramStatusReply("\u{1B}]7501;?version=2\u{1B}\\"))
        #expect(isProgramStatusReply("\u{1B}]7501;?version=2:feature=yes\u{7}"))
        #expect(isProgramStatusReply("\u{1B}]7501;?\u{301}version=2\u{7}"))
        #expect(!isProgramStatusReply("\u{1B}]7501;state=idle\u{1B}\\"))
        #expect(!isProgramStatusReply("\u{1B}]11;rgb:0000/0000/0000\u{7}"))
        #expect(!isProgramStatusReply("\u{1B}]7501;?"))
        #expect(!isProgramStatusReply("\u{1B}]7501;?bad\u{7}pair\u{1B}\\"))
        #expect(!isProgramStatusReply("\u{1B}]7501;?bad\u{1B}pair\u{7}"))
        #expect(!isProgramStatusReply(programStatusQuery + "extra"))
    }

    @Test("Accepts only app names with one to 32 allowed ASCII characters")
    func appNames() {
        for app in ["a", "Z9_.+-", String(repeating: "z", count: 32)] {
            #expect(formatProgramStatus(.init(state: .idle, app: app))
                == "\u{1B}]7501;state=idle:app=\(app)\u{1B}\\")
        }
        for app in ["", String(repeating: "a", count: 33), "my app", "pi/cli", "pi:cli", "pi=cli",
                    "é", "pi\n", "pi\r", "pi\r\n", "pi\ncli", "pi\u{0}"] {
            #expect(formatProgramStatus(.init(state: .idle, app: app)) == "\u{1B}]7501;state=idle\u{1B}\\")
        }
    }

    @Test("Writes all states and limits kinds to blocked reports")
    func statesAndKinds() {
        for state in ProgramStatus.State.allCases {
            #expect(formatProgramStatus(.init(state: state)) == "\u{1B}]7501;state=\(state.rawValue)\u{1B}\\")
            for kind in ProgramStatus.Kind.allCases {
                let kindPair = state == .blocked ? ":kind=\(kind.rawValue)" : ""
                #expect(formatProgramStatus(.init(state: state, kind: kind))
                    == "\u{1B}]7501;state=\(state.rawValue)\(kindPair)\u{1B}\\")
            }
        }
    }

    @Test("Replaces each run of C0, DEL, and C1 controls with one space")
    func controlRuns() {
        let controls = (0...0x1f).map { String(Unicode.Scalar($0)!) }.joined()
            + (0x7f...0x9f).map { String(Unicode.Scalar($0)!) }.joined()
        #expect(programStatusMessage(formatProgramStatus(.init(state: .error,
            message: controls + "first" + controls + "second" + controls))) == "first second")
        #expect(!formatProgramStatus(.init(state: .idle, message: controls)).contains("msg="))
    }

    @Test("Trims ECMAScript whitespace including FEFF and omits empty messages")
    func trimAndEmptyMessages() {
        let whitespace = "\t\n\u{B}\u{C}\r \u{A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}"
            + "\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}"
            + "\u{202F}\u{205F}\u{3000}\u{FEFF}"
        #expect(programStatusMessage(formatProgramStatus(.init(state: .idle,
            message: whitespace + "ready" + whitespace))) == "ready")
        for message in [nil, "", whitespace] as [String?] {
            #expect(formatProgramStatus(.init(state: .idle, message: message)) == "\u{1B}]7501;state=idle\u{1B}\\")
        }
        #expect(programStatusMessage(formatProgramStatus(.init(state: .idle,
            message: "\u{200B}ready\u{200B}"))) == "\u{200B}ready\u{200B}")
    }

    @Test("Truncates emoji by scalar and retains standard base64 padding")
    func emojiMessageLimit() {
        let message = String(repeating: "a", count: 2_045) + "😀tail"
        let sequence = formatProgramStatus(.init(state: .working, message: message))
        #expect(programStatusMessage(sequence) == String(repeating: "a", count: 2_045))
        #expect(programStatusMessage(sequence)?.utf8.count == 2_045)
        #expect(sequence.contains("=\u{1B}\\"))
        #expect(sequence.utf8.count <= 4_096)
        #expect(programStatusMessage(formatProgramStatus(.init(state: .working,
            message: String(repeating: "😀", count: 1_000)))) == String(repeating: "😀", count: 512))
    }

    @Test("Uses scalar boundaries even when the last grapheme has a combining mark")
    func combiningScalarBoundary() {
        let prefix = String(repeating: "a", count: 2_047)
        let sequence = formatProgramStatus(.init(state: .working, message: prefix + "e\u{301}tail"))
        #expect(programStatusMessage(sequence) == prefix + "e")
        #expect(programStatusMessage(sequence)?.unicodeScalars.count == 2_048)
        #expect(programStatusMessage(sequence)?.utf8.count == 2_048)
        #expect(sequence.utf8.count <= 4_096)
    }
}

@Suite("OSC 7501 program status negotiation")
struct ProgramStatusNegotiationTests {
    private let working = ProgramStatus(state: .working, app: "pi")
    private let report = "\u{1B}]7501;state=working:app=pi\u{1B}\\"
    private let clear = "\u{1B}]7501;state=clear\u{1B}\\"

    @Test("Reports the latest stored status after a reply before DA1")
    func replyBeforeDA1() {
        var negotiation = ProgramStatusNegotiation()
        #expect(negotiation.start(environmentValue: nil) == programStatusQuery)
        #expect(negotiation.queryPending)
        #expect(!negotiation.supported)
        #expect(negotiation.set(.init(state: .idle)) == "")
        #expect(negotiation.set(working) == "")
        #expect(negotiation.status == working)
        #expect(negotiation.receiveReply() == report)
        #expect(negotiation.supported)
        #expect(!negotiation.queryPending)
        #expect(negotiation.endQuery() == "")
        #expect(negotiation.set(.init(state: .done)) == "\u{1B}]7501;state=done\u{1B}\\")
    }

    @Test("DA1 before the reply ends support negotiation and ignores late replies")
    func DA1BeforeReply() {
        var negotiation = ProgramStatusNegotiation()
        #expect(negotiation.start(environmentValue: nil) == programStatusQuery)
        #expect(negotiation.endQuery() == "")
        #expect(!negotiation.queryPending)
        #expect(!negotiation.supported)
        #expect(negotiation.receiveReply() == "")
        #expect(negotiation.set(working) == "")
        #expect(!negotiation.supported)
    }

    @Test("Environment overrides skip the query; other values request support")
    func environmentOverrides() {
        var enabled = ProgramStatusNegotiation()
        #expect(enabled.set(working) == "")
        #expect(enabled.start(environmentValue: "1") == report)
        #expect(enabled.supported)
        #expect(!enabled.queryPending)
        #expect(enabled.set(working) == report)

        var disabled = ProgramStatusNegotiation()
        #expect(disabled.set(working) == "")
        #expect(disabled.start(environmentValue: "0") == "")
        #expect(!disabled.supported)
        #expect(!disabled.queryPending)
        #expect(disabled.receiveReply() == "")
        #expect(disabled.set(working) == "")
        for value in [nil, "", "true", " 1", "2"] as [String?] {
            var query = ProgramStatusNegotiation()
            #expect(query.start(environmentValue: value) == programStatusQuery)
            #expect(query.queryPending)
            #expect(!query.supported)
        }
    }

    @Test("A stale DA1 from before restart leaves the new query pending")
    func staleDA1AfterRestart() {
        var negotiation = ProgramStatusNegotiation()
        #expect(negotiation.start(environmentValue: nil) == programStatusQuery)
        #expect(negotiation.set(working) == "")
        #expect(negotiation.stop() == "")
        #expect(negotiation.start(environmentValue: nil) == programStatusQuery)
        #expect(negotiation.endQuery(isStale: true) == "")
        #expect(negotiation.queryPending)
        #expect(negotiation.receiveReply() == report)
        #expect(negotiation.endQuery() == "")
        #expect(negotiation.supported)
    }

    @Test("Stop clears the terminal status and restart waits for a new support reply")
    func clearOnStopAndReportAfterRestart() {
        var negotiation = ProgramStatusNegotiation()
        #expect(negotiation.start(environmentValue: nil) == programStatusQuery)
        #expect(negotiation.set(working) == "")
        #expect(negotiation.receiveReply() == report)
        #expect(negotiation.stop() == clear)
        #expect(!negotiation.supported)
        #expect(!negotiation.queryPending)
        #expect(negotiation.status == working)
        #expect(negotiation.set(working) == "")
        #expect(negotiation.receiveReply() == "")
        #expect(negotiation.start(environmentValue: nil) == programStatusQuery)
        #expect(!negotiation.supported)
        #expect(negotiation.receiveReply() == report)
    }

    @Test("Explicit clear removes the stored report and avoids another clear on stop")
    func explicitClear() {
        var negotiation = ProgramStatusNegotiation()
        #expect(negotiation.start(environmentValue: "1") == "")
        #expect(negotiation.set(working) == report)
        #expect(negotiation.set(.init(state: .clear)) == clear)
        #expect(negotiation.status == nil)
        #expect(negotiation.stop() == "")
        #expect(negotiation.start(environmentValue: nil) == programStatusQuery)
        #expect(negotiation.receiveReply() == "")
        #expect(negotiation.supported)
    }
}
