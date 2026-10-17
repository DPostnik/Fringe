import SwiftUI
import FringeCore
import FringeNotch

/// The Translate tab: Google Translate with Apple's offline Translation as fallback.
@MainActor public final class TranslateModule: FringeTabModule {
    public let tab = FringeTab.translate
    private var hub = NotchHub()
    private lazy var model = TranslateModel()

    public init() {}

    public func start(hub: NotchHub) { self.hub = hub }

    public func makeView() -> AnyView {
        AnyView(TranslateView(model: model, hub: hub))
    }

    public func makeSettingsView() -> AnyView? {
        AnyView(TranslateSettingsView(model: model))
    }

    public func visibilityChanged(_ visible: Bool) {
        if visible { model.becameVisible() } else { model.becameHidden() }
    }
}
