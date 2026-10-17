import AppKit
import ServiceManagement
import SwiftUI
import FringeCore

/// General settings plus one section per tab that has settings.
struct SettingsView: View {
    let sections: [(FringeTab, AnyView)]
    let onChange: () -> Void
    @State private var preferences = FringePreferences.load()
    @State private var language = AppLanguage.load()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section(L10n.text("Основные", "General")) {
                Toggle(L10n.text("Запускать при входе в систему", "Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle(L10n.text("Прятать шторку, когда нечего показать", "Hide the strip when there is nothing to show"), isOn: binding(\.autoHide))
                Toggle(L10n.text("Звуки", "Sounds"), isOn: binding(\.sound))
                Toggle(L10n.text("Системные уведомления", "System notifications"), isOn: binding(\.systemNotifications))
                LabeledContent(L10n.text("Перевод по сочетанию клавиш", "Translate shortcut")) {
                    ShortcutRecorder(combo: Binding(get: { preferences.translateShortcut },
                                                    set: { preferences.translateShortcut = $0; save() }))
                }
                Picker(L10n.text("Язык интерфейса", "Interface language"), selection: $language) {
                    ForEach(AppLanguage.allCases, id: \.self) { Text($0.nativeName).tag($0) }
                }
                .onChange(of: language) { _, value in value.save() }
                if language != L10n.language {
                    Text(L10n.text("Язык сменится после перезапуска Fringe.", "The language changes after Fringe restarts."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(sections, id: \.0) { tab, view in
                Section(tab.title()) { view }
            }
            Section {
                HStack {
                    Text(L10n.text("Сторонний код: Coucou (MIT)", "Third-party code: Coucou (MIT)"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.text("Выйти из Fringe", "Quit Fringe")) { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .frame(minHeight: 600)
    }

    private func binding(_ key: WritableKeyPath<FringePreferences, Bool>) -> Binding<Bool> {
        Binding(get: { preferences[keyPath: key] }, set: { preferences[keyPath: key] = $0; save() })
    }

    private func save() {
        // Merge with the stored value so the panel's remembered tab is not overwritten.
        var stored = FringePreferences.load()
        stored.autoHide = preferences.autoHide
        stored.sound = preferences.sound
        stored.systemNotifications = preferences.systemNotifications
        stored.translateShortcut = preferences.translateShortcut
        stored.save()
        onChange()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = L10n.text("Не удалось изменить автозапуск: \(error.localizedDescription)",
                                   "Could not change open at login: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// Click, then press the new combination; Esc cancels, Delete turns the shortcut off.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var invalid = false

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? L10n.text("Нажми сочетание…", "Press keys…")
                   : combo?.display ?? L10n.text("Выключено", "Off")) { recording ? stop() : start() }
            if invalid {
                Text(L10n.text("Нужен ⌘, ⌥ или ⌃", "Needs ⌘, ⌥ or ⌃")).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true; invalid = false
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case 53: stop() // Esc
            case 51, 117: combo = nil; stop() // Delete, Forward Delete
            default:
                var modifiers = KeyCombo.Modifiers()
                let flags = event.modifierFlags
                if flags.contains(.command) { modifiers.insert(.command) }
                if flags.contains(.option) { modifiers.insert(.option) }
                if flags.contains(.control) { modifiers.insert(.control) }
                if flags.contains(.shift) { modifiers.insert(.shift) }
                let key = event.charactersIgnoringModifiers?.uppercased() ?? "?"
                let candidate = KeyCombo(keyCode: UInt32(event.keyCode), key: key, modifiers: modifiers)
                if candidate.isValid { combo = candidate; stop() } else { invalid = true }
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
