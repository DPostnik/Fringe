import Foundation
import Testing
import FringeCore
import FringeProtocol
@testable import FringeAgents

private let now = Date(timeIntervalSince1970: 0)
private func chat(_ id: String, _ phase: FringeChat.Phase) -> FringeChat { FringeChat(id: id, title: id, project: "", phase: phase, updated: now) }

@MainActor @Test func moduleOwnsItsTab() {
    #expect(AgentsModule().tab == .agents)
}

@Test func summaryLeadsWithTheMostUrgentPhase() {
    #expect(AgentsPolicy.summary([]) == .idle)
    #expect(AgentsPolicy.summary([chat("a", .finished), chat("b", .working), chat("c", .working)]) == .working(2))
    #expect(AgentsPolicy.summary([chat("a", .working), chat("b", .waiting)]) == .waiting(1))
    #expect(AgentsPolicy.summary([chat("a", .finished)]) == .finished(1))
}

@Test func vanishedRequestsAreResolved() {
    let r1 = FringeRequest(id: "r1", chatID: "a", kind: .approval, title: "")
    let r2 = FringeRequest(id: "r2", chatID: "a", kind: .question, title: "")
    #expect(AgentsPolicy.resolvedRequests(previous: [r1, r2], current: [r2]) == ["r1"])
    #expect(AgentsPolicy.resolvedRequests(previous: [], current: [r1]).isEmpty)
}

@Test func retryBacksOffAndCaps() {
    #expect(AgentsPolicy.retryDelay(attempt: 0) == .seconds(1))
    #expect(AgentsPolicy.retryDelay(attempt: 2) == .seconds(5))
    #expect(AgentsPolicy.retryDelay(attempt: 40) == .seconds(15))
}
