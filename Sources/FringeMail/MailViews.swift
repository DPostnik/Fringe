import SwiftUI
import FringeCore
import FringeNotch

/// The tab: up to 20 unseen Primary messages; a click opens the message in the browser.
struct MailTabView: View {
    @ObservedObject var model: MailModel

    var body: some View {
        switch model.status {
        case .notConfigured:
            FringeEmptyState(symbol: "envelope.badge.person.crop",
                             message: L10n.text("Подключи Gmail: Настройки (шестерёнка справа вверху) → Почта.",
                                                "Connect Gmail: Settings (the gear at the top right) → Mail."))
        case .failed(let error, _) where error.isAuthentication:
            FringeEmptyState(symbol: "key.slash", message: error.message)
        case .connecting where model.messages.isEmpty, .offline where model.messages.isEmpty:
            VStack(spacing: 10) {
                if model.status == .offline {
                    Image(systemName: "wifi.slash").font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                } else {
                    ProgressView().controlSize(.small).tint(.white)
                }
                Text(model.statusLine).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error, _) where model.messages.isEmpty:
            FringeEmptyState(symbol: "exclamationmark.triangle", message: error.message,
                             actionTitle: L10n.text("Повторить", "Retry"), action: model.retry)
        default:
            list
        }
    }

    private var list: some View {
        VStack(spacing: 6) {
            header
            if model.messages.isEmpty {
                FringeEmptyState(symbol: "tray", message: L10n.text("Нет непрочитанных во «Входящих» (основные).",
                                                                     "No unread mail in Inbox (Primary)."))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    TimelineView(.everyMinute) { context in
                        LazyVStack(spacing: 4) {
                            ForEach(model.messages) { message in
                                MailRow(message: message, now: context.date) { model.open(message) }
                            }
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if model.status != .connected {
                Image(systemName: model.status == .offline ? "wifi.slash" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                Text(model.statusLine).lineLimit(1).truncationMode(.tail).foregroundStyle(.orange)
            } else {
                Text(L10n.text("Непрочитанные: \(model.unseenCount)", "Unread: \(model.unseenCount)"))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
            Button(L10n.text("Открыть Gmail", "Open Gmail")) { model.openInbox() }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 4)
    }
}

private struct MailRow: View {
    let message: MailMessage
    let now: Date
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(message.displaySender).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = message.date {
                        Text(relative(date)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1).fixedSize()
                    }
                }
                Text(message.displaySubject).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fringeCard(highlighted: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(message.senderAddress)
    }

    private func relative(_ date: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return L10n.text("сейчас", "now") }
        return date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated).locale(L10n.locale))
    }
}

extension MailModel {
    var statusLine: String {
        switch status {
        case .notConfigured: L10n.text("Не подключено", "Not connected")
        case .connecting: L10n.text("Подключение к Gmail…", "Connecting to Gmail…")
        case .connected: L10n.text("Подключено, непрочитанных: \(unseenCount)", "Connected, unread: \(unseenCount)")
        case .offline: L10n.text("Нет сети, ждём подключения", "Offline, waiting for the network")
        case .failed(let error, let retryAt):
            if let retryAt {
                L10n.text("\(error.message) Повтор в \(retryAt.formatted(date: .omitted, time: .shortened)).",
                          "\(error.message) Retrying at \(retryAt.formatted(date: .omitted, time: .shortened)).")
            } else {
                error.message
            }
        }
    }
}

/// The Mail section of the Settings window.
struct MailSettingsView: View {
    @ObservedObject var model: MailModel
    @State private var address = ""
    @State private var password = ""
    @State private var browser = MailBrowser.systemDefault
    @State private var saveError: String?

    var body: some View {
        Group {
            TextField(L10n.text("Адрес Gmail", "Gmail address"), text: $address, prompt: Text(verbatim: "name@gmail.com"))
                .textContentType(.username)
                .autocorrectionDisabled()
            SecureField(L10n.text("Пароль приложения", "App password"), text: $password,
                        prompt: Text(model.hasPassword ? L10n.text("Сохранён в Связке ключей", "Saved in the Keychain")
                                                       : L10n.text("16 букв", "16 letters")))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("Нужен пароль приложения Google, а не обычный пароль. Его можно создать только при включённой двухэтапной проверке. Хранится только в Связке ключей; письма не помечаются прочитанными.",
                               "Use a Google app password, not your account password. App passwords require 2-Step Verification. It is stored only in the Keychain; messages are never marked as read."))
                    .font(.caption).foregroundStyle(.secondary)
                Link(L10n.text("Создать пароль приложения", "Create an app password"),
                     destination: URL(string: "https://myaccount.google.com/apppasswords")!)
                    .font(.caption)
            }
            Picker(L10n.text("Открывать письма в", "Open messages in"), selection: $browser) {
                Text(L10n.text("Браузере по умолчанию", "Default browser")).tag(MailBrowser.systemDefault)
                Text(verbatim: "Google Chrome").tag(MailBrowser.chrome)
            }
            .onChange(of: browser) { _, value in model.setBrowser(value) }
            HStack {
                statusView
                Spacer()
                if model.hasPassword {
                    Button(L10n.text("Выйти", "Sign out")) {
                        model.signOut()
                        address = ""; password = ""; saveError = nil
                    }
                }
                Button(L10n.text("Сохранить и подключить", "Save and connect"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear {
            address = model.settings.address
            browser = model.settings.browser
        }
    }

    @ViewBuilder private var statusView: some View {
        if let saveError {
            Text(saveError).font(.caption).foregroundStyle(.red)
        } else {
            switch model.status {
            case .connected:
                Label(model.statusLine, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
            case .failed:
                Text(model.statusLine).font(.caption).foregroundStyle(.red)
            default:
                Text(model.statusLine).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        do {
            try model.save(address: address, password: password, browser: browser)
            password = ""
            saveError = nil
        } catch {
            saveError = switch error {
            case .invalidCredentials: L10n.text("Проверь адрес: нужен вид name@gmail.com, пароль только из латинских букв.",
                                                "Check the address (name@gmail.com); the password must be plain Latin letters.")
            default: error.message
            }
        }
    }
}
