import Foundation

/// The notch cut-out of a built-in display, in points. Screens without a notch have no panel.
/// Adapted from Switchboard (Context Desk), whose geometry follows Coucou (MIT, github.com/Louis-CFM/coucou):
/// the menu-bar areas left and right of the cut-out are reported by AppKit, the notch is the width between them.
public struct NotchGeometry: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height }

    public init?(screenWidth: CGFloat, safeAreaTop: CGFloat, auxiliaryLeftWidth: CGFloat?, auxiliaryRightWidth: CGFloat?) {
        guard safeAreaTop > 0, let left = auxiliaryLeftWidth, let right = auxiliaryRightWidth else { return nil }
        let width = screenWidth - left - right
        guard width > 40, width < screenWidth / 2 else { return nil }
        self.init(width: width, height: safeAreaTop)
    }
}

/// Visible state of the panel window.
public enum NotchMode: Equatable, Sendable {
    /// Nothing drawn; hovering the notch still opens the panel.
    case hidden
    /// A slim strip around the notch with the counters.
    case compact
    /// A short wider strip announcing one event.
    case peek
    /// The full panel with tabs.
    case expanded
}

/// The agents' state as the compact strip shows it; sent by Switchboard, idle without it.
public enum AgentSummary: Hashable, Sendable {
    case idle
    case working(Int)
    case waiting(Int)
    case finished(Int)

    public var isIdle: Bool { self == .idle }
    public var count: Int {
        switch self {
        case .idle: 0
        case .working(let count), .waiting(let count), .finished(let count): count
        }
    }
}

/// Pure decisions about the panel; the window controller only applies them.
public enum NotchPolicy {
    /// With auto-hide the strip shows only while there is something to count.
    public static func restingMode(agents: AgentSummary, unreadMail: Int, autoHide: Bool) -> NotchMode {
        autoHide && agents.isIdle && unreadMail == 0 ? .hidden : .compact
    }

    /// Hover or a pin opens, a peek widens the strip; otherwise the panel rests.
    public static func mode(resting: NotchMode, hovering: Bool, pinnedOpen: Bool, peeking: Bool) -> NotchMode {
        if hovering || pinnedOpen { return .expanded }
        if peeking { return .peek }
        return resting
    }

    /// Leaving the pointer closes the panel unless the user is typing in it.
    public static func closesOnHoverExit(editing: Bool) -> Bool { !editing }

    public static func duration(since start: Date, now: Date = Date(), language: AppLanguage = L10n.language) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return L10n.text("\(seconds) с", "\(seconds)s", language: language) }
        let minutes = seconds / 60
        if minutes < 60 { return L10n.text("\(minutes) мин", "\(minutes)m", language: language) }
        return L10n.text("\(minutes / 60) ч \(minutes % 60) мин", "\(minutes / 60)h \(minutes % 60)m", language: language)
    }
}

/// The panel's tabs in display order.
public enum FringeTab: String, Codable, CaseIterable, Sendable {
    case agents, mail, calendar, screenshots, translate

    public func title(language: AppLanguage = L10n.language) -> String {
        switch self {
        case .agents: L10n.text("Агенты", "Agents", language: language)
        case .mail: L10n.text("Почта", "Mail", language: language)
        case .calendar: L10n.text("Календарь", "Calendar", language: language)
        case .screenshots: L10n.text("Скриншоты", "Screenshots", language: language)
        case .translate: L10n.text("Перевод", "Translate", language: language)
        }
    }

    public var symbol: String {
        switch self {
        case .agents: "sparkles"
        case .mail: "envelope.fill"
        case .calendar: "calendar"
        case .screenshots: "photo.on.rectangle"
        case .translate: "character.bubble.fill"
        }
    }
}
