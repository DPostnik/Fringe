import Foundation
import FringeCore

/// One unseen message as the tab lists it. Only headers are fetched; bodies never are.
public struct MailMessage: Identifiable, Equatable, Sendable {
    public var uid: UInt32
    public var gmailMessageID: UInt64?
    public var sender: String
    public var senderAddress: String
    public var subject: String
    public var date: Date?
    public var id: UInt32 { uid }

    public init(uid: UInt32, gmailMessageID: UInt64?, sender: String, senderAddress: String, subject: String, date: Date?) {
        self.uid = uid; self.gmailMessageID = gmailMessageID; self.sender = sender
        self.senderAddress = senderAddress; self.subject = subject; self.date = date
    }

    /// Builds a message from a FETCH response; a response without UID is unusable.
    public init?(fetch: IMAPFetch) {
        guard let uid = fetch.uid else { return nil }
        let fields = fetch.header.map(MailHeaderFields.init(header:))
        self.init(uid: uid, gmailMessageID: fetch.gmailMessageID,
                  sender: fields?.sender ?? "", senderAddress: fields?.senderAddress ?? "",
                  subject: fields?.subject ?? "",
                  date: fetch.internalDate.flatMap(MailDates.parseInternalDate) ?? fields?.date)
    }
}

/// The unseen list after one refresh.
public struct MailSnapshot: Equatable, Sendable {
    public var uidValidity: UInt32?
    /// Every unseen UID matching the filter; its count is the badge.
    public var unseen: [UInt32]
    /// The newest unseen messages, newest first.
    public var messages: [MailMessage]
    public init(uidValidity: UInt32?, unseen: [UInt32], messages: [MailMessage]) {
        self.uidValidity = uidValidity; self.unseen = unseen; self.messages = messages
    }

    public static let listLimit = 20

    /// The UIDs to fetch headers for: the highest (newest) ones.
    public static func newest(_ uids: [UInt32], limit: Int = listLimit) -> [UInt32] {
        Array(Set(uids).sorted(by: >).prefix(limit))
    }
}

/// Decides which messages are new since the previous list, to announce them.
public struct MailDiff: Sendable {
    private var uidValidity: UInt32?
    /// The highest UID seen so far; a message marked unread again is not "new".
    private var highWater: UInt32 = 0
    private var primed = false
    /// A burst after a long sleep announces only the newest few.
    public let announceLimit: Int

    public init(announceLimit: Int = 3) { self.announceLimit = announceLimit }

    /// Returns the messages to announce, newest first. The first list, and the first after the
    /// mailbox's UIDVALIDITY changes, announce nothing.
    public mutating func update(_ snapshot: MailSnapshot) -> [MailMessage] {
        let maxUID = snapshot.unseen.max() ?? 0
        guard primed, snapshot.uidValidity == uidValidity else {
            primed = true
            uidValidity = snapshot.uidValidity
            highWater = maxUID
            return []
        }
        let previous = highWater
        highWater = max(highWater, maxUID)
        return Array(snapshot.messages.filter { $0.uid > previous }.sorted { $0.uid > $1.uid }.prefix(announceLimit))
    }

    /// Forget the account (sign-out or another address).
    public mutating func reset() { self = MailDiff(announceLimit: announceLimit) }
}

/// Pauses between reconnect attempts: 2 s, 10 s, 1 min, then 5 min; reset after a success.
public struct ReconnectPolicy: Sendable {
    public static let delays: [Duration] = [.seconds(2), .seconds(10), .seconds(60), .seconds(300)]
    public private(set) var failures = 0
    public init() {}

    public mutating func nextDelay() -> Duration {
        defer { failures += 1 }
        return Self.delays[min(failures, Self.delays.count - 1)]
    }

    public mutating func reset() { failures = 0 }
}

