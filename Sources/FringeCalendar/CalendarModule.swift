import AppKit
import SwiftUI
import FringeCore
import FringeNotch

/// The Calendar tab: the next seven days from the system calendar (EventKit), read-only.
@MainActor public final class CalendarModule: FringeTabModule {
    public let tab = FringeTab.calendar
    let model = CalendarModel()
    private weak var hub: NotchHub?

    public init() {}

    public func start(hub: NotchHub) { self.hub = hub }

    public func makeView() -> AnyView {
        AnyView(CalendarTabView(model: model, actions: CalendarActions(
            open: { [weak self] in self?.open($0) },
            join: { [weak self] in self?.join($0) },
            openSettings: { [weak self] in self?.openPrivacySettings() },
            openAccounts: { [weak self] in
                NSWorkspace.shared.open(CalendarLinks.internetAccounts)
                self?.hub?.closePanel()
            })))
    }

    public func visibilityChanged(_ visible: Bool) { model.setVisible(visible) }

    private func open(_ entry: CalendarEntry) {
        let opened = CalendarLinks.eventURL(externalIdentifier: entry.externalIdentifier).map { NSWorkspace.shared.open($0) } ?? false
        if !opened { openCalendarApp() }
        hub?.closePanel()
    }

    private func join(_ entry: CalendarEntry) {
        guard let url = entry.meetingURL else { return }
        NSWorkspace.shared.open(url)
        hub?.closePanel()
    }

    private func openPrivacySettings() {
        NSWorkspace.shared.open(CalendarLinks.privacySettings)
        hub?.closePanel()
    }

    private func openCalendarApp() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
