import Foundation

/// A malformed or unexpected server response. Responses are untrusted: anything that does not
/// parse is an error, never a guess.
public struct IMAPParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public var reason: String
    public init(_ reason: String) { self.reason = reason }
    public var description: String { "IMAP parse error: \(reason)" }
}

public enum IMAPStatus: String, Equatable, Sendable {
    case ok = "OK", no = "NO", bad = "BAD", bye = "BYE", preauth = "PREAUTH"
}

/// The attributes of one `* n FETCH (...)` response that the mail tab uses.
public struct IMAPFetch: Equatable, Sendable {
    public var sequence: Int
    public var uid: UInt32?
    public var gmailMessageID: UInt64?
    public var flags: [String]?
    /// The raw `INTERNALDATE` string, e.g. `17-Oct-2026 09:41:05 +0000`.
    public var internalDate: String?
    /// The bytes of `BODY[HEADER...]`; nil when absent or NIL.
    public var header: Data?
    public init(sequence: Int, uid: UInt32? = nil, gmailMessageID: UInt64? = nil, flags: [String]? = nil,
                internalDate: String? = nil, header: Data? = nil) {
        self.sequence = sequence; self.uid = uid; self.gmailMessageID = gmailMessageID
        self.flags = flags; self.internalDate = internalDate; self.header = header
    }
}

public enum IMAPResponse: Equatable, Sendable {
    /// `+ text`: the server waits for more of the command (IDLE started).
    case continuation(String)
    /// `tag OK|NO|BAD [code] text`.
    case tagged(tag: String, status: IMAPStatus, code: String?, text: String)
    /// `* OK|NO|BAD|BYE|PREAUTH [code] text`.
    case status(IMAPStatus, code: String?, text: String)
    case capability([String])
    case exists(Int)
    case expunge(Int)
    case recent(Int)
    case search([UInt32])
    case fetch(IMAPFetch)
    /// A well-formed untagged response the tab does not use (`FLAGS`, `LIST`, ...).
    case other(String)

    /// Mailbox changes that make the unseen list stale.
    public var changesMailbox: Bool {
        switch self {
        case .exists, .expunge, .fetch: true
        default: false
        }
    }
}

/// Splits the byte stream into complete responses: a line plus any `{n}` literals it announces.
public struct IMAPFramer: Sendable {
    /// Unseen-list responses are small; a larger one is a broken or hostile server.
    public static let maxResponseSize = 4 << 20
    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ data: Data) { buffer.append(contentsOf: data) }
    public mutating func append(_ bytes: [UInt8]) { buffer.append(contentsOf: bytes) }

    /// The next complete response without its final CRLF, or nil until more bytes arrive.
    public mutating func next() throws -> [UInt8]? {
        var segmentStart = 0
        while true {
            guard let lineEnd = Self.findCRLF(in: buffer, from: segmentStart) else { break }
            if let literal = try Self.literalLength(in: buffer, lineStart: segmentStart, lineEnd: lineEnd) {
                let literalEnd = lineEnd + 2 + literal
                guard literalEnd <= buffer.count else { break }
                segmentStart = literalEnd
                continue
            }
            let response = Array(buffer[0..<lineEnd])
            buffer.removeFirst(lineEnd + 2)
            return response
        }
        if buffer.count > Self.maxResponseSize { throw IMAPParseError("response exceeds \(Self.maxResponseSize) bytes") }
        return nil
    }

    static func findCRLF(in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + 1 < bytes.count {
            if bytes[index] == 13 && bytes[index + 1] == 10 { return index }
            index += 1
        }
        return nil
    }

    /// `{123}` or `{123+}` at the end of a line announces a literal of that many bytes.
    static func literalLength(in bytes: [UInt8], lineStart: Int, lineEnd: Int) throws -> Int? {
        guard lineEnd > lineStart, bytes[lineEnd - 1] == UInt8(ascii: "}") else { return nil }
        var index = lineEnd - 2
        if index >= lineStart, bytes[index] == UInt8(ascii: "+") { index -= 1 }
        let digitsEnd = index + 1
        while index >= lineStart, (48...57).contains(bytes[index]) { index -= 1 }
        guard index >= lineStart, bytes[index] == UInt8(ascii: "{"), digitsEnd > index + 1 else { return nil }
        guard digitsEnd - index - 1 <= 9 else { throw IMAPParseError("literal size too long") }
        let size = Int(String(decoding: bytes[(index + 1)..<digitsEnd], as: UTF8.self)) ?? 0
        guard size <= maxResponseSize else { throw IMAPParseError("literal of \(size) bytes") }
        return size
    }
}

