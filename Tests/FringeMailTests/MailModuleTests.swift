import Testing
import FringeCore
@testable import FringeMail

@MainActor @Test func moduleOwnsItsTab() {
    #expect(MailModule().tab == .mail)
}
