import SwiftUI
import FringeCore
import FringeNotch

/// The Mail tab: unseen Gmail messages over one IMAP IDLE connection.
@MainActor public final class MailModule: FringeTabModule {
    public let tab = FringeTab.mail
    let model: MailModel
    private weak var hub: NotchHub?

    public init() { model = MailModel() }

    public func start(hub: NotchHub) {
        self.hub = hub
        model.start(hub: hub)
    }

    public func makeView() -> AnyView { AnyView(MailTabView(model: model, onOpenSettings: { [weak self] in self?.hub?.openSettings() })) }

    public func makeSettingsView() -> AnyView? { AnyView(MailSettingsView(model: model)) }
}
