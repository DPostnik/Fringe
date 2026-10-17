import AppKit
import EventKit
import os
import FringeCore

/// Reads the next seven days from EventKit. Nothing happens until the tab is first shown; after that the
/// list is refreshed by store, day-change and wake notifications (no polling). Changes that arrive while
/// the tab is hidden only mark the list stale; it is reloaded the next time the tab is shown.
@MainActor final class CalendarModel: ObservableObject {
    enum Access: Equatable { case unknown, notDetermined, requesting, denied, restricted, granted }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var entries: [CalendarEntry] = []
    @Published private(set) var loaded = false
    /// False when no Google calendar is visible: the Google account is not added to macOS Internet Accounts.
    @Published private(set) var hasGoogleCalendars = true
    /// Every event calendar macOS shares with Fringe, for the Settings list.
    @Published private(set) var calendars: [CalendarInfo] = []
    /// Calendars the user turned off in Settings.
    @Published private(set) var hiddenCalendars: Set<String>

    private static let hiddenKey = "calendarHiddenIDs"
    private let defaults: UserDefaults

    private let log = Logger(subsystem: "local.daniil.fringe", category: "calendar")

    private var store: EKEventStore?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var visible = false
    private var stale = true
    private var requested = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenCalendars = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    }

    func setCalendar(_ id: String, shown: Bool) {
        if shown { hiddenCalendars.remove(id) } else { hiddenCalendars.insert(id) }
        defaults.set(hiddenCalendars.sorted(), forKey: Self.hiddenKey)
        if access == .granted { reload() }
    }

    /// The Settings section opened: list calendars even if the tab has not been shown yet.
    func refreshForSettings() {
        updateAccess()
        if access == .granted { reload() }
    }

    func setVisible(_ visible: Bool) {
        self.visible = visible
        guard visible else { return }
        let before = access
        updateAccess()
        // Access granted in System Settings while Fringe runs: the old store never sees events.
        if access == .granted, before != .granted, before != .unknown { resetStore(); stale = true }
        switch access {
        case .notDetermined where !requested: requestAccess()
        case .granted where stale: reload()
        default: break
        }
    }

    /// Asks for full access; the system prompt shows only while the status is not determined.
    func requestAccess() {
        guard access == .notDetermined else { return }
        requested = true
        access = .requesting
        let store = eventStore()
        store.requestFullAccessToEvents { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.access = .unknown
                self.updateAccess()
                if self.access == .granted {
                    // A store created before access was granted keeps returning no events; start a fresh one.
                    self.resetStore()
                    self.stale = true
                    if self.visible { self.reload() }
                }
            }
        }
    }

    private func resetStore() {
        observers.forEach { center, token in center.removeObserver(token) }
        observers.removeAll()
        store = nil
    }

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let created = EKEventStore()
        store = created
        return created
    }

    private func updateAccess() {
        if access == .requesting { return }
        access = switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        default: .denied // denied, write-only (not enough to read), or unknown future cases
        }
    }

    private func reload() {
        let store = eventStore()
        observeIfNeeded(store)
        let calendar = Calendar.current
        let window = CalendarSchedule.window(now: Date(), calendar: calendar)
        // Start a day early so a timed event still in progress after midnight is included.
        let from = calendar.date(byAdding: .day, value: -1, to: window.start) ?? window.start
        let calendars = store.calendars(for: .event)
        hasGoogleCalendars = calendars.contains { CalendarSources.isGoogle(sourceTitle: $0.source.title) }
        let sources = Set(calendars.map { "\($0.source.sourceType.rawValue)" }).sorted().joined(separator: ",")
        let predicate = store.predicateForEvents(withStart: from, end: window.end, calendars: nil)
        let events = store.events(matching: predicate)
        let counts = Dictionary(grouping: events, by: { $0.calendar.calendarIdentifier }).mapValues(\.count)
        self.calendars = calendars.map {
            CalendarInfo(id: $0.calendarIdentifier, title: $0.title, account: $0.source.title,
                         color: Self.color(of: $0), events: counts[$0.calendarIdentifier] ?? 0)
        }.sorted { ($0.account, $0.title) < ($1.account, $1.title) }
        entries = events.filter { !hiddenCalendars.contains($0.calendar.calendarIdentifier) }.compactMap(Self.entry(from:))
        log.info("Calendar reload: \(calendars.count) calendars, source types [\(sources, privacy: .public)], Google: \(self.hasGoogleCalendars), \(self.entries.count) events")
        stale = false
        loaded = true
    }

    private func observeIfNeeded(_ store: EKEventStore) {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default, workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(NotificationCenter, Notification.Name, AnyObject?)] = [
            (center, .EKEventStoreChanged, store),
            (center, .NSCalendarDayChanged, nil),
            (workspace, NSWorkspace.didWakeNotification, nil)
        ]
        for (target, name, object) in pairs {
            let token = target.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sourceChanged() }
            }
            observers.append((target, token))
        }
    }

    private func sourceChanged() {
        stale = true
        guard visible else { return }
        updateAccess()
        if access == .granted { reload() }
    }

    private static func entry(from event: EKEvent) -> CalendarEntry? {
        if event.status == .canceled { return nil }
        if event.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined { return nil }
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let base = event.calendarItemExternalIdentifier ?? event.eventIdentifier ?? UUID().uuidString
        let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CalendarEntry(
            id: "\(base)|\(Int(start.timeIntervalSince1970))",
            title: title.isEmpty ? L10n.text("Без названия", "Untitled") : title,
            start: start, end: max(end, start), isAllDay: event.isAllDay,
            color: color(of: event.calendar),
            externalIdentifier: event.calendarItemExternalIdentifier,
            meetingURL: MeetingLink.find(url: event.url, location: event.location, notes: event.notes))
    }

    private static func color(of calendar: EKCalendar?) -> CalendarColor {
        guard let color = calendar?.color?.usingColorSpace(.sRGB) else { return .fallback }
        return CalendarColor(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
    }
}

enum CalendarSources {
    /// macOS names a Google account's source after the account ("Google" or the Gmail address).
    static func isGoogle(sourceTitle: String) -> Bool {
        let title = sourceTitle.lowercased()
        return title.contains("google") || title.hasSuffix("@gmail.com") || title.hasSuffix("@googlemail.com")
    }
}

/// One calendar as the Settings list shows it.
struct CalendarInfo: Identifiable, Equatable {
    var id: String
    var title: String
    /// The account (source) it belongs to, e.g. iCloud or a Gmail address.
    var account: String
    var color: CalendarColor
    /// Events in the shown window (yesterday to seven days ahead).
    var events: Int
}