/// A parsed IMAP value inside parentheses.
enum IMAPValue: Equatable {
    case atom(String)
    case string(Data)
    case list([IMAPValue])
    case nilValue

    var text: String? {
        switch self {
        case .atom(let value): value
        case .string(let data): String(decoding: data, as: UTF8.self)
        default: nil
        }
    }
}

public enum IMAPParser {
    /// Parses one framed response (see `IMAPFramer`).
    public static func parse(_ bytes: [UInt8]) throws -> IMAPResponse {
        var reader = Reader(bytes: bytes)
        if reader.consume("+") {
            reader.skipSpaces()
            return .continuation(reader.rest())
        }
        if reader.consume("*") {
            try reader.expectSpace()
            return try parseUntagged(&reader)
        }
        let tag = reader.readWhile { $0 != UInt8(ascii: " ") && $0 > 32 && $0 < 127 }
        guard !tag.isEmpty else { throw IMAPParseError("missing tag") }
        try reader.expectSpace()
        let word = reader.readWhile { $0 != UInt8(ascii: " ") }.uppercased()
        guard let status = IMAPStatus(rawValue: word), status == .ok || status == .no || status == .bad else {
            throw IMAPParseError("unknown tagged status \(word)")
        }
        let (code, text) = try parseResponseText(&reader)
        return .tagged(tag: tag, status: status, code: code, text: text)
    }

    private static func parseUntagged(_ reader: inout Reader) throws -> IMAPResponse {
        let first = reader.readWhile { $0 != UInt8(ascii: " ") }
        if let number = Int(first) {
            try reader.expectSpace()
            let keyword = reader.readWhile { $0 != UInt8(ascii: " ") }.uppercased()
            switch keyword {
            case "EXISTS": return .exists(number)
            case "EXPUNGE": return .expunge(number)
            case "RECENT": return .recent(number)
            case "FETCH":
                try reader.expectSpace()
                guard case .list(let items) = try reader.readValue() else { throw IMAPParseError("FETCH without a list") }
                return .fetch(try parseFetch(sequence: number, items: items))
            default: throw IMAPParseError("unknown numbered response \(keyword)")
            }
        }
        let keyword = first.uppercased()
        if let status = IMAPStatus(rawValue: keyword) {
            let (code, text) = try parseResponseText(&reader)
            return .status(status, code: code, text: text)
        }
        switch keyword {
        case "CAPABILITY":
            reader.skipSpaces()
            return .capability(reader.rest().split(separator: " ").map { $0.uppercased() })
        case "SEARCH":
            var uids: [UInt32] = []
            for part in reader.rest().split(separator: " ") {
                // CONDSTORE adds "(MODSEQ n)"; this client never enables it, so anything else is malformed.
                guard let uid = UInt32(part) else { throw IMAPParseError("bad SEARCH item") }
                uids.append(uid)
            }
            return .search(uids)
        default:
            guard keyword.allSatisfy({ $0.isLetter || $0 == "-" || $0.isNumber }), !keyword.isEmpty else {
                throw IMAPParseError("malformed untagged response")
            }
            return .other(keyword)
        }
    }

    /// ` [CODE args] human text` after a status word.
    private static func parseResponseText(_ reader: inout Reader) throws -> (String?, String) {
        reader.skipSpaces()
        var code: String?
        if reader.consume("[") {
            let value = reader.readWhile { $0 != UInt8(ascii: "]") }
            guard reader.consume("]") else { throw IMAPParseError("unterminated response code") }
            code = value
            reader.skipSpaces()
        }
        return (code, reader.rest())
    }

