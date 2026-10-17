import Foundation
import Testing
import FringeCore
@testable import FringeMail

@MainActor @Test func moduleOwnsItsTab() {
    #expect(MailModule().tab == .mail)
}

// MARK: Fixtures

private func bytes(_ text: String) -> [UInt8] { Array(text.utf8) }

private func parse(_ text: String) throws -> IMAPResponse { try IMAPParser.parse(bytes(text)) }

/// A Gmail-style FETCH response with the header block as a literal of the right length.
private func fetchResponse(sequence: Int, uid: UInt32, msgID: UInt64, flags: String = "", date: String, header: String) -> String {
    "* \(sequence) FETCH (X-GM-MSGID \(msgID) UID \(uid) FLAGS (\(flags)) INTERNALDATE \"\(date)\" "
        + "BODY[HEADER.FIELDS (FROM SUBJECT DATE)] {\(header.utf8.count)}\r\n\(header))"
}

private let annaHeader = "From: =?UTF-8?B?0JDQvdC90LAg0J/QtdGC0YDQvtCy0LA=?= <anna@example.com>\r\n"
    + "Subject: =?UTF-8?B?0JLRgdGC0Q==?=\r\n =?UTF-8?B?gNC10YfQsCDQsiDQv9GP0YLQvdC40YbRgw==?=\r\n"
    + "Date: Fri, 16 Oct 2026 23:41:05 -0700 (PDT)\r\n\r\n"

// MARK: Framing

@Test func framerSplitsResponsesAndWaitsForLiterals() throws {
    var framer = IMAPFramer()
    let fetch = fetchResponse(sequence: 7, uid: 4521, msgID: 1812345678901234567, date: "17-Oct-2026 06:41:05 +0000", header: annaHeader)
    let stream = bytes("* 12 EXISTS\r\n" + fetch + "\r\nF004 OK Success\r\n")
    // Deliver in small chunks, cutting through the literal and through CRLFs.
    var responses: [[UInt8]] = []
    for chunk in stride(from: 0, to: stream.count, by: 7).map({ Array(stream[$0..<min($0 + 7, stream.count)]) }) {
        framer.append(chunk)
        while let response = try framer.next() { responses.append(response) }
    }
    #expect(responses.count == 3)
    #expect(responses.first == bytes("* 12 EXISTS"))
    #expect(responses.last == bytes("F004 OK Success"))
    #expect(responses[1] == bytes(fetch))
}

@Test func framerRejectsOversizedLiteral() {
    var framer = IMAPFramer()
    framer.append(bytes("* 1 FETCH (BODY[] {999999999}\r\n"))
    #expect(throws: IMAPParseError.self) { try framer.next() }
}

// MARK: Parsing

@Test func parsesGreetingCapabilityAndTaggedResults() throws {
    #expect(try parse("* OK Gimap ready for requests from 2a02:a31a::1 988c60f3423e3") == .status(.ok, code: nil, text: "Gimap ready for requests from 2a02:a31a::1 988c60f3423e3"))
    let capability = try parse("* CAPABILITY IMAP4rev1 UNSELECT IDLE NAMESPACE QUOTA ID XLIST CHILDREN X-GM-EXT-1 XYZZY SASL-IR AUTH=XOAUTH2 AUTH=PLAIN AUTH=PLAIN-CLIENTTOKEN AUTH=OAUTHBEARER")
    guard case .capability(let list) = capability else { Issue.record("not a capability"); return }
    #expect(list.contains("IDLE") && list.contains("X-GM-EXT-1"))
    #expect(try parse("F002 OK Thats all she wrote! 988c60f3423e3") == .tagged(tag: "F002", status: .ok, code: nil, text: "Thats all she wrote! 988c60f3423e3"))
    #expect(try parse("F003 NO [AUTHENTICATIONFAILED] Invalid credentials (Failure)") == .tagged(tag: "F003", status: .no, code: "AUTHENTICATIONFAILED", text: "Invalid credentials (Failure)"))
    #expect(try parse("F009 BAD Could not parse command") == .tagged(tag: "F009", status: .bad, code: nil, text: "Could not parse command"))
    #expect(try parse("* OK [UIDVALIDITY 1] UIDs valid.") == .status(.ok, code: "UIDVALIDITY 1", text: "UIDs valid."))
    #expect(try parse("* BYE System error") == .status(.bye, code: nil, text: "System error"))
    #expect(try parse("+ idling") == .continuation("idling"))
    #expect(try parse("* FLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen $NotPhishing $Phishing)") == .other("FLAGS"))
}

