import SwiftUI
import FringeCore
import FringeNotch

struct CalendarActions {
    var open: (CalendarEntry) -> Void
    var join: (CalendarEntry) -> Void
    var openSettings: () -> Void
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
                CalendarList(entries: model.entries, actions: actions)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
        .padding(.horizontal, 10).padding(.vertical, 7)
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
