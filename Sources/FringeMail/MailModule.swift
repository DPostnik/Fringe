import SwiftUI
import FringeCore
import FringeNotch

/// The Mail tab: unseen Gmail messages over one IMAP IDLE connection.
@MainActor public final class MailModule: FringeTabModule {
    public let tab = FringeTab.mail
    let model: MailModel

    public init() { model = MailModel() }

    public func start(hub: NotchHub) { model.start(hub: hub) }

    public func makeView() -> AnyView { AnyView(MailTabView(model: model)) }

    public func makeSettingsView() -> AnyView? { AnyView(MailSettingsView(model: model)) }
}
