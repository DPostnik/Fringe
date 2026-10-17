import Foundation

/// Finds video-call links (Google Meet, Zoom, Microsoft Teams) in event fields.
public enum MeetingLink {
    /// Checks the event URL, then the location, then the notes; returns the first meeting link.
    public static func find(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, let link = meetingURL(url) { return link }
        for text in [location, notes] {
            if let text, let link = first(in: text) { return link }
        }
        return nil
    }

    /// The first meeting link inside free text.
    public static func first(in text: String) -> URL? {
        guard !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let link = meetingURL(url) { return link }
        }
        return nil
    }

    /// The URL itself, normalized to https, if it points to a meeting; otherwise nil.
    public static func meetingURL(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host?.lowercased() else { return nil }
        let path = components.percentEncodedPath
        guard isMeeting(host: host, path: path) else { return nil }
        components.scheme = "https"
        return components.url
    }

    static func isMeeting(host: String, path: String) -> Bool {
        let lowerPath = path.lowercased()
        if host == "meet.google.com" {
            // A room code like /abc-defg-hij, not the landing page or /new.
            let code = lowerPath.dropFirst().split(separator: "/").first.map(String.init) ?? ""
            return code.count >= 3 && code.contains("-") && code.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") {
            return lowerPath.hasPrefix("/j/") && lowerPath.count > 3
        }
        if host == "teams.microsoft.com" {
            return lowerPath.hasPrefix("/l/meetup-join/")
        }
        if host == "teams.live.com" {
            return lowerPath.count > 1
        }
        return false
    }
}

/// Links that open an event in Calendar.app or a settings pane.
public enum CalendarLinks {
    /// `ical://ekevent/<id>?method=show&options=more`; nil when there is no identifier.
    public static func eventURL(externalIdentifier: String?) -> URL? {
        guard let id = externalIdentifier, !id.isEmpty else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "ical://ekevent/\(encoded)?method=show&options=more")
    }

    /// System Settings, Privacy & Security, Calendars.
    public static let privacySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
}
