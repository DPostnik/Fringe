import SwiftUI
import FringeCore
import FringeNotch
import FringeProtocol

/// The Agents tab. Placeholder until its stage is implemented.
@MainActor public final class AgentsModule: FringeTabModule {
    public let tab = FringeTab.agents
    public init() {}
    public func makeView() -> AnyView {
        AnyView(FringeEmptyState(symbol: tab.symbol, message: L10n.text("Скоро", "Coming soon")))
    }
}
