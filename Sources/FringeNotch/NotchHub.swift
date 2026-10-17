import Combine
import SwiftUI
import FringeCore

/// A feature tab. The panel asks for the view only while the tab is open, so a closed tab
/// keeps no view tree; background work (a mail connection) belongs to the module itself.
@MainActor public protocol FringeTabModule: AnyObject {
    var tab: FringeTab { get }
    /// Starts background work; called once after launch.
    func start(hub: NotchHub)
    /// Built each time the tab becomes visible.
    func makeView() -> AnyView
    /// A section for the Settings window, if the tab has settings.
    func makeSettingsView() -> AnyView?
    /// The tab became visible or hidden (panel opened/closed or another tab selected).
    func visibilityChanged(_ visible: Bool)
}

public extension FringeTabModule {
    func start(hub: NotchHub) {}
    func makeSettingsView() -> AnyView? { nil }
    func visibilityChanged(_ visible: Bool) {}
}

/// What modules tell the panel: counters for the strip and announcements for the peek queue.
@MainActor public final class NotchHub: ObservableObject {
    @Published public var agents = AgentSummary.idle
    @Published public var unreadMail = 0
    /// Small counters on the tab bar.
    @Published public var badges: [FringeTab: Int] = [:]
    /// Changes when the panel opens on a tab by shortcut, so the tab can focus its input.
    @Published public private(set) var focusRequest = 0

    var onPost: (PeekEvent) -> Void = { _ in }
    var onRetract: (String) -> Void = { _ in }
    var onClose: () -> Void = {}

    public init() {}

    /// Queues an announcement; sound and notification follow the user's settings.
    public func post(_ event: PeekEvent) { onPost(event) }
    /// Withdraws an announcement that no longer applies (a request answered elsewhere).
    public func retract(id: String) { onRetract(id) }
    /// Closes the panel, e.g. after an action that opens another app.
    public func closePanel() { onClose() }

    func requestFocus() { focusRequest &+= 1 }
}
