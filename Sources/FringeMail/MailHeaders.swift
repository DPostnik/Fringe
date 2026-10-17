import Foundation

/// RFC 2047 encoded-words (`=?charset?B|Q?text?=`) in header values.
public enum EncodedWords {
    private enum Segment {
        case text(String)
        case word(charset: String, bytes: Data, raw: String)
    }

    /// Decodes every encoded-word; whitespace between adjacent words is dropped and adjacent words in
    /// one charset are joined before decoding, so a character split across words survives.
    /// A word that does not decode stays as written.
    public static func decode(_ value: String) -> String {
        let pattern = #/=\?([^?\s]+)\?([QqBb])\?([^?\s]*)\?=/#
        var segments: [Segment] = []
        var cursor = value.startIndex
        for match in value.matches(of: pattern) {
            if cursor < match.range.lowerBound { segments.append(.text(String(value[cursor..<match.range.lowerBound]))) }
            let raw = String(value[match.range])
            let charset = String(match.output.1).split(separator: "*").first.map(String.init) ?? ""
            let isBase64 = match.output.2.uppercased() == "B"
            if let bytes = isBase64 ? base64(String(match.output.3)) : quotedPrintable(String(match.output.3)) {
                segments.append(.word(charset: charset.lowercased(), bytes: bytes, raw: raw))
            } else {
                segments.append(.text(raw))
            }
            cursor = match.range.upperBound
        }
        if cursor < value.endIndex { segments.append(.text(String(value[cursor...]))) }

        // Drop linear whitespace between two encoded-words, then merge same-charset neighbours.
        var merged: [Segment] = []
        for (index, segment) in segments.enumerated() {
            if case .text(let text) = segment, text.allSatisfy(\.isWhitespace),
               index > 0, index + 1 < segments.count,
               case .word = segments[index - 1], case .word = segments[index + 1] {
                continue
            }
            if case .word(let charset, let bytes, let raw) = segment, case .word(let lastCharset, let lastBytes, let lastRaw)? = merged.last,
               lastCharset == charset {
                merged[merged.count - 1] = .word(charset: charset, bytes: lastBytes + bytes, raw: lastRaw + raw)
                continue
            }
            merged.append(segment)
        }

        return merged.map { segment in
            switch segment {
            case .text(let text): text
            case .word(let charset, let bytes, let raw): string(from: bytes, charset: charset) ?? raw
            }
        }.joined()
    }

    static func string(from bytes: Data, charset: String) -> String? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
        return String(data: bytes, encoding: encoding)
    }

    static func base64(_ text: String) -> Data? {
        var padded = text
        while padded.count % 4 != 0 { padded += "=" }
        return Data(base64Encoded: padded)
    }

    /// The "Q" encoding: `_` is a space, `=XX` a byte.
    static func quotedPrintable(_ text: String) -> Data? {
        var data = Data()
        var bytes = Array(text.utf8)[...]
        while let byte = bytes.popFirst() {
            switch byte {
            case UInt8(ascii: "_"): data.append(0x20)
            case UInt8(ascii: "="):
                guard bytes.count >= 2, let value = UInt8(String(decoding: bytes.prefix(2), as: UTF8.self), radix: 16) else { return nil }
                data.append(value)
                bytes.removeFirst(2)
            default: data.append(byte)
            }
        }
        return data
    }
}

/// The From, Subject and Date fields of a fetched header block.
public struct MailHeaderFields: Equatable, Sendable {
    public var senderName: String
    public var senderAddress: String
    public var subject: String
    public var date: Date?

    /// The sender as the list shows it: the display name, else the address.
    public var sender: String { senderName.isEmpty ? senderAddress : senderName }

    public init(senderName: String, senderAddress: String, subject: String, date: Date?) {
        self.senderName = senderName; self.senderAddress = senderAddress; self.subject = subject; self.date = date
    }

    public init(header: Data) {
        let fields = Self.fields(header)
        let (name, address) = Self.parseAddress(fields["from"] ?? "")
        senderName = name
        senderAddress = address
        subject = Self.clean(EncodedWords.decode(fields["subject"] ?? ""))
        date = fields["date"].flatMap(MailDates.parseHeaderDate)
    }

    /// Unfolds and splits the block; field names are lowercased, the first occurrence wins.
    static func fields(_ header: Data) -> [String: String] {
        // Raw 8-bit headers are nearly always UTF-8; Latin-1 keeps any other bytes visible instead of dropping them.
        let text = String(data: header, encoding: .utf8) ?? String(data: header, encoding: .isoLatin1) ?? ""
        let unfolded = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n ", with: " ")
            .replacingOccurrences(of: "\n\t", with: " ")
        var result: [String: String] = [:]
        for line in unfolded.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty, result[name] == nil else { continue }
            result[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// `"Name" <a@b>`, `Name <a@b>`, `a@b (Name)` or `a@b`; the name has its encoded-words decoded.
    static func parseAddress(_ raw: String) -> (name: String, address: String) {
        var name = "", address = raw.trimmingCharacters(in: .whitespaces)
        if let open = raw.lastIndex(of: "<"), let close = raw[open...].firstIndex(of: ">") {
            address = String(raw[raw.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            name = String(raw[..<open])
        } else if let open = raw.firstIndex(of: "("), let close = raw.lastIndex(of: ")"), open < close {
            address = raw[..<open].trimmingCharacters(in: .whitespaces)
            name = String(raw[raw.index(after: open)..<close])
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.count >= 2, name.hasPrefix("\""), name.hasSuffix("\"") {
            var unquoted = "", escaping = false
            for character in name.dropFirst().dropLast() {
                if escaping || character != "\\" { unquoted.append(character); escaping = false } else { escaping = true }
            }
            name = unquoted
        }
        return (clean(EncodedWords.decode(name)), address)
    }

    /// Collapses whitespace, line breaks and tabs into single spaces.
    static func clean(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

public enum MailDates {
    /// `17-Oct-2026 09:41:05 +0000` (the day may be space-padded).
    public static func parseInternalDate(_ value: String) -> Date? {
        formatter("d-MMM-yyyy HH:mm:ss Z").date(from: value.trimmingCharacters(in: .whitespaces))
    }

    /// RFC 5322 dates, with or without the weekday and seconds; a trailing `(UTC)` comment is ignored.
    public static func parseHeaderDate(_ value: String) -> Date? {
        var text = value
        if let comment = text.firstIndex(of: "(") { text = String(text[..<comment]) }
        text = MailHeaderFields.clean(text)
        for format in ["EEE, d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm Z", "d MMM yyyy HH:mm Z"] {
            if let date = formatter(format).date(from: text) { return date }
        }
        return nil
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter
    }
}
