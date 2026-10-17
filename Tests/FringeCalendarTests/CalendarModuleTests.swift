import Testing
import FringeCore
@testable import FringeCalendar

@MainActor @Test func moduleOwnsItsTab() {
    #expect(CalendarModule().tab == .calendar)
}
