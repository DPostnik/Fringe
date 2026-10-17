import Foundation

/// One Gmail IMAP session: log in, examine INBOX read-only, list unseen messages, then IDLE and
/// refresh on every mailbox change. Runs until an error or cancellation; reconnecting is the caller's job.
enum MailSession {
    enum Event: Sendable {
        case authenticated
        case snapshot(MailSnapshot)
    }

    static func run(address: String, password: String, nudger: MailNudger? = nil,
                    report: @escaping @Sendable (Event) async -> Void) async throws {
        let login: String
        do { login = try IMAPCommand.login(user: address, password: password) } catch { throw MailError.invalidCredentials }

        let client = IMAPClient()
        nudger?.attach(client)
        do {
            try await client.connect()
            try await session(client: client, login: login, report: report)
        } catch {
            await client.cancel()
            throw error
        }
    }

    private static func session(client: IMAPClient, login: String, report: @escaping @Sendable (Event) async -> Void) async throws {
        try await greeting(client)

        let capability = try await client.execute(IMAPCommand.capability)
        try require(capability, "CAPABILITY")
        let capabilities = Set(capability.untagged.flatMap { response -> [String] in
            if case .capability(let list) = response { return list } else { return [] }
        })
        guard capabilities.contains("IDLE"), capabilities.contains("X-GM-EXT-1") else {
            throw MailError.protocolError("IDLE or X-GM-EXT-1 missing")
        }

        let loggedIn = try await client.execute(login)
        switch loggedIn.status {
        case .ok: break
        case .no: throw MailError.authenticationFailed(loggedIn.text)
        default: throw MailError.protocolError("LOGIN \(loggedIn.status.rawValue)")
        }
        await report(.authenticated)

        let examined = try await client.execute(IMAPCommand.examineInbox)
        try require(examined, "EXAMINE")
        let uidValidity = examined.untagged.lazy.compactMap { response -> UInt32? in
            guard case .status(.ok, let code?, _) = response else { return nil }
            let parts = code.split(separator: " ")
            guard parts.count == 2, parts[0].uppercased() == "UIDVALIDITY" else { return nil }
            return UInt32(parts[1])
        }.first

        while true {
            await report(.snapshot(try await snapshot(client, uidValidity: uidValidity)))
            try await idleUntilChange(client)
        }
    }

    private static func greeting(_ client: IMAPClient) async throws {
        guard let response = try await client.next(timeout: MailTiming.connectTimeout) else { throw MailError.timeout }
        switch response {
        case .status(.ok, _, _): return
        case .status(.bye, _, let text): throw MailError.server(text)
        default: throw MailError.protocolError("unexpected greeting")
        }
    }

    private static func require(_ result: IMAPClient.Result, _ command: String) throws {
        switch result.status {
        case .ok: return
        case .no: throw MailError.server("\(command): \(result.text)")
        default: throw MailError.protocolError("\(command) \(result.status.rawValue)")
        }
    }

    static func snapshot(_ client: IMAPClient, uidValidity: UInt32?) async throws -> MailSnapshot {
        let search = try await client.execute(try IMAPCommand.searchUnseen())
        try require(search, "SEARCH")
        let unseen = search.untagged.flatMap { response -> [UInt32] in
            if case .search(let uids) = response { return uids } else { return [] }
        }
        let newest = MailSnapshot.newest(unseen)
        var messages: [MailMessage] = []
        if !newest.isEmpty {
            let fetch = try await client.execute(IMAPCommand.fetchHeaders(uids: newest))
            try require(fetch, "FETCH")
            let wanted = Set(newest)
            // Gmail may also report unsolicited flag changes for other messages; keep only the requested ones.
            messages = fetch.untagged.compactMap { response -> MailMessage? in
                guard case .fetch(let attributes) = response, let message = MailMessage(fetch: attributes),
                      wanted.contains(message.uid), attributes.header != nil else { return nil }
                return message
            }
            messages.sort { $0.uid > $1.uid }
        }
        return MailSnapshot(uidValidity: uidValidity, unseen: unseen, messages: messages)
    }

    /// Idles until the mailbox changes or the renewal interval passes, then ends the IDLE.
    /// Returns normally in both cases; the caller refreshes either way, which is a cheap check.
    static func idleUntilChange(_ client: IMAPClient) async throws {
        let tag = await client.nextTag()
        try await client.send(line: "\(tag) \(IMAPCommand.idle)")
        var pending: [IMAPResponse] = []
        // Wait for "+ idling"; a change reported before it still counts.
        idleStart: while true {
            guard let response = try await client.next(timeout: MailTiming.commandTimeout) else { throw MailError.timeout }
            switch response {
            case .continuation: break idleStart
            case .tagged(let responseTag, let status, _, let text) where responseTag == tag:
                throw MailError.server("IDLE \(status.rawValue): \(text)")
            case .status(.bye, _, let text): throw MailError.server(text)
            default: pending.append(response)
            }
        }

        let clock = ContinuousClock()
        let deadline = clock.now + MailTiming.idleRenewal
        var changed = pending.contains { $0.changesMailbox }
        while !changed {
            let remaining = clock.now.duration(to: deadline)
            // Nil: the renewal interval passed or the app asked for a refresh (Gmail does not always
            // report a message read elsewhere while idling).
            guard remaining > .zero, let response = try await client.next(timeout: remaining, nudgeable: true) else { break }
            switch response {
            case .status(.bye, _, let text): throw MailError.server(text)
            case .tagged: throw MailError.protocolError("IDLE ended by the server")
            default: changed = response.changesMailbox
            }
        }
        if changed {
            // A new message usually comes as EXISTS followed by FETCH; let the burst settle briefly.
            try? await Task.sleep(for: .milliseconds(300))
            try Task.checkCancellation()
        }
        try await client.send(line: IMAPCommand.done)
        let result = try await client.collect(tag: tag)
        if result.status != .ok { throw MailError.server("IDLE \(result.status.rawValue): \(result.text)") }
    }
}

/// Lets the app ask a running session to refresh now, e.g. when the user looks at the Mail tab.
final class MailNudger: @unchecked Sendable {
    private let lock = NSLock()
    private weak var client: IMAPClient?

    func attach(_ client: IMAPClient) { lock.withLock { self.client = client } }

    func nudge() {
        guard let client = lock.withLock({ self.client }) else { return }
        Task { await client.nudge() }
    }
}
