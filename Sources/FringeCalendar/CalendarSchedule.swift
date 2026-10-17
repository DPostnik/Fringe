import Foundation
import FringeCore

/// A day in the list: "Today", "Tomorrow" or a date.
public struct CalendarDaySection: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case today, tomorrow, later }
    /// Start of the day in the schedule's calendar.
    public var day: Date
    public var kind: Kind
    public var entries: [CalendarEntry]
    public var id: Date { day }
}

/// Which events are happening now and which come next.
public struct CalendarHighlight: Equatable, Sendable {
    public var current: Set<String>
    /// All timed events that share the nearest future start.
    public var next: Set<String>
    public static let none = CalendarHighlight(current: [], next: [])
}

/// Pure schedule logic; the calendar (time zone included) and the current time are injected.
public enum CalendarSchedule {
    public static let dayCount = 7

    /// The loading window: start of today through `days` days later.
    public static func window(now: Date, calendar: Calendar, days: Int = dayCount) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(Double(days) * 86_400)
        return DateInterval(start: start, end: end)
    }

    /// Groups entries by day. Ended events are dropped; a timed event that started earlier and is still
    /// going appears under today; an all-day event appears on every day it covers. Today is always the first
    /// section when any other day has events; other empty days are omitted.
    public static func sections(for entries: [CalendarEntry], now: Date, calendar: Calendar,
                                days: Int = dayCount) -> [CalendarDaySection] {
        let window = window(now: now, calendar: calendar, days: days)
        let today = window.start
        var dayStarts: [Date] = []
        var cursor = today
        while cursor < window.end {
            dayStarts.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        var buckets: [Date: [CalendarEntry]] = [:]
        for entry in entries {
            let visibleFrom = entry.isAllDay ? today : now
            guard entry.start < window.end, visibleFrom < entry.end else { continue }
            if entry.isAllDay {
                for (index, day) in dayStarts.enumerated() {
                    let dayEnd = index + 1 < dayStarts.count ? dayStarts[index + 1] : window.end
                    if entry.start < dayEnd && entry.end > day { buckets[day, default: []].append(entry) }
                }
            } else {
                let day = max(calendar.startOfDay(for: entry.start), today)
                buckets[day, default: []].append(entry)
            }
        }
        guard !buckets.isEmpty else { return [] }
        let tomorrow = dayStarts.count > 1 ? dayStarts[1] : nil
        return dayStarts.compactMap { day in
            let items = (buckets[day] ?? []).sorted(by: order)
            guard !items.isEmpty || day == today else { return nil }
            let kind: CalendarDaySection.Kind = day == today ? .today : day == tomorrow ? .tomorrow : .later
            return CalendarDaySection(day: day, kind: kind, entries: items)
        }
    }

    /// All-day first, then by start time, then by title.
    static func order(_ a: CalendarEntry, _ b: CalendarEntry) -> Bool {
        if a.isAllDay != b.isAllDay { return a.isAllDay }
        if a.start != b.start { return a.start < b.start }
        if a.title != b.title { return a.title.localizedStandardCompare(b.title) == .orderedAscending }
        return a.id < b.id
    }

    /// Current: timed events that have started and not ended. Next: timed events with the nearest future start.
    /// All-day events are never highlighted.
    public static func highlight(_ entries: [CalendarEntry], now: Date) -> CalendarHighlight {
        let timed = entries.filter { !$0.isAllDay }
        let current = Set(timed.filter { $0.start <= now && now < $0.end }.map(\.id))
        let upcoming = timed.filter { $0.start > now }
        guard let nearest = upcoming.map(\.start).min() else { return CalendarHighlight(current: current, next: []) }
        return CalendarHighlight(current: current, next: Set(upcoming.filter { $0.start == nearest }.map(\.id)))
    }

    /// "через 25 мин" / "in 25 min"; hours past 60 minutes; nil when the start passed or is a day or more away.
    public static func countdownText(now: Date, until start: Date, language: AppLanguage = L10n.language) -> String? {
        guard let span = spanText(now: now, until: start, language: language) else { return nil }
        return L10n.text("через \(span)", "in \(span)", language: language)
    }

    /// "ещё 20 мин" / "20 min left" for an event in progress.
    public static func remainingText(now: Date, until end: Date, language: AppLanguage = L10n.language) -> String? {
        guard let span = spanText(now: now, until: end, language: language) else { return nil }
        return L10n.text("ещё \(span)", "\(span) left", language: language)
    }

    /// Whole minutes rounded up so a minute tick never shows "0 min".
    static func spanText(now: Date, until date: Date, language: AppLanguage) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        guard minutes < 24 * 60 else { return nil }
        let min = L10n.text("мин", "min", language: language), hour = L10n.text("ч", "h", language: language)
        if minutes < 60 { return "\(minutes) \(min)" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) \(hour)" : "\(h) \(hour) \(m) \(min)"
    }

    /// "Сегодня" / "Today", "Завтра" / "Tomorrow", otherwise a weekday and date such as "Понедельник, 20 октября".
    public static func dayTitle(_ section: CalendarDaySection, calendar: Calendar,
                                language: AppLanguage = L10n.language) -> String {
        switch section.kind {
        case .today: return L10n.text("Сегодня", "Today", language: language)
        case .tomorrow: return L10n.text("Завтра", "Tomorrow", language: language)
        case .later:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = language.locale
            formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
            let text = formatter.string(from: section.day)
            return text.prefix(1).uppercased(with: language.locale) + text.dropFirst()
        }
    }

    /// Short local time, e.g. "09:30" (ru) or "9:30 AM" (en).
    public static func timeText(_ date: Date, calendar: Calendar, language: AppLanguage = L10n.language) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = language.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    public static func allDayText(language: AppLanguage = L10n.language) -> String {
        L10n.text("весь день", "all day", language: language)
    }
}
