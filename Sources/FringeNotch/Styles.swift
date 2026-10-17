import SwiftUI

/// Shared measurements, so every tab has the same rhythm.
public enum FringeMetrics {
    /// Gap between blocks inside a tab and between the title row and the content.
    public static let spacing: CGFloat = 8
    /// Gap between rows of a list.
    public static let rowSpacing: CGFloat = 6
    public static let rowPadding = EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
    public static let cornerRadius: CGFloat = 10
    public static let pageInset: CGFloat = 14
    public static let railWidth: CGFloat = 34
    public static let railGap: CGFloat = 12
    public static let titleHeight: CGFloat = 22
    public static let titleFont = Font.system(size: 15, weight: .semibold)
    public static let rowTitleFont = Font.system(size: 13, weight: .semibold)
    public static let bodyFont = Font.system(size: 12)
    public static let captionFont = Font.system(size: 11, weight: .medium)
}

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
        content.background(.white.opacity(highlighted ? 0.11 : 0.06), in: RoundedRectangle(cornerRadius: FringeMetrics.cornerRadius, style: .continuous))
    }
}

public extension View {
    func fringeCard(highlighted: Bool = false) -> some View { modifier(FringeCard(highlighted: highlighted)) }
    /// A list row: standard padding on a card, full width.
    func fringeRow(highlighted: Bool = false) -> some View {
        padding(FringeMetrics.rowPadding).frame(maxWidth: .infinity, alignment: .leading).fringeCard(highlighted: highlighted)
    }
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