@Test func parsesMailboxUpdates() throws {
    #expect(try parse("* 3021 EXISTS") == .exists(3021))
    #expect(try parse("* 17 EXPUNGE") == .expunge(17))
    #expect(try parse("* 0 RECENT") == .recent(0))
    #expect(try parse("* SEARCH 4519 4520 4521") == .search([4519, 4520, 4521]))
    #expect(try parse("* SEARCH") == .search([]))
    #expect(try parse("* 3021 EXISTS").changesMailbox)
    #expect(try parse("* 12 FETCH (UID 4500 FLAGS (\\Seen))").changesMailbox)
    #expect(try parse("* 0 RECENT").changesMailbox == false)
}

@Test func parsesGmailFetchWithLiteral() throws {
    let text = fetchResponse(sequence: 7, uid: 4521, msgID: 1812345678901234567, flags: "\\Recent $NotPhishing",
                             date: " 7-Oct-2026 06:41:05 +0000", header: annaHeader)
    guard case .fetch(let fetch) = try parse(text) else { Issue.record("not a fetch"); return }
    #expect(fetch.sequence == 7)
    #expect(fetch.uid == 4521)
    #expect(fetch.gmailMessageID == 1812345678901234567)
    #expect(fetch.flags == ["\\Recent", "$NotPhishing"])
    #expect(fetch.internalDate == " 7-Oct-2026 06:41:05 +0000")
    #expect(fetch.header == Data(annaHeader.utf8))
}

@Test func fetchIgnoresUnusedAttributesAndAcceptsNilHeader() throws {
    let text = "* 2 FETCH (X-GM-THRID 1812345678901234000 X-GM-LABELS (\"\\\\Inbox\" \"\\\\Important\") UID 88 RFC822.SIZE 5120 BODY[HEADER.FIELDS (FROM SUBJECT DATE)]<0> NIL)"
    guard case .fetch(let fetch) = try parse(text) else { Issue.record("not a fetch"); return }
    #expect(fetch.uid == 88)
    #expect(fetch.header == nil)
    #expect(fetch.gmailMessageID == nil)
}

@Test func malformedResponsesFailClosed() {
    for text in ["* 3 FETCH (UID abc)", "* 3 FETCH UID 1", "* 3 FETCH (UID 1", "* 3 FETCH (UID)",
                 "* 3 FETCH (INTERNALDATE \"17-Oct-2026)", "* SEARCH 1 x", "* 3 WHATEVER", "F001 MAYBE fine",
                 "* 3 FETCH (BODY[HEADER] {40}\r\nshort)", "* OK [UNTERMINATED code", ""] {
        #expect(throws: IMAPParseError.self, "\(text)") { try parse(text) }
    }
}

// MARK: Commands

@Test func commandsQuoteAndRefuseUnsafeValues() throws {
    #expect(try IMAPCommand.quoted("plain") == "\"plain\"")
    #expect(try IMAPCommand.quoted("a\"b\\c") == "\"a\\\"b\\\\c\"")
    #expect(try IMAPCommand.login(user: "daniil@gmail.com", password: "abcdefghijklmnop") == "LOGIN \"daniil@gmail.com\" \"abcdefghijklmnop\"")
    #expect(throws: IMAPCommandError.unquotable) { try IMAPCommand.quoted("pass\r\nF002 LOGOUT") }
    #expect(throws: IMAPCommandError.unquotable) { try IMAPCommand.quoted("пароль") }
    #expect(throws: IMAPCommandError.unquotable) { try IMAPCommand.quoted("tab\there") }
    #expect(try IMAPCommand.searchUnseen() == "UID SEARCH UNSEEN X-GM-RAW \"category:primary\"")
    #expect(IMAPCommand.fetchHeaders(uids: [4521, 4520]) == "UID FETCH 4521,4520 (UID X-GM-MSGID FLAGS INTERNALDATE BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])")
    #expect(IMAPCommand.examineInbox == "EXAMINE INBOX")
}

// MARK: Headers

