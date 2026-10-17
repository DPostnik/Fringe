import SwiftUI
import FringeCore
import FringeNotch

/// The Mail tab. Placeholder until its stage is implemented.
@MainActor public final class MailModule: FringeTabModule {
    public let tab = FringeTab.mail
    public init() {}
    public func makeView() -> AnyView {
        AnyView(FringeEmptyState(symbol: tab.symbol, message: L10n.text("Скоро", "Coming soon")))
    }
}
