import Foundation
import Testing
@testable import FringeProtocol

private func line(_ text: String) -> Data { Data(text.utf8) }

@Test func everyMessageRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_760_000_000.25)
    let messages: [FringeMessage] = [
        .hello(FringeHello(app: "Fringe", appVersion: "0.1.0", capabilities: [.answer])),
        .snapshot(FringeSnapshot(
            chats: [FringeChat(id: "c1", title: "Fix tests", project: "fringe", phase: .working, activity: "Running tests", since: now, updated: now)],
            requests: [FringeRequest(id: "r1", chatID: "c1", kind: .approval, title: "Action required", reason: "Run rm", details: "rm -rf build", canAllow: true)])),
        .announce(FringeAnnouncement(kind: .request, chatID: "c1", requestID: "r1", chatTitle: "Fix tests")),
        .answerResult(FringeAnswerResult(requestID: "r1", outcome: .failed, message: "Not connected")),
        .openChat(chatID: "c1"),
        .answer(requestID: "r1", response: .allowOnce)
    ]
    for message in messages {
        let data = try FringeCodec.encode(message)
        #expect(data.last == 0x0A)
        #expect(!data.dropLast().contains(0x0A))
        #expect(try FringeCodec.decode(data.dropLast()) == message)
    }
}

@Test func otherVersionIsRejected() {
    #expect(throws: FringeProtocolError.versionMismatch(2)) {
        try FringeCodec.decode(line(#"{"version":2,"type":"openChat","payload":{"chatID":"c1"}}"#))
    }
}

@Test func unknownTypeIsRejected() {
    #expect(throws: FringeProtocolError.unknownType("deleteChat")) {
        try FringeCodec.decode(line(#"{"version":1,"type":"deleteChat","payload":{}}"#))
    }
}

@Test func malformedPayloadIsRejected() {
    #expect(throws: FringeProtocolError.malformed("answer")) {
        try FringeCodec.decode(line(#"{"version":1,"type":"answer","payload":{"requestID":"r1","response":"allowAlways"}}"#))
    }
    #expect(throws: FringeProtocolError.malformed("header")) { try FringeCodec.decode(line("not json")) }
}

@Test func unknownCapabilitiesAreIgnored() throws {
    let message = try FringeCodec.decode(line(#"{"version":1,"type":"hello","payload":{"app":"Switchboard","appVersion":"9","capabilities":["answer","teleport"]}}"#))
    #expect(message == .hello(FringeHello(app: "Switchboard", appVersion: "9", capabilities: [.answer])))
}

@Test func lineBufferSplitsAndKeepsRemainder() throws {
    var buffer = FringeLineBuffer()
    let first = try buffer.append(line("{\"a\":1}\n{\"b\""))
    #expect(first == [line("{\"a\":1}")])
    let second = try buffer.append(line(":2}\n\n"))
    #expect(second == [line("{\"b\":2}")])
}

@Test func oversizedLineIsRejected() {
    var buffer = FringeLineBuffer()
    #expect(throws: FringeProtocolError.lineTooLong) {
        _ = try buffer.append(Data(repeating: 0x41, count: FringeProtocol.maxLineBytes + 1))
    }
}

@Test func requirementPinsBundleAndTeam() {
    #expect(FringePeer.requirement(bundleID: "local.daniil.fringe", teamID: "ABCDE12345")
        == #"identifier "local.daniil.fringe" and anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345""#)
}

@Test func socketLivesInSwitchboardDataDirectory() {
    let url = FringeProtocol.socketURL(home: URL(filePath: "/Users/test"))
    #expect(url.path == "/Users/test/Library/Application Support/Context Desk/fringe.sock")
}
