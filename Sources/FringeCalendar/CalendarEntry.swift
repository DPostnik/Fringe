import Foundation

/// An sRGB color of a calendar, kept as plain numbers so entries stay `Sendable`.
public struct CalendarColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }

    public static let fallback = CalendarColor(red: 0.55, green: 0.55, blue: 0.6)
}

/// One occurrence of a calendar event, copied out of EventKit so the logic is testable.
public struct CalendarEntry: Identifiable, Equatable, Hashable, Sendable {
    /// Unique per occurrence (recurring events share the EventKit identifier).
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var color: CalendarColor
    /// Used to open the event in Calendar.app.
    public var externalIdentifier: String?
    /// The first Meet/Zoom/Teams link found in the event, if any.
    public var meetingURL: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                color: CalendarColor = .fallback, externalIdentifier: String? = nil, meetingURL: URL? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
        self.color = color; self.externalIdentifier = externalIdentifier; self.meetingURL = meetingURL
    }
}
