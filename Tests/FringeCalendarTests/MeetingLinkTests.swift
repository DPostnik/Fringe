import Foundation
import Testing
@testable import FringeCalendar

@Test func findsGoogleMeetInLocation() {
    let link = MeetingLink.find(url: nil, location: "https://meet.google.com/abc-defg-hij", notes: nil)
    #expect(link?.absoluteString == "https://meet.google.com/abc-defg-hij")
}

@Test func findsZoomOnSubdomainInNotes() {
    let notes = """
    Hi team,
    Join Zoom Meeting: https://us02web.zoom.us/j/81234567890?pwd=AbCdEf123.
    Meeting ID: 812 3456 7890
    """
    #expect(MeetingLink.find(url: nil, location: nil, notes: notes)?.absoluteString
            == "https://us02web.zoom.us/j/81234567890?pwd=AbCdEf123")
}

@Test func findsTeamsMeetupJoinInsideAngleBrackets() {
    let notes = "Join on your computer <https://teams.microsoft.com/l/meetup-join/19%3ameeting_NjQ%40thread.v2/0?context=%7b%22Tid%22%3a%22x%22%7d>"
    let link = MeetingLink.find(url: nil, location: "Room 4", notes: notes)
    #expect(link?.host() == "teams.microsoft.com")
    #expect(link?.path().hasPrefix("/l/meetup-join/") == true)
}

@Test func findsTeamsLive() {
    let link = MeetingLink.find(url: nil, location: nil, notes: "Call: https://teams.live.com/meet/9876543210")
    #expect(link?.absoluteString == "https://teams.live.com/meet/9876543210")
}

@Test func prefersEventURLThenLocationThenNotes() {
    let url = URL(string: "https://meet.google.com/aaa-bbbb-ccc")
    let location = "https://zoom.us/j/111"
    let notes = "https://teams.live.com/meet/222"
    #expect(MeetingLink.find(url: url, location: location, notes: notes)?.host() == "meet.google.com")
    #expect(MeetingLink.find(url: nil, location: location, notes: notes)?.host() == "zoom.us")
    #expect(MeetingLink.find(url: URL(string: "https://example.com/agenda"), location: "Office", notes: notes)?.host() == "teams.live.com")
}

@Test func skipsNonMeetingLinksBeforeTheMeetingOne() {
    let notes = "Agenda: https://docs.google.com/document/d/1 then https://meet.google.com/xyz-abcd-efg (Google Meet)"
    #expect(MeetingLink.first(in: notes)?.absoluteString == "https://meet.google.com/xyz-abcd-efg")
}

@Test func linkWithoutSchemeIsUpgradedToHTTPS() {
    #expect(MeetingLink.first(in: "meet.google.com/abc-defg-hij")?.absoluteString == "https://meet.google.com/abc-defg-hij")
    #expect(MeetingLink.meetingURL(URL(string: "http://zoom.us/j/123")!)?.scheme == "https")
}

@Test func rejectsLookalikesAndLandingPages() {
    let rejected = [
        "https://meet.google.com/", "https://meet.google.com/new", "https://zoom.us/", "https://zoom.us/signin",
        "https://evilzoom.us/j/123", "https://zoom.us.example.com/j/123", "https://teams.microsoft.com/",
        "https://teams.microsoft.com/l/channel/abc", "https://teams.live.com/", "ftp://meet.google.com/abc-defg-hij",
        "https://meet.google.com.evil.io/abc-defg-hij"
    ]
    for string in rejected {
        #expect(MeetingLink.meetingURL(URL(string: string)!) == nil, "\(string)")
    }
    #expect(MeetingLink.find(url: nil, location: "Office 3", notes: "No call link here") == nil)
    #expect(MeetingLink.find(url: nil, location: nil, notes: nil) == nil)
}

@Test func calendarEventURL() {
    #expect(CalendarLinks.eventURL(externalIdentifier: nil) == nil)
    #expect(CalendarLinks.eventURL(externalIdentifier: "") == nil)
    #expect(CalendarLinks.eventURL(externalIdentifier: "ABC-123")?.absoluteString == "ical://ekevent/ABC-123?method=show&options=more")
    #expect(CalendarLinks.eventURL(externalIdentifier: "a1b2@google.com")?.absoluteString
            == "ical://ekevent/a1b2@google.com?method=show&options=more")
    #expect(CalendarLinks.eventURL(externalIdentifier: "x/y?z")?.absoluteString == "ical://ekevent/x%2Fy%3Fz?method=show&options=more")
}

@Test func googleSourcesAreRecognizedByTitle() {
    #expect(CalendarSources.isGoogle(sourceTitle: "Google"))
    #expect(CalendarSources.isGoogle(sourceTitle: "someone@gmail.com"))
    #expect(!CalendarSources.isGoogle(sourceTitle: "iCloud"))
    #expect(!CalendarSources.isGoogle(sourceTitle: "Other"))
}
