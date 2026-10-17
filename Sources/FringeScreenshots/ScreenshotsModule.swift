import SwiftUI
import FringeCore
import FringeNotch

/// The Screenshots tab: the latest captures from the system screenshot folder.
@MainActor public final class ScreenshotsModule: FringeTabModule {
    public let tab = FringeTab.screenshots
    private let store = ScreenshotStore()
    private let thumbnails = ThumbnailCache()
    private weak var hub: NotchHub?

    public init() {}

    public func start(hub: NotchHub) { self.hub = hub }

    public func makeView() -> AnyView {
        AnyView(ScreenshotsView(store: store, thumbnails: thumbnails) { [weak self] in self?.hub?.closePanel() })
    }

    /// The Spotlight query lives only while the tab is on screen.
    public func visibilityChanged(_ visible: Bool) {
        if visible { store.start() } else { store.stop() }
    }
}
