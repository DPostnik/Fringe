import SwiftUI
import FringeCore
import FringeNotch

/// The Screenshots tab. Placeholder until its stage is implemented.
@MainActor public final class ScreenshotsModule: FringeTabModule {
    public let tab = FringeTab.screenshots
    public init() {}
    public func makeView() -> AnyView {
        AnyView(FringeEmptyState(symbol: tab.symbol, message: L10n.text("Скоро", "Coming soon")))
    }
}
