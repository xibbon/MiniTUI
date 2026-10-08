import Foundation

/// The root status record for OSC 7501.
public struct ProgramStatus: Sendable, Equatable {
    public enum State: String, Sendable, CaseIterable {
        case idle, working, blocked, done, error, clear
    }

    public enum Kind: String, Sendable, CaseIterable {
        case permission, question, auth
    }

    public var state: State
    public var app: String?
    public var kind: Kind?
    public var message: String?

    public init(state: State, app: String? = nil, kind: Kind? = nil, message: String? = nil) {
        self.state = state
        self.app = app
        self.kind = kind
        self.message = message
    }
}

/// Query the terminal for OSC 7501 support.
public let programStatusQuery = "\u{001B}]7501;?\u{001B}\\"

/// Return true for a support reply with BEL or ST as its terminator.
public func isProgramStatusReply(_ sequence: String) -> Bool {
    let bytes = sequence.utf8
    guard bytes.starts(with: "\u{001B}]7501;?".utf8) else { return false }
    let terminatorBytes: Int
    if bytes.last == 7 {
        terminatorBytes = 1
    } else if bytes.suffix(2).elementsEqual("\u{001B}\\".utf8) {
        terminatorBytes = 2
    } else {
        return false
    }
    return !bytes.dropFirst(8).dropLast(terminatorBytes).contains { $0 == 7 || $0 == 27 }
}

/// Encode a status. Replace controls and limit the decoded message to 2048 bytes.
public func formatProgramStatus(_ status: ProgramStatus) -> String {
    var pairs = ["state=\(status.state.rawValue)"]
    if let app = status.app, (1...32).contains(app.utf8.count),
       app.utf8.allSatisfy({ byte in
           (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte)
               || [95, 46, 43, 45].contains(byte)
       }) {
        pairs.append("app=\(app)")
    }
    if status.state == .blocked, let kind = status.kind {
        pairs.append("kind=\(kind.rawValue)")
    }
    var clean = String.UnicodeScalarView()
    var inControls = false
    for scalar in (status.message ?? "").unicodeScalars {
        let control = scalar.value <= 0x1f || (0x7f...0x9f).contains(scalar.value)
        if control {
            if !inControls { clean.append(" ") }
        } else {
            clean.append(scalar)
        }
        inControls = control
    }
    // Use ECMAScript trim characters, including the byte order mark.
    let trim = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D} \u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
    let trimmed = String(clean).trimmingCharacters(in: trim)
    var message = String.UnicodeScalarView()
    var byteCount = 0
    for scalar in trimmed.unicodeScalars {
        let size = scalar.utf8.count
        guard byteCount + size <= 2048 else { break }
        message.append(scalar)
        byteCount += size
    }
    if !message.isEmpty {
        pairs.append("msg=\(Data(String(message).utf8).base64EncodedString())")
    }
    return "\u{001B}]7501;\(pairs.joined(separator: ":"))\u{001B}\\"
}

/// TUI owns the DA1 queue and supplies the end of each support query.
struct ProgramStatusNegotiation {
    private(set) var status: ProgramStatus?
    private(set) var supported = false
    private(set) var queryPending = false

    mutating func start(environmentValue: String?) -> String {
        supported = environmentValue == "1"
        queryPending = environmentValue != "1" && environmentValue != "0"
        return queryPending ? programStatusQuery : report()
    }

    mutating func receiveReply() -> String {
        guard queryPending else { return "" }
        queryPending = false
        supported = true
        return report()
    }

    mutating func endQuery(isStale: Bool = false) -> String {
        if !isStale { queryPending = false }
        return ""
    }

    mutating func set(_ status: ProgramStatus) -> String {
        self.status = status.state == .clear ? nil : status
        return supported ? formatProgramStatus(status) : ""
    }

    mutating func stop() -> String {
        let bytes = supported && status != nil ? formatProgramStatus(ProgramStatus(state: .clear)) : ""
        supported = false
        queryPending = false
        return bytes
    }

    private func report() -> String {
        guard supported, let status else { return "" }
        return formatProgramStatus(status)
    }
}
