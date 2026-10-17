import SwiftUI
import FringeCore
import FringeNotch
import FringeProtocol

/// The Agents tab: chats and requests from Switchboard over the local channel.
@MainActor public final class AgentsModule: FringeTabModule {
    public let tab = FringeTab.agents
    private let link = AgentsLink()
    private weak var hub: NotchHub?

    public init() {}

    public func start(hub: NotchHub) {
        self.hub = hub
        link.onSnapshot = { [weak hub] snapshot, resolved in
            guard let hub else { return }
            hub.agents = AgentsPolicy.summary(snapshot.chats)
            hub.badges[.agents] = snapshot.requests.count
            resolved.forEach { hub.retract(id: AgentsPolicy.requestEventID($0)) }
        }
        link.onAnnounce = { [weak hub] announcement in
            switch announcement.kind {
            case .request:
                hub?.post(PeekEvent(id: AgentsPolicy.requestEventID(announcement.requestID ?? announcement.chatID), kind: .agentRequest,
                                    title: L10n.text("Ждёт тебя", "Needs you"), detail: announcement.chatTitle))
            case .done:
                hub?.post(PeekEvent(id: "agent-done-\(announcement.chatID)-\(Date().timeIntervalSince1970)", kind: .agentDone,
                                    title: L10n.text("Готово", "Done"), detail: announcement.chatTitle))
            }
        }
        link.start()
    }

    public func makeView() -> AnyView {
        AnyView(AgentsView(link: link, onOpenChat: { [weak self] id in
            self?.link.openChat(id)
            self?.hub?.closePanel()
        }))
    }
}