@Test func decodesEncodedWords() {
    #expect(EncodedWords.decode("=?UTF-8?B?0JDQvdC90LAg0J/QtdGC0YDQvtCy0LA=?=") == "Анна Петрова")
    #expect(EncodedWords.decode("=?windows-1251?B?0fe48iDn4CDu6vL/4fD8?=") == "Счёт за октябрь")
    #expect(EncodedWords.decode("=?koi8-r?q?=F0=D2=C9=D7=C5=D4_=C9=DA_KOI8?=") == "Привет из KOI8")
    // A character split across two words, separated by folding whitespace.
    #expect(EncodedWords.decode("=?UTF-8?B?0JLRgdGC0Q==?=\r\n =?UTF-8?B?gNC10YfQsCDQsiDQv9GP0YLQvdC40YbRgw==?=") == "Встреча в пятницу")
    #expect(EncodedWords.decode("Re: =?UTF-8?Q?caf=C3=A9?= tomorrow") == "Re: café tomorrow")
    #expect(EncodedWords.decode("=?utf-8*en?Q?Hello_there?=") == "Hello there")
    #expect(EncodedWords.decode("=?x-unknown?Q?abc?= ok") == "=?x-unknown?Q?abc?= ok")
    #expect(EncodedWords.decode("=?UTF-8?Q?bad=Z?=") == "=?UTF-8?Q?bad=Z?=")
    #expect(EncodedWords.decode("Plain subject") == "Plain subject")
}

@Test func parsesHeaderBlock() {
    let fields = MailHeaderFields(header: Data(annaHeader.utf8))
    #expect(fields.senderName == "Анна Петрова")
    #expect(fields.senderAddress == "anna@example.com")
    #expect(fields.sender == "Анна Петрова")
    #expect(fields.subject == "Встреча в пятницу")
    #expect(fields.date == Date(timeIntervalSince1970: 1_792_219_265))
}

@Test func parsesSenderForms() {
    #expect(MailHeaderFields.parseAddress("\"GitHub \\\"Bot\\\"\" <noreply@github.com>") == ("GitHub \"Bot\"", "noreply@github.com"))
    #expect(MailHeaderFields.parseAddress("\"=?UTF-8?B?0JDQvdC90LA=?=\" <anna@example.com>") == ("Анна", "anna@example.com"))
    #expect(MailHeaderFields.parseAddress("Google <no-reply@accounts.google.com>") == ("Google", "no-reply@accounts.google.com"))
    #expect(MailHeaderFields.parseAddress("bob@example.com") == ("", "bob@example.com"))
    #expect(MailHeaderFields.parseAddress("bob@example.com (Bob Smith)") == ("Bob Smith", "bob@example.com"))
    let bare = MailHeaderFields(header: Data("From: bob@example.com\r\nSubject:\r\n\r\n".utf8))
    #expect(bare.sender == "bob@example.com")
    #expect(bare.subject == "")
}

@Test func parsesDates() {
    #expect(MailDates.parseInternalDate("17-Oct-2026 06:41:05 +0000") == Date(timeIntervalSince1970: 1_792_219_265))
    #expect(MailDates.parseInternalDate(" 7-Oct-2026 06:41:05 +0300") == Date(timeIntervalSince1970: 1_791_344_465))
    #expect(MailDates.parseHeaderDate("17 Oct 2026 06:41 +0000") == Date(timeIntervalSince1970: 1_792_219_260))
    #expect(MailDates.parseInternalDate("yesterday") == nil)
}

@Test func buildsMessageFromFetch() throws {
    let text = fetchResponse(sequence: 7, uid: 4521, msgID: 1812345678901234567, date: "17-Oct-2026 06:41:05 +0000", header: annaHeader)
    guard case .fetch(let fetch) = try parse(text) else { Issue.record("not a fetch"); return }
    let message = try #require(MailMessage(fetch: fetch))
    #expect(message == MailMessage(uid: 4521, gmailMessageID: 1812345678901234567, sender: "Анна Петрова",
                                   senderAddress: "anna@example.com", subject: "Встреча в пятницу",
                                   date: Date(timeIntervalSince1970: 1_792_219_265)))
    #expect(MailMessage(fetch: IMAPFetch(sequence: 1)) == nil)
}

// MARK: Links, policy, diff, settings

