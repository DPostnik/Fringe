import AppKit
import SwiftUI
import FringeCore
import FringeNotch

struct CalendarActions {
    var open: (CalendarEntry) -> Void
    var join: (CalendarEntry) -> Void
    var openSettings: () -> Void
    var openAccounts: () -> Void
}

struct CalendarTabView: View {
    @ObservedObject var model: CalendarModel
    let actions: CalendarActions

    var body: some View {
        switch model.access {
        case .unknown, .requesting:
            FringeEmptyState(symbol: "calendar", message: L10n.text("Запрашиваю доступ к календарю…", "Requesting calendar access…"))
        case .notDetermined:
            FringeEmptyState(symbol: "calendar.badge.exclamationmark",
                             message: L10n.text("Fringe показывает события из системного Календаря. Нужен доступ на чтение.",
                                                "Fringe shows events from the system Calendar. It needs read access."),
                             actionTitle: L10n.text("Разрешить доступ", "Allow access")) { model.requestAccess() }
        case .denied:
            FringeEmptyState(symbol: "calendar.badge.exclamationmark",
                             message: L10n.text("Нет доступа к календарю. Включите Fringe в Настройках: Конфиденциальность → Календари (полный доступ).",
                                                "No calendar access. Turn on Fringe in Settings: Privacy → Calendars (full access)."),
                             actionTitle: L10n.text("Открыть Настройки", "Open Settings"), action: actions.openSettings)
        case .restricted:
            FringeEmptyState(symbol: "lock.fill", message: L10n.text("Доступ к календарю ограничен на этом Mac.",
                                                                     "Calendar access is restricted on this Mac."))
        case .granted:
            if model.loaded {
                VStack(spacing: 6) {
                    CalendarList(entries: model.entries, actions: actions)
                    if !model.hasGoogleCalendars { AccountHint(open: actions.openAccounts) }
                }
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Fringe reads the system Calendar; a Google calendar appears there only after the account is added to macOS.
private struct AccountHint: View {
    let open: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 16)).foregroundStyle(.orange)
            Text(L10n.text("Календарь Google не подключён к macOS. Добавь аккаунт Google в Интернет-аккаунтах и включи «Календари».",
                           "Google Calendar is not connected to macOS. Add your Google account in Internet Accounts and turn on Calendars."))
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(L10n.text("Открыть", "Open"), action: open).buttonStyle(FringeButtonStyle(prominent: true))
        }
        .padding(10)
        .fringeCard()
    }
}

/// Recomputed once a minute while visible, so the highlight and countdown stay current.
private struct CalendarList: View {
    let entries: [CalendarEntry]
    let actions: CalendarActions

    var body: some View {
        TimelineView(.everyMinute) { context in
            let calendar = Calendar.current
            let sections = CalendarSchedule.sections(for: entries, now: context.date, calendar: calendar)
            if sections.isEmpty {
                FringeEmptyState(symbol: "calendar", message: L10n.text("На ближайшие 7 дней событий нет", "No events in the next 7 days"))
            } else {
                let highlight = CalendarSchedule.highlight(sections.flatMap(\.entries), now: context.date)
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(sections) { section in
                            Text(CalendarSchedule.dayTitle(section, calendar: calendar))
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 4).padding(.top, section.kind == .today ? 0 : 8).padding(.bottom, 2)
                            if section.entries.isEmpty {
                                Text(L10n.text("Сегодня больше ничего нет", "Nothing else today"))
                                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                            }
                            ForEach(section.entries) { entry in
                                CalendarRow(entry: entry, now: context.date, calendar: calendar,
                                            isCurrent: highlight.current.contains(entry.id),
                                            isNext: highlight.next.contains(entry.id), actions: actions)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CalendarRow: View {
    let entry: CalendarEntry
    let now: Date
    let calendar: Calendar
    let isCurrent: Bool
    let isNext: Bool
    let actions: CalendarActions
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            time.frame(width: 62, alignment: .leading)
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                    .foregroundStyle(.white.opacity(0.92)).lineLimit(1).truncationMode(.tail)
                if let status {
                    Text(status).font(.system(size: 10, weight: .semibold)).foregroundStyle(isCurrent ? color : .orange)
                }
            }
            Spacer(minLength: 4)
            if entry.meetingURL != nil {
                Button(L10n.text("Подключиться", "Join")) { actions.join(entry) }
                    .buttonStyle(FringeButtonStyle(prominent: isCurrent || isNext))
                    .help(entry.meetingURL?.host() ?? "")
            }
        }
        .padding(FringeMetrics.rowPadding)
        .fringeCard(highlighted: isCurrent || hovering)
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { actions.open(entry) }
        .help(L10n.text("Открыть в Календаре", "Open in Calendar"))
    }

    @ViewBuilder private var time: some View {
        if entry.isAllDay {
            Text(CalendarSchedule.allDayText()).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(CalendarSchedule.timeText(entry.start, calendar: calendar))
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(.white.opacity(0.9))
                Text(CalendarSchedule.timeText(entry.end, calendar: calendar))
                    .font(.system(size: 10)).monospacedDigit().foregroundStyle(.white.opacity(0.45))
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private var status: String? {
        if isCurrent {
            let left = CalendarSchedule.remainingText(now: now, until: entry.end)
            return [L10n.text("Идёт", "Now"), left].compactMap { $0 }.joined(separator: " · ")
        }
        if isNext { return CalendarSchedule.countdownText(now: now, until: entry.start) }
        return nil
    }

    private var color: Color { Color(red: entry.color.red, green: entry.color.green, blue: entry.color.blue) }
}

/// Settings: every calendar macOS shares with Fringe, with its account, event count and a switch.
struct CalendarSettingsView: View {
    @ObservedObject var model: CalendarModel
    let openAccounts: () -> Void

    var body: some View {
        Group {
            if model.access != .granted {
                Text(L10n.text("Нет доступа к календарю. Открой вкладку «Календарь» в шторке, чтобы разрешить его.",
                               "No calendar access. Open the Calendar tab in the notch to allow it."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if model.calendars.isEmpty {
                Text(L10n.text("macOS не передаёт ни одного календаря.", "macOS shares no calendars."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.calendars) { info in
                    Toggle(isOn: Binding(get: { !model.hiddenCalendars.contains(info.id) },
                                         set: { model.setCalendar(info.id, shown: $0) })) {
                        HStack(spacing: 8) {
                            Circle().fill(Color(red: info.color.red, green: info.color.green, blue: info.color.blue)).frame(width: 9, height: 9)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(info.title)
                                Text("\(info.account) · " + L10n.text("событий на 7 дней: \(info.events)", "events in 7 days: \(info.events)"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Text(L10n.text("Fringe берёт события из системного Календаря macOS. Нет календаря Google или в нём пусто: проверь аккаунт в Интернет-аккаунтах (включены «Календари», вход не истёк), а дополнительные и общие календари отметь на странице синхронизации Google.",
                           "Fringe reads the macOS Calendar. A Google calendar missing or empty? Check the account in Internet Accounts (Calendars on, sign-in not expired) and tick secondary and shared calendars on Google's sync page."))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.text("Синхронизация Google", "Google sync page")) { NSWorkspace.shared.open(CalendarLinks.googleSyncSelect) }
                Button(L10n.text("Интернет-аккаунты", "Internet Accounts"), action: openAccounts)
            }
        }
        .onAppear { model.refreshForSettings() }
    }
}