    private static func parseFetch(sequence: Int, items: [IMAPValue]) throws -> IMAPFetch {
        guard items.count.isMultiple(of: 2) else { throw IMAPParseError("odd FETCH item count") }
        var fetch = IMAPFetch(sequence: sequence)
        for index in stride(from: 0, to: items.count, by: 2) {
            guard case .atom(let rawKey) = items[index] else { throw IMAPParseError("FETCH key is not an atom") }
            let key = rawKey.uppercased(), value = items[index + 1]
            switch key {
            case "UID":
                guard case .atom(let text) = value, let uid = UInt32(text) else { throw IMAPParseError("bad UID") }
                fetch.uid = uid
            case "X-GM-MSGID":
                guard case .atom(let text) = value, let id = UInt64(text) else { throw IMAPParseError("bad X-GM-MSGID") }
                fetch.gmailMessageID = id
            case "FLAGS":
                guard case .list(let flags) = value else { throw IMAPParseError("bad FLAGS") }
                fetch.flags = try flags.map { flag in
                    guard case .atom(let name) = flag else { throw IMAPParseError("bad flag") }
                    return name
                }
            case "INTERNALDATE":
                guard case .string(let data) = value else { throw IMAPParseError("bad INTERNALDATE") }
                fetch.internalDate = String(decoding: data, as: UTF8.self)
            default:
                if key.hasPrefix("BODY[HEADER") {
                    switch value {
                    case .string(let data): fetch.header = data
                    case .nilValue: fetch.header = nil
                    default: throw IMAPParseError("bad header section")
                    }
                }
                // Other attributes (X-GM-THRID, RFC822.SIZE, ...) are well-formed but unused.
            }
        }
        return fetch
    }
}

/// A cursor over one response's bytes.
struct Reader {
    let bytes: [UInt8]
    var index = 0

    var atEnd: Bool { index >= bytes.count }
    var peek: UInt8? { atEnd ? nil : bytes[index] }

    mutating func consume(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue, peek == ascii else { return false }
        index += 1
        return true
    }

    mutating func expectSpace() throws {
        guard consume(" ") else { throw IMAPParseError("expected a space at byte \(index)") }
    }

    mutating func skipSpaces() { while peek == UInt8(ascii: " ") { index += 1 } }

    mutating func readWhile(_ predicate: (UInt8) -> Bool) -> String {
        let start = index
        while let byte = peek, predicate(byte) { index += 1 }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    mutating func rest() -> String {
        defer { index = bytes.count }
        return String(decoding: bytes[min(index, bytes.count)...], as: UTF8.self)
    }

    mutating func readValue() throws -> IMAPValue {
        guard let byte = peek else { throw IMAPParseError("unexpected end of response") }
        switch byte {
        case UInt8(ascii: "("):
            index += 1
            var items: [IMAPValue] = []
            while true {
                skipSpaces()
                guard let next = peek else { throw IMAPParseError("unterminated list") }
                if next == UInt8(ascii: ")") { index += 1; return .list(items) }
                items.append(try readValue())
            }
        case UInt8(ascii: "\""):
            index += 1
            var data = Data()
            while true {
                guard let next = peek else { throw IMAPParseError("unterminated quoted string") }
                index += 1
                if next == UInt8(ascii: "\"") { return .string(data) }
                if next == UInt8(ascii: "\\") {
                    guard let escaped = peek, escaped == UInt8(ascii: "\\") || escaped == UInt8(ascii: "\"") else {
                        throw IMAPParseError("bad escape in quoted string")
                    }
                    index += 1
                    data.append(escaped)
                } else if next == 13 || next == 10 {
                    throw IMAPParseError("line break in quoted string")
                } else {
                    data.append(next)
                }
            }
        case UInt8(ascii: "{"):
            index += 1
            let digits = readWhile { (48...57).contains($0) }
            _ = consume("+")
            guard consume("}"), consume("\r"), consume("\n"), let size = Int(digits), digits.count <= 9 else {
                throw IMAPParseError("bad literal")
            }
            guard index + size <= bytes.count else { throw IMAPParseError("truncated literal") }
            defer { index += size }
            return .string(Data(bytes[index..<(index + size)]))
        case UInt8(ascii: ")"):
            throw IMAPParseError("unexpected )")
        default:
            let atom = try readAtom()
            return atom.uppercased() == "NIL" ? .nilValue : .atom(atom)
        }
    }

    /// An atom; a `[...]` section (with spaces and parentheses inside) and a `<n>` origin are part of it,
    /// as in `BODY[HEADER.FIELDS (FROM SUBJECT)]<0>`.
    mutating func readAtom() throws -> String {
        let start = index
        while let byte = peek {
            if byte == UInt8(ascii: "[") {
                index += 1
                while let inner = peek, inner != UInt8(ascii: "]") {
                    guard inner != 13, inner != 10 else { throw IMAPParseError("line break in section") }
                    index += 1
                }
                guard consume("]") else { throw IMAPParseError("unterminated section") }
                continue
            }
            if byte <= 32 || byte >= 127 || byte == UInt8(ascii: "(") || byte == UInt8(ascii: ")")
                || byte == UInt8(ascii: "{") || byte == UInt8(ascii: "\"") { break }
            index += 1
        }
        guard index > start else { throw IMAPParseError("empty atom at byte \(start)") }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }
}
