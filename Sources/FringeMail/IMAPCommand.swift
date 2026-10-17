import Foundation

public enum IMAPCommandError: Error, Equatable, Sendable {
    /// The value cannot be sent as a quoted string (non-ASCII, a control character or a line break).
    case unquotable
}

/// Builds command lines without tag and CRLF. Values go out as quoted strings; anything a quoted
/// string cannot carry is refused rather than sent as a literal.
public enum IMAPCommand {
    public static func quoted(_ value: String) throws -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            guard scalar.isASCII, scalar.value >= 32, scalar.value != 127 else { throw IMAPCommandError.unquotable }
            if scalar == "\"" || scalar == "\\" { result.append("\\") }
            result.unicodeScalars.append(scalar)
        }
        return result + "\""
    }

    public static func login(user: String, password: String) throws -> String {
        "LOGIN \(try quoted(user)) \(try quoted(password))"
    }

    public static let capability = "CAPABILITY"
    /// Read-only selection: nothing in this session can change flags.
    public static let examineInbox = "EXAMINE INBOX"
    public static let idle = "IDLE"
    public static let done = "DONE"
    public static let logout = "LOGOUT"

    /// Default filter: the Primary category (the mailbox examined is INBOX).
    public static let primaryFilter = "category:primary"

    public static func searchUnseen(gmailQuery: String = primaryFilter) throws -> String {
        "UID SEARCH UNSEEN X-GM-RAW \(try quoted(gmailQuery))"
    }

    /// `BODY.PEEK` keeps the messages unread.
    public static func fetchHeaders(uids: [UInt32]) -> String {
        let set = uids.map(String.init).joined(separator: ",")
        return "UID FETCH \(set) (UID X-GM-MSGID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])"
    }
}
