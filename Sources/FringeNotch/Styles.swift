import SwiftUI

/// The panel's capsule button; `prominent` is the primary action.
public struct FringeButtonStyle: ButtonStyle {
    let prominent: Bool
    public init(prominent: Bool) { self.prominent = prominent }
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? .black : .white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(prominent ? Color.white : Color.white.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(Capsule())
    }
}

/// A rounded row or card on the black panel.
public struct FringeCard: ViewModifier {
    var highlighted: Bool
    public func body(content: Content) -> some View {
        content.background(.white.opacity(highlighted ? 0.11 : 0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

public extension View {
    func fringeCard(highlighted: Bool = false) -> some View { modifier(FringeCard(highlighted: highlighted)) }
}

/// Centered note for an empty or unavailable tab, with an optional action.
public struct FringeEmptyState: View {
    let symbol: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    public init(symbol: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol; self.message = message; self.actionTitle = actionTitle; self.action = action
    }

    public var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
            Text(message).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(FringeButtonStyle(prominent: true))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(16)
    }
}
