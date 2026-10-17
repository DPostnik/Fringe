import Foundation
import Testing
import FringeCore
@testable import FringeCalendar

private let moscow = TimeZone(identifier: "Europe/Moscow")!

private func calendar(_ zone: TimeZone = moscow) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

/// A date in the given zone, 2026-10-<day> hh:mm.
private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, zone: TimeZone = moscow) -> Date {
    calendar(zone).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private func timed(_ id: String, _ start: Date, minutes: Double = 60) -> CalendarEntry {
    CalendarEntry(id: id, title: id, start: start, end: start.addingTimeInterval(minutes * 60))
}

/// EventKit gives all-day events an end of 23:59:59 on the last day.
private func allDay(_ id: String, day: Int, days: Int = 1) -> CalendarEntry {
    CalendarEntry(id: id, title: id, start: at(day, 0), end: at(day + days, 0).addingTimeInterval(-1), isAllDay: true)
}

private func ids(_ section: CalendarDaySection) -> [String] { section.entries.map(\.id) }

// MARK: - Grouping

@Test func groupsIntoTodayTomorrowAndDates() {
    let now = at(17, 9)
    let entries = [timed("later", at(20, 15)), timed("tomorrow", at(18, 10)), timed("today", at(17, 12))]
    let sections = CalendarSchedule.sections(for: entries, now: now, calendar: calendar())
    #expect(sections.map(\.kind) == [.today, .tomorrow, .later])
    #expect(sections.map(\.day) == [at(17, 0), at(18, 0), at(20, 0)])
    #expect(sections.map(ids) == [["today"], ["tomorrow"], ["later"]])
}

@Test func dropsEventsOutsideTheSevenDayWindowAndEndedOnes() {
    let now = at(17, 9)
    let entries = [timed("ended", at(17, 7)), timed("day7", at(23, 23, 30)), timed("day8", at(24, 0)),
                   timed("yesterday", at(16, 10))]
    let sections = CalendarSchedule.sections(for: entries, now: now, calendar: calendar())
    #expect(sections.flatMap(ids) == ["day7"])
    #expect(sections.first?.kind == .today)
    #expect(sections.first?.entries.isEmpty == true)
}

@Test func noSectionsWhenNothingIsAhead() {
    let sections = CalendarSchedule.sections(for: [timed("ended", at(17, 7))], now: at(17, 9), calendar: calendar())
    #expect(sections.isEmpty)
}

@Test func ongoingEventFromYesterdayShowsUnderToday() {
    let overnight = timed("overnight", at(16, 23), minutes: 180)
    let sections = CalendarSchedule.sections(for: [overnight], now: at(17, 1), calendar: calendar())
    #expect(sections.map(ids) == [["overnight"]])
    #expect(sections.first?.kind == .today)
}

@Test func allDayEventsCoverEachDayAndSortFirst() {
    let now = at(17, 9)
    let entries = [timed("meeting", at(17, 10)), allDay("trip", day: 16, days: 3), allDay("holiday", day: 17)]
    let sections = CalendarSchedule.sections(for: entries, now: now, calendar: calendar())
    #expect(sections.map(\.kind) == [.today, .tomorrow])
    #expect(ids(sections[0]) == ["trip", "holiday", "meeting"])
    #expect(ids(sections[1]) == ["trip"])
}

@Test func dayBoundariesFollowTheInjectedTimeZone() {
    // 23:30 UTC on the 17th is 02:30 on the 18th in Moscow.
    let utc = TimeZone(identifier: "UTC")!
    let event = timed("call", at(17, 23, 30, zone: utc))
    let now = at(17, 12, zone: utc)
    let inUTC = CalendarSchedule.sections(for: [event], now: now, calendar: calendar(utc))
    let inMoscow = CalendarSchedule.sections(for: [event], now: now, calendar: calendar(moscow))
    #expect(inUTC.map(\.kind) == [.today])
    #expect(inMoscow.map(\.kind) == [.today, .tomorrow])
    #expect(inMoscow.last.map(ids) == ["call"])
}

@Test func sameStartSortsByTitle() {
    let b = timed("b", at(17, 10)), a = timed("a", at(17, 10)), early = timed("z", at(17, 9, 30))
    let sections = CalendarSchedule.sections(for: [b, a, early], now: at(17, 9), calendar: calendar())
    #expect(sections.map(ids) == [["z", "a", "b"]])
}

// MARK: - Current and next

@Test func detectsCurrentAndNextIgnoringAllDay() {
    let now = at(17, 10, 15)
    let entries = [timed("current", at(17, 10)), timed("next", at(17, 11)), timed("alsoNext", at(17, 11), minutes: 30),
                   timed("later", at(17, 14)), allDay("holiday", day: 17), timed("past", at(17, 8))]
    let highlight = CalendarSchedule.highlight(entries, now: now)
    #expect(highlight.current == ["current"])
    #expect(highlight.next == ["next", "alsoNext"])
}

@Test func eventStartingNowIsCurrentAndEndingNowIsNot() {
    let now = at(17, 10)
    let highlight = CalendarSchedule.highlight([timed("starts", now), timed("ends", at(17, 9))], now: now)
    #expect(highlight.current == ["starts"])
    #expect(highlight.next.isEmpty)
}

@Test func nothingHighlightedForEmptyList() {
    #expect(CalendarSchedule.highlight([], now: at(17, 9)) == .none)
}

// MARK: - Countdown

@Test func countdownInRussianAndEnglish() {
    let now = at(17, 9, 35)
    #expect(CalendarSchedule.countdownText(now: now, until: at(17, 10), language: .russian) == "через 25 мин")
    #expect(CalendarSchedule.countdownText(now: now, until: at(17, 10), language: .english) == "in 25 min")
    #expect(CalendarSchedule.countdownText(now: now, until: at(17, 11, 35), language: .russian) == "через 2 ч")
    #expect(CalendarSchedule.countdownText(now: now, until: at(17, 11, 40), language: .english) == "in 2 h 5 min")
}

@Test func countdownRoundsUpPartialMinutes() {
    let start = at(17, 10)
    #expect(CalendarSchedule.countdownText(now: start.addingTimeInterval(-20), until: start, language: .english) == "in 1 min")
    #expect(CalendarSchedule.countdownText(now: start.addingTimeInterval(-61), until: start, language: .english) == "in 2 min")
}

@Test func noCountdownForPastOrFarEvents() {
    let now = at(17, 10)
    #expect(CalendarSchedule.countdownText(now: now, until: now, language: .russian) == nil)
    #expect(CalendarSchedule.countdownText(now: now, until: at(17, 9), language: .russian) == nil)
    #expect(CalendarSchedule.countdownText(now: now, until: at(18, 10), language: .russian) == nil)
    #expect(CalendarSchedule.countdownText(now: now, until: at(18, 9, 59), language: .english) == "in 23 h 59 min")
}

@Test func remainingTimeForCurrentEvent() {
    let now = at(17, 10, 40)
    #expect(CalendarSchedule.remainingText(now: now, until: at(17, 11), language: .russian) == "ещё 20 мин")
    #expect(CalendarSchedule.remainingText(now: now, until: at(17, 11), language: .english) == "20 min left")
}

// MARK: - Labels

@Test func dayTitles() {
    let cal = calendar()
    let today = CalendarDaySection(day: at(17, 0), kind: .today, entries: [])
    let tomorrow = CalendarDaySection(day: at(18, 0), kind: .tomorrow, entries: [])
    let later = CalendarDaySection(day: at(19, 0), kind: .later, entries: [])
    #expect(CalendarSchedule.dayTitle(today, calendar: cal, language: .russian) == "Сегодня")
    #expect(CalendarSchedule.dayTitle(tomorrow, calendar: cal, language: .english) == "Tomorrow")
    #expect(CalendarSchedule.dayTitle(later, calendar: cal, language: .russian) == "Понедельник, 19 октября")
    #expect(CalendarSchedule.dayTitle(later, calendar: cal, language: .english) == "Monday, October 19")
}

@Test func timeLabels() {
    let cal = calendar()
    #expect(CalendarSchedule.timeText(at(17, 9, 5), calendar: cal, language: .russian) == "09:05")
    let english = CalendarSchedule.timeText(at(17, 21, 5), calendar: cal, language: .english)
    #expect(english.hasPrefix("9:05") && english.hasSuffix("PM"))
    #expect(CalendarSchedule.allDayText(language: .russian) == "весь день")
    #expect(CalendarSchedule.allDayText(language: .english) == "all day")
}

@Test func windowStartsAtLocalMidnightAndSpansSevenDays() {
    let window = CalendarSchedule.window(now: at(17, 15), calendar: calendar())
    #expect(window.start == at(17, 0))
    #expect(window.end == at(24, 0))
}
