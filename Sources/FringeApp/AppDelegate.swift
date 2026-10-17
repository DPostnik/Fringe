import AppKit
import SwiftUI
import FringeAgents
import FringeCalendar
import FringeCore
import FringeMail
import FringeNotch
import FringeScreenshots
import FringeTranslate

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var modules: [any FringeTabModule] = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        modules = [AgentsModule(), MailModule(), CalendarModule(), ScreenshotsModule(), TranslateModule()]
        let controller = NotchController(modules: modules)
        controller.onOpenSettings = { [weak self] in self?.showSettings() }
        controller.start()
        self.controller = controller
        // Development aid: `open build/Fringe.app --args -FringeOpenTab translate` opens the panel pinned on a tab.
        if let tab = UserDefaults.standard.string(forKey: "FringeOpenTab").flatMap(FringeTab.init(rawValue:)) {
            controller.open(tab, focus: false)
        }
    }

    /// Launching the app again (Finder, Spotlight) opens Settings: the only window it has.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(sections: modules.compactMap { module in module.makeSettingsView().map { (module.tab, $0) } },
                                    onChange: { [weak self] in self?.controller?.reloadPreferences() })
                .environment(\.locale, L10n.locale)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = L10n.text("Настройки Fringe", "Fringe Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
