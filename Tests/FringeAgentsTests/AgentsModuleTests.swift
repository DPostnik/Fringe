import Testing
import FringeCore
@testable import FringeAgents

@MainActor @Test func moduleOwnsItsTab() {
    #expect(AgentsModule().tab == .agents)
}
