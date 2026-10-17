import Foundation
import FringeCore
import Network

/// One TLS connection to an IMAP server. Receives sequentially (one read outstanding at a time),
/// frames responses and hands them out in order. Nothing here logs traffic: it carries the password.
actor IMAPClient {
    struct Result {
        var status: IMAPStatus
        var code: String?
        var text: String
        var untagged: [IMAPResponse]
    }

    private let connection: NWConnection
    private var framer = IMAPFramer()
    private var queue: [IMAPResponse] = []
    private var failure: MailError?
    private var waiter: CheckedContinuation<IMAPResponse?, Error>?
    private var waiterGeneration = 0
    private var connectWaiter: CheckedContinuation<Void, Error>?
    private var ready = false
    private var tagCounter = 0

    init(host: String = "imap.gmail.com", port: UInt16 = 993) {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 20
        // Detects a dead socket during a long IDLE without any traffic from the app.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 300
        tcp.keepaliveInterval = 60
        tcp.keepaliveCount = 3
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!,
                                  using: NWParameters(tls: tls, tcp: tcp))
    }

    // MARK: Connection

    func connect(timeout: Duration = MailTiming.connectTimeout) async throws {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.stateChanged(state) }
        }
        connection.start(queue: DispatchQueue(label: "local.daniil.fringe.imap"))
        let timer = Task { [weak self] in
            try await Task.sleep(for: timeout)
            await self?.fail(.timeout)
        }
        defer { timer.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if let failure { continuation.resume(throwing: failure) }
                else if ready { continuation.resume() }
                else { connectWaiter = continuation }
            }
        } onCancel: {
            Task { await self.cancel() }
        }
        receiveNext()
    }

    func cancel() {
        fail(nil)
        connection.cancel()
    }

    private func stateChanged(_ state: NWConnection.State) {
        switch state {
        case .ready:
            ready = true
            connectWaiter?.resume()
            connectWaiter = nil
        case .waiting(let error):
            // No route (offline, captive network): fail now; the path monitor reconnects later.
            if !ready { fail(.network(Self.describe(error))) }
        case .failed(let error):
            fail(.network(Self.describe(error)))
        case .cancelled:
            fail(.network("cancelled"))
        default:
            break
        }
    }

    /// Ends the connection; a nil error means cancellation.
    private func fail(_ error: MailError?) {
        guard failure == nil else { return }
        failure = error ?? .network("cancelled")
        if let connectWaiter {
            self.connectWaiter = nil
            if let error { connectWaiter.resume(throwing: error) } else { connectWaiter.resume(throwing: CancellationError()) }
        }
        if let waiter {
            self.waiter = nil
            if let error { waiter.resume(throwing: error) } else { waiter.resume(throwing: CancellationError()) }
        }
        if error != nil { connection.cancel() }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .posix(let code): String(cString: strerror(code.rawValue))
        case .dns: "DNS"
        case .tls(let status): "TLS \(status)"
        default: error.localizedDescription
        }
    }

    // MARK: Receiving

    private func receiveNext() {
        guard failure == nil else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { await self.received(data, isComplete: isComplete, error: error) }
        }
    }

    private func received(_ data: Data?, isComplete: Bool, error: NWError?) {
        if let data, !data.isEmpty {
            framer.append(data)
            do {
                while let bytes = try framer.next() {
                    deliver(try IMAPParser.parse(bytes))
                }
            } catch let error as IMAPParseError {
                fail(.protocolError(error.reason))
                return
            } catch {
                fail(.protocolError("\(error)"))
                return
            }
        }
        if let error { fail(.network(Self.describe(error))); return }
        if isComplete { fail(.server(L10n.connectionClosed)); return }
        receiveNext()
    }

    private func deliver(_ response: IMAPResponse) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: response)
        } else {
            queue.append(response)
        }
    }

    /// The next response, or nil when `timeout` passes first.
    func next(timeout: Duration) async throws -> IMAPResponse? {
        if !queue.isEmpty { return queue.removeFirst() }
        if let failure { throw failure }
        try Task.checkCancellation()
        waiterGeneration += 1
        let generation = waiterGeneration
        let timer = Task { [weak self] in
            try await Task.sleep(for: timeout)
            await self?.expire(generation)
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter = continuation
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    private func expire(_ generation: Int) {
        guard generation == waiterGeneration, let waiter else { return }
        self.waiter = nil
        waiter.resume(returning: nil)
    }

    // MARK: Sending

    func send(line: String) async throws {
        if let failure { throw failure }
        let data = Data((line + "\r\n").utf8)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: MailError.network(Self.describe(error))) } else { continuation.resume() }
            })
        }
    }

    func nextTag() -> String {
        tagCounter += 1
        return String(format: "F%03d", tagCounter)
    }

    /// Sends a tagged command and collects untagged responses until its completion.
    func execute(_ command: String, timeout: Duration = MailTiming.commandTimeout) async throws -> Result {
        let tag = nextTag()
        try await send(line: "\(tag) \(command)")
        return try await collect(tag: tag, timeout: timeout)
    }

    func collect(tag: String, timeout: Duration = MailTiming.commandTimeout, into untagged: [IMAPResponse] = []) async throws -> Result {
        var untagged = untagged
        while true {
            guard let response = try await next(timeout: timeout) else { throw MailError.timeout }
            switch response {
            case .tagged(let responseTag, let status, let code, let text):
                guard responseTag == tag else { throw MailError.protocolError("unexpected tag \(responseTag)") }
                return Result(status: status, code: code, text: text, untagged: untagged)
            case .continuation:
                throw MailError.protocolError("unexpected continuation")
            default:
                untagged.append(response)
            }
        }
    }
}

extension L10n {
    static var connectionClosed: String { text("сервер закрыл соединение", "the server closed the connection") }
}