/// How long one IDLE runs before it is renewed (Gmail ends idle connections after about 29 minutes).
public enum MailTiming {
    /// Also a safety net: Gmail does not always push a flag change (a message read elsewhere) during IDLE,
    /// so the unseen list is re-checked at least this often.
    public static let idleRenewal: Duration = .seconds(5 * 60)
    public static let commandTimeout: Duration = .seconds(60)
    public static let connectTimeout: Duration = .seconds(30)
}

/// Links into Gmail's web interface.
public enum MailLink {
    /// `X-GM-MSGID` in hex opens the message in any folder.
    public static func message(id: UInt64, account: String) -> URL? {
        URL(string: "https://mail.google.com/mail/?authuser=\(encode(account))#all/\(String(id, radix: 16))")
    }

    public static func inbox(account: String) -> URL? {
        URL(string: "https://mail.google.com/mail/?authuser=\(encode(account))#inbox")
    }

    private static func encode(_ account: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")
        return account.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

public enum MailBrowser: String, Codable, CaseIterable, Sendable {
    case systemDefault, chrome
    public static let chromeBundleID = "com.google.Chrome"
}

/// The tab's settings; the password is not here, it lives only in the Keychain.
public struct MailSettings: Codable, Equatable, Sendable {
    public var address = ""
    public var browser = MailBrowser.systemDefault

    public init(address: String = "", browser: MailBrowser = .systemDefault) {
        self.address = address; self.browser = browser
    }

    private enum CodingKeys: String, CodingKey { case address, browser }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        address = try container.decodeIfPresent(String.self, forKey: .address) ?? ""
        browser = (try? container.decodeIfPresent(MailBrowser.self, forKey: .browser)) ?? .systemDefault
    }

    public static let defaultsKey = "mailSettings"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    /// A plausible address: something@domain, no spaces, quotable.
    public static func isValidAddress(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
            && !value.contains(where: { $0.isWhitespace }) && (try? IMAPCommand.quoted(value)) != nil
    }

    /// Google shows app passwords in groups of four ("abcd efgh ijkl mnop"); the spaces are not part of it.
    public static func normalizedAppPassword(_ value: String) -> String {
        value.filter { !$0.isWhitespace }
    }
}

public enum MailError: Error, Equatable, Sendable {
    /// LOGIN was refused; retrying would not help until the credentials change.
    case authenticationFailed(String)
    case network(String)
    case timeout
    /// The server said something this client does not understand, or is not Gmail.
    case protocolError(String)
    /// A command failed (NO/BAD) or the server closed the session.
    case server(String)
    case keychain(OSStatus)
    case missingPassword
    case invalidCredentials

    public var isAuthentication: Bool {
        switch self {
        case .authenticationFailed, .missingPassword, .invalidCredentials, .keychain: true
        default: false
        }
    }

    public var message: String {
        switch self {
        case .authenticationFailed:
            L10n.text("Gmail не принял вход. Проверь адрес и пароль приложения в Настройках.",
                      "Gmail rejected the sign-in. Check the address and the app password in Settings.")
        case .network(let detail):
            L10n.text("Нет связи с Gmail: \(detail)", "Cannot reach Gmail: \(detail)")
        case .timeout:
            L10n.text("Gmail не отвечает.", "Gmail is not responding.")
        case .protocolError(let detail):
            L10n.text("Непонятный ответ сервера: \(detail)", "Unexpected server response: \(detail)")
        case .server(let detail):
            L10n.text("Ошибка Gmail: \(detail)", "Gmail error: \(detail)")
        case .keychain(let status):
            L10n.text("Связка ключей недоступна (код \(status)).", "The Keychain is unavailable (code \(status)).")
        case .missingPassword:
            L10n.text("Пароль приложения не найден в Связке ключей. Введи его в Настройках.",
                      "No app password in the Keychain. Enter it in Settings.")
        case .invalidCredentials:
            L10n.text("Адрес или пароль содержат недопустимые символы.", "The address or password has unsupported characters.")
        }
    }
}
