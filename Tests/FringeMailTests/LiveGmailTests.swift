import Foundation
import Testing
@testable import FringeMail

/// Opt-in network check (`FRINGE_LIVE_IMAP=1 swift test --filter LiveGmail`): connects to imap.gmail.com
/// with the real client, passes the greeting and CAPABILITY check, and expects a made-up account
/// (not a Google account) to be rejected as an authentication failure.
@Test(.enabled(if: ProcessInfo.processInfo.environment["FRINGE_LIVE_IMAP"] != nil))
func liveGmailRejectsUnknownAccount() async throws {
    let address = "fringe-\(UUID().uuidString.lowercased())@example.com"
    do {
        try await MailSession.run(address: address, password: "notarealpassword") { _ in }
        Issue.record("session should not succeed")
    } catch let error as MailError {
        guard case .authenticationFailed = error else { Issue.record("unexpected error \(error)"); return }
    }
}
