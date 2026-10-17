import SwiftUI
import FringeCore
import FringeNotch

/// The Calendar tab. Placeholder until its stage is implemented.
@MainActor public final class CalendarModule: FringeTabModule {
    public let tab = FringeTab.calendar
    public init() {}
    public func makeView() -> AnyView {
        AnyView(FringeEmptyState(symbol: tab.symbol, message: L10n.text("Скоро", "Coming soon")))
    }
}
