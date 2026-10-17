import AppKit
import Foundation
import Network
import os
import FringeCore
import FringeProtocol

/// Pure decisions for the Agents tab, kept apart from the socket so they are testable.
public enum AgentsPolicy {
    /// The strip's resting look: whoever needs the user most leads.
    public static func summary(_ chats: [FringeChat]) -> AgentSummary {
        let waiting = chats.filter { $0.phase == .waiting }.count
        let working = chats.filter { $0.phase == .working }.count
        let finished = chats.filter { $0.phase == .finished }.count
        return waiting > 0 ? .waiting(waiting) : working > 0 ? .working(working) : finished > 0 ? .finished(finished) : .idle
    }

    public static func requestEventID(_ requestID: String) -> String { "agent-request-\(requestID)" }

    /// Requests that disappeared from the snapshot were answered or cancelled elsewhere.
    public static func resolvedRequests(previous: [FringeRequest], current: [FringeRequest]) -> [String] {
        let now = Set(current.map(\.id))
        return previous.map(\.id).filter { !now.contains($0) }
    }

    /// Delays between connection attempts while Switchboard runs: 1 s, 2 s, 5 s, then every 15 s.
    public static func retryDelay(attempt: Int) -> Duration {
        let steps: [Duration] = [.seconds(1), .seconds(2), .seconds(5), .seconds(15)]
        return steps[min(max(attempt, 0), steps.count - 1)]
    }
}

/// State of one answer sent from the panel. Never retried.
public enum AnswerState: Equatable, Sendable {
    case sending
    case failed(String)
    /// The connection dropped before a result arrived; the user checks the chat.
    case unknown
}

/// The client end of the channel to Switchboard.
@MainActor final class AgentsLink: ObservableObject {
    enum Status: Equatable {
        case notRunning
        case connecting
        case connected
        /// The peer speaks another protocol; no reconnect until either app is updated.
        case incompatible(String)
    }

    @Published private(set) var status = Status.notRunning
    @Published private(set) var snapshot = FringeSnapshot(chats: [], requests: [])
    @Published private(set) var answers: [String: AnswerState] = [:]
    @Published private(set) var canAnswer = false

    var onSnapshot: (FringeSnapshot, _ resolved: [String]) -> Void = { _, _ in }
    var onAnnounce: (FringeAnnouncement) -> Void = { _ in }