@Test func buildsGmailLinks() {
    #expect(MailLink.message(id: 1812345678901234567, account: "daniil@gmail.com")?.absoluteString
            == "https://mail.google.com/mail/?authuser=daniil@gmail.com#all/1926becaf11f4b87")
    #expect(MailLink.message(id: 255, account: "a+b@gmail.com")?.absoluteString
            == "https://mail.google.com/mail/?authuser=a%2Bb@gmail.com#all/ff")
    #expect(MailLink.inbox(account: "daniil@gmail.com")?.absoluteString == "https://mail.google.com/mail/?authuser=daniil@gmail.com#inbox")
}

@Test func reconnectBackoffCapsAndResets() {
    var policy = ReconnectPolicy()
    var delays: [Duration] = []
    for _ in 0..<6 { delays.append(policy.nextDelay()) }
    #expect(delays == [.seconds(2), .seconds(10), .seconds(60), .seconds(300), .seconds(300), .seconds(300)])
    policy.reset()
    let afterReset = policy.nextDelay()
    #expect(afterReset == .seconds(2))
}

private func message(_ uid: UInt32) -> MailMessage {
    MailMessage(uid: uid, gmailMessageID: UInt64(uid) * 1000, sender: "S\(uid)", senderAddress: "s\(uid)@x.com", subject: "T\(uid)", date: nil)
}

private func snapshot(_ uids: [UInt32], validity: UInt32 = 1) -> MailSnapshot {
    MailSnapshot(uidValidity: validity, unseen: uids, messages: MailSnapshot.newest(uids).map(message))
}

@Test func diffAnnouncesOnlyNewMessages() {
    var diff = MailDiff()
    let first = diff.update(snapshot([10, 11, 12]))
    #expect(first.isEmpty)
    let unchanged = diff.update(snapshot([10, 11, 12]))
    #expect(unchanged.isEmpty)
    let arrived = diff.update(snapshot([10, 11, 12, 13]))
    #expect(arrived.map(\.uid) == [13])
    // 12 was read, then 11 marked unread again: neither is new.
    let read = diff.update(snapshot([10, 11]))
    #expect(read.isEmpty)
    let markedUnread = diff.update(snapshot([10, 11, 12]))
    #expect(markedUnread.isEmpty)
    // A burst after sleep announces the newest three only.
    let burst = diff.update(snapshot([10, 14, 15, 16, 17, 18]))
    #expect(burst.map(\.uid) == [18, 17, 16])
    // Everything read, then a new message.
    _ = diff.update(snapshot([]))
    let afterEmpty = diff.update(snapshot([19]))
    #expect(afterEmpty.map(\.uid) == [19])
    // A new UIDVALIDITY starts over silently.
    let reset = diff.update(snapshot([3, 4], validity: 2))
    #expect(reset.isEmpty)
}

@Test func newestPicksHighestTwentyUIDs() {
    let uids = Array(UInt32(1)...45).shuffled()
    #expect(MailSnapshot.newest(uids) == Array((26...45).reversed()))
    #expect(MailSnapshot.newest([5, 5, 3]) == [5, 3])
}

@Test func settingsDecodeOldValuesAndNormalizeInput() throws {
    let decoded = try JSONDecoder().decode(MailSettings.self, from: Data(#"{"address":"daniil@gmail.com"}"#.utf8))
    #expect(decoded == MailSettings(address: "daniil@gmail.com", browser: .systemDefault))
    let unknownBrowser = try JSONDecoder().decode(MailSettings.self, from: Data(#"{"browser":"lynx"}"#.utf8))
    #expect(unknownBrowser == MailSettings())
    #expect(MailSettings.normalizedAppPassword("abcd efgh ijkl mnop") == "abcdefghijklmnop")
    #expect(MailSettings.isValidAddress("daniil@gmail.com"))
    #expect(!MailSettings.isValidAddress("daniil"))
    #expect(!MailSettings.isValidAddress("dan iil@gmail.com"))
    #expect(!MailSettings.isValidAddress("даниил@gmail.com"))
}

@Test func authenticationErrorsDoNotRetry() {
    #expect(MailError.authenticationFailed("Invalid credentials").isAuthentication)
    #expect(MailError.missingPassword.isAuthentication)
    #expect(!MailError.timeout.isAuthentication)
    #expect(!MailError.network("offline").isAuthentication)
}
