import SwiftUI
import FringeCore
import FringeNotch

/// The Translate tab. Placeholder until its stage is implemented.
@MainActor public final class TranslateModule: FringeTabModule {
    public let tab = FringeTab.translate
    public init() {}
    public func makeView() -> AnyView {
        AnyView(FringeEmptyState(symbol: tab.symbol, message: L10n.text("Скоро", "Coming soon")))
    }
}