    private let log = Logger(subsystem: "local.daniil.fringe", category: "agents")
    private var connection: NWConnection?
    private var lineBuffer = FringeLineBuffer()
    private var retryTask: Task<Void, Never>?
    private var attempt = 0
    private var observers: [NSObjectProtocol] = []
    private let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isSwitchboard(note) else { return }
            MainActor.assumeIsolated { self?.attempt = 0; self?.connectIfRunning() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard Self.isSwitchboard(note) else { return }
            MainActor.assumeIsolated { self?.disconnect(status: .notRunning) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.status != .connected { self?.attempt = 0; self?.connectIfRunning() } }
        })
        connectIfRunning()
    }

    func launchSwitchboard() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: FringeProtocol.serverBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openChat(_ chatID: String) { send(.openChat(chatID: chatID)) }

    /// Sends the answer exactly once; a lost connection leaves it unknown instead of resending.
    func answer(_ request: FringeRequest, _ response: FringeAnswer) {
        guard canAnswer, status == .connected, answers[request.id] == nil else { return }
        answers[request.id] = .sending
        send(.answer(requestID: request.id, response: response))
    }

    private nonisolated static func isSwitchboard(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == FringeProtocol.serverBundleID
    }

    private var switchboardRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: FringeProtocol.serverBundleID).isEmpty
    }

    private func connectIfRunning() {
        retryTask?.cancel()
        guard connection == nil else { return }
        if case .incompatible = status { return }
        guard switchboardRunning else { status = .notRunning; return }
        status = .connecting
        let connection = NWConnection(to: .unix(path: FringeProtocol.socketURL().path), using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.connectionChanged(connection, state) }
        }
        connection.start(queue: .main)
    }

    private func connectionChanged(_ connection: NWConnection, _ state: NWConnection.State) {
        guard connection === self.connection else { return }
        switch state {
        case .ready:
            send(.hello(FringeHello(app: "Fringe", appVersion: appVersion, capabilities: FringeCapability.allCases)))
            receive(on: connection)
        case .failed(let error), .waiting(let error):
            log.info("Connection to Switchboard unavailable: \(error.localizedDescription, privacy: .public)")
            disconnect(status: switchboardRunning ? .connecting : .notRunning)
            scheduleRetry()
        case .cancelled:
            break
        default:
            break
        }
    }

    private func scheduleRetry() {
        guard switchboardRunning else { return }
        let delay = AgentsPolicy.retryDelay(attempt: attempt)
        attempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.connectIfRunning()
        }
    }

    private func receive(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self, connection === self.connection else { return }
                if let data, !data.isEmpty { self.consume(data) }
                guard self.connection === connection else { return }
                if complete || error != nil {
                    self.disconnect(status: self.switchboardRunning ? .connecting : .notRunning)
                    self.scheduleRetry()
                } else {
                    self.receive(on: connection)
                }
            }
        }
    }

    private func consume(_ data: Data) {
        do {
            for line in try lineBuffer.append(data) { handle(try FringeCodec.decode(line)) }
        } catch let error as FringeProtocolError {
            // Fail closed: another protocol version or an unknown message ends the session.
            log.error("Protocol error from Switchboard: \(String(describing: error), privacy: .public)")
            let detail = switch error {
            case .versionMismatch(let version): "version \(version)"
            case .unknownType(let type): "message \(type)"
            case .malformed(let type): "malformed \(type)"
            case .lineTooLong: "line too long"
            }
            disconnect(status: .incompatible(detail))
        } catch {
            disconnect(status: .incompatible(error.localizedDescription))
        }
    }

    private func handle(_ message: FringeMessage) {
        switch message {
        case .hello(let hello):
            attempt = 0
            canAnswer = hello.capabilities.contains(.answer)
            status = .connected
        case .snapshot(let snapshot):
            guard status == .connected else { return disconnect(status: .incompatible("snapshot before hello")) }
            let resolved = AgentsPolicy.resolvedRequests(previous: self.snapshot.requests, current: snapshot.requests)
            self.snapshot = snapshot
            // A request that is gone was answered somewhere, so its unknown answer is settled.
            let pending = Set(snapshot.requests.map(\.id))
            answers = answers.filter { pending.contains($0.key) || $0.value == .sending }
            onSnapshot(snapshot, resolved)
        case .announce(let announcement):
            guard status == .connected else { return }
            onAnnounce(announcement)
        case .answerResult(let result):
            guard answers[result.requestID] == .sending else { return }
            answers[result.requestID] = switch result.outcome {
            case .sent: nil
            case .failed: .failed(result.message ?? L10n.text("Ответ не отправлен.", "The answer was not sent."))
            }
        case .openChat, .answer:
            // Messages only Fringe sends; receiving one means the peer is not Switchboard.
            disconnect(status: .incompatible(message.type))
        }
    }

    private func send(_ message: FringeMessage) {
        guard let connection, let data = try? FringeCodec.encode(message) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in
                guard let self, connection === self.connection else { return }
                self.disconnect(status: .connecting)
                self.scheduleRetry()
            }
        })
    }

    private func disconnect(status newStatus: Status) {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        lineBuffer = FringeLineBuffer()
        canAnswer = false
        for (id, state) in answers where state == .sending { answers[id] = .unknown }
        if !snapshot.chats.isEmpty || !snapshot.requests.isEmpty {
            let resolved = snapshot.requests.map(\.id)
            snapshot = FringeSnapshot(chats: [], requests: [])
            onSnapshot(snapshot, resolved)
        }
        status = newStatus
    }
}
