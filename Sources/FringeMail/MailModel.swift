import AppKit
import Combine
import FringeCore
import FringeNotch
import Network

public enum MailStatus: Equatable, Sendable {
    case notConfigured
    case connecting
    case connected
    /// No network path; reconnects when one appears.
    case offline
    /// `retryAt` is nil when nothing retries on its own (rejected credentials).
    case failed(MailError, retryAt: Date?)
}

/// Owns the Gmail connection for the app's lifetime and publishes the unseen list.
@MainActor final class MailModel: ObservableObject {
    @Published private(set) var status = MailStatus.notConfigured
    @Published private(set) var messages: [MailMessage] = []
    @Published private(set) var unseenCount = 0
    @Published private(set) var settings: MailSettings
    @Published private(set) var hasPassword = false

    private weak var hub: NotchHub?
    private let keychain: MailKeychain
    private let defaults: UserDefaults
    private var supervisor: Task<Void, Never>?
    private var generation = 0
    private var policy = ReconnectPolicy()
    private var diff = MailDiff()
    private var pathMonitor: NWPathMonitor?
    private var lastPath: (satisfied: Bool, interfaces: [String])?
    private var observers: [NSObjectProtocol] = []
    private var asleep = false

    init(keychain: MailKeychain = MailKeychain(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        settings = MailSettings.load(from: defaults)
        hasPassword = !settings.address.isEmpty && keychain.hasPassword(account: settings.address)
    }

    func start(hub: NotchHub) {
        self.hub = hub
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            let interfaces = path.availableInterfaces.map(\.name)
            Task { @MainActor in self?.pathChanged(satisfied: satisfied, interfaces: interfaces) }
        }
        monitor.start(queue: DispatchQueue(label: "local.daniil.fringe.mail.path"))
        pathMonitor = monitor
        connect()
    }

    var isConfigured: Bool { !settings.address.isEmpty && hasPassword }

    // MARK: Settings

    /// Saves the address and, when given, a new app password; then reconnects.
    /// An empty password keeps the stored one for the same address.
    func save(address rawAddress: String, password rawPassword: String, browser: MailBrowser) throws(MailError) {
        let address = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = MailSettings.normalizedAppPassword(rawPassword)
        guard MailSettings.isValidAddress(address) else { throw .invalidCredentials }
        if !password.isEmpty {
            guard (try? IMAPCommand.quoted(password)) != nil else { throw .invalidCredentials }
        } else if !keychain.hasPassword(account: address) {
            throw .missingPassword
        }
        let previous = settings.address
        if !password.isEmpty { try keychain.save(password: password, account: address) }
        if !previous.isEmpty, previous.caseInsensitiveCompare(address) != .orderedSame {
            keychain.delete(account: previous)
            diff.reset()
            publish(messages: [], unseen: 0)
        }
        settings = MailSettings(address: address, browser: browser)
        settings.save(to: defaults)
        hasPassword = true
        policy.reset()
        connect()
    }

    func setBrowser(_ browser: MailBrowser) {
        settings.browser = browser
        settings.save(to: defaults)
    }

    /// Removes the password and the address; the tab returns to "not configured".
    func signOut() {
        stopSession()
        if !settings.address.isEmpty { keychain.delete(account: settings.address) }
        settings.address = ""
        settings.save(to: defaults)
        hasPassword = false
        diff.reset()
        publish(messages: [], unseen: 0)
        status = .notConfigured
    }

    // MARK: Connection

    /// Starts a fresh session now, replacing any running one.
    func connect() {
        stopSession()
        guard isConfigured else { status = .notConfigured; return }
        if let lastPath, !lastPath.satisfied { status = .offline; return }
        let address = settings.address
        let password: String
        do { password = try keychain.password(account: address) } catch {
            status = .failed(error, retryAt: nil)
            return
        }
        generation += 1
        let generation = generation
        status = .connecting
        supervisor = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await MailSession.run(address: address, password: password) { [weak self] event in
                        await self?.handle(event, generation: generation)
                    }
                } catch {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    let failure = (error as? MailError) ?? .network(error.localizedDescription)
                    if failure.isAuthentication {
                        // Retrying a rejected password in a loop could lock the account; wait for new credentials.
                        self.status = .failed(failure, retryAt: nil)
                        return
                    }
                    let delay = self.policy.nextDelay()
                    self.status = .failed(failure, retryAt: Date().addingTimeInterval(TimeInterval(delay.components.seconds)))
                    try? await Task.sleep(for: delay)
                    if Task.isCancelled { return }
                    self.status = .connecting
                }
            }
        }
    }

    /// The "Retry" button: try again now.
    func retry() {
        policy.reset()
        connect()
    }

    private func stopSession() {
        supervisor?.cancel()
        supervisor = nil
        generation += 1
    }

    private func handle(_ event: MailSession.Event, generation: Int) {
        guard generation == self.generation else { return }
        switch event {
        case .authenticated:
            status = .connected
        case .snapshot(let snapshot):
            policy.reset()
            status = .connected
            let fresh = diff.update(snapshot)
            publish(messages: snapshot.messages, unseen: snapshot.unseen.count)
            for message in fresh.reversed() {
                hub?.post(PeekEvent(id: "mail-\(message.uid)", kind: .mail, title: message.displaySender, detail: message.displaySubject))
            }
        }
    }

    private func publish(messages: [MailMessage], unseen: Int) {
        self.messages = messages
        unseenCount = unseen
        hub?.unreadMail = unseen
        hub?.badges[.mail] = unseen > 0 ? unseen : nil
    }

    private func sleep() {
        asleep = true
        stopSession()
        if isConfigured, case .connected = status { status = .connecting }
    }

    private func wake() {
        asleep = false
        guard shouldReconnect else { return }
        policy.reset()
        connect()
    }

    private func pathChanged(satisfied: Bool, interfaces: [String]) {
        let previous = lastPath
        lastPath = (satisfied, interfaces)
        guard let previous else { return } // the first update only reports the current path
        guard !asleep else { return }
        if !satisfied {
            stopSession()
            if isConfigured, shouldReconnect { status = .offline }
            return
        }
        guard !previous.satisfied || previous.interfaces != interfaces, shouldReconnect else { return }
        policy.reset()
        connect()
    }

    /// Rejected or missing credentials and an unconfigured account wait for the user.
    private var shouldReconnect: Bool {
        guard isConfigured else { return false }
        if case .failed(let error, _) = status, error.isAuthentication { return false }
        return true
    }

    // MARK: Opening

    func open(_ message: MailMessage) {
        let account = settings.address
        guard let url = message.gmailMessageID.flatMap({ MailLink.message(id: $0, account: account) }) ?? MailLink.inbox(account: account) else { return }
        openURL(url)
        hub?.closePanel()
    }

    func openInbox() {
        guard let url = MailLink.inbox(account: settings.address) else { return }
        openURL(url)
        hub?.closePanel()
    }

    private func openURL(_ url: URL) {
        let workspace = NSWorkspace.shared
        if settings.browser == .chrome, let chrome = workspace.urlForApplication(withBundleIdentifier: MailBrowser.chromeBundleID) {
            workspace.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                // Chrome failed to open the link: fall back to the default browser.
                if error != nil { Task { @MainActor in NSWorkspace.shared.open(url) } }
            }
        } else {
            workspace.open(url)
        }
    }
}

extension MailMessage {
    var displaySender: String { sender.isEmpty ? L10n.text("Без отправителя", "Unknown sender") : sender }
    var displaySubject: String { subject.isEmpty ? L10n.text("(без темы)", "(no subject)") : subject }
}
