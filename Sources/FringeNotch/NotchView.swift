import SwiftUI
import FringeCore

/// The black panel drawn over the notch: counters at rest, tabs when open.
struct NotchView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var hub: NotchHub

    init(state: NotchState) {
        self.state = state
        hub = state.hub
    }

    var body: some View {
        VStack(spacing: 0) {
            island
            Spacer(minLength: 0)
        }
        .frame(width: NotchController.panelSize.width, height: NotchController.panelSize.height, alignment: .top)
    }

    private var island: some View {
        let expanded = state.mode == .expanded
        return VStack(spacing: 0) {
            header
            if state.mode == .peek, let peek = state.peek {
                PeekLine(event: peek)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if expanded {
                HStack(alignment: .top, spacing: FringeMetrics.railGap) {
                    TabRail(state: state, hub: hub)
                    page
                }
                .padding(.leading, 10).padding(.trailing, FringeMetrics.pageInset).padding(.top, 4).padding(.bottom, FringeMetrics.pageInset)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: width, height: expanded ? NotchController.expandedSize.height : nil)
        .background(Color.black, in: UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
        .opacity(state.mode == .hidden ? 0 : 1)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.mode)
    }

    /// Every tab gets the same frame: a title row with the tab's own controls on the right, then
    /// its content in a fixed area. Only the open tab has a view; switching or closing drops it.
    private var page: some View {
        VStack(alignment: .leading, spacing: FringeMetrics.spacing) {
            HStack(spacing: 8) {
                Text(state.tab.title()).font(FringeMetrics.titleFont).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                state.modules[state.tab]?.makeHeaderAccessory()
                    .font(FringeMetrics.captionFont).foregroundStyle(.white.opacity(0.6))
            }
            .frame(height: FringeMetrics.titleHeight)
            if let module = state.modules[state.tab] {
                module.makeView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .id(state.tab)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var width: CGFloat {
        let notch = state.notch.width, wing = NotchController.wing
        return switch state.mode {
        case .hidden: notch
        case .compact: notch + wing * 2
        case .peek: notch + wing * 2 + 120
        case .expanded: NotchController.expandedSize.width
        }
    }
    private var radius: CGFloat { state.mode == .expanded ? 22 : state.mode == .peek ? 16 : 10 }

    /// The band beside the cut-out; nothing is drawn under the notch itself.
    private var header: some View {
        let expanded = state.mode == .expanded
        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                DeskBuddy(summary: hub.agents, size: expanded ? 20 : 17, celebratedAt: state.celebratedAt,
                          look: state.look, paused: state.mode == .hidden)
                if !expanded, !hub.agents.isIdle { AgentCount(summary: hub.agents) }
            }
            .frame(maxWidth: .infinity, alignment: expanded ? .leading : .center)
            Color.clear.frame(width: state.notch.width)
            HStack(spacing: 4) {
                if expanded {
                    Button { state.onOpenSettings() } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).help(L10n.text("Настройки", "Settings"))
                } else if hub.unreadMail > 0 {
                    Image(systemName: "envelope.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                    Text("\(hub.unreadMail)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.9)).contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: expanded ? .trailing : .center)
        }
        .padding(.horizontal, expanded ? 18 : 6)
        .frame(height: state.notch.height)
    }
}

/// The tabs as a column of icons on the left; the name shows on hover.
private struct TabRail: View {
    @ObservedObject var state: NotchState
    @ObservedObject var hub: NotchHub

    var body: some View {
        VStack(spacing: 6) {
            ForEach(state.tabs, id: \.self) { tab in
                let selected = state.tab == tab
                Button { state.onSelectTab(tab) } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
                        .frame(width: FringeMetrics.railWidth, height: FringeMetrics.railWidth)
                        .background(.white.opacity(selected ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            if let badge = hub.badges[tab], badge > 0 {
                                Text(badge > 99 ? "99+" : "\(badge)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
                                    .foregroundStyle(tab == .agents ? Color.black : Color.white)
                                    .fixedSize()
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(tab == .agents ? Color.orange : Color(white: 0.35), in: Capsule())
                                    .offset(x: 3, y: -2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title())
            }
            Spacer(minLength: 0)
        }
        .frame(width: FringeMetrics.railWidth)
    }
}

private struct AgentCount: View {
    let summary: AgentSummary
    var body: some View {
        Text("\(summary.count)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit()
            .foregroundStyle(color).contentTransition(.numericText())
    }
    private var color: Color {
        switch summary {
        case .waiting: .orange
        case .finished: .green
        default: .white.opacity(0.85)
        }
    }
}

private struct PeekLine: View {
    let event: PeekEvent
    var body: some View {
        HStack(spacing: 6) {
            Text(event.title).foregroundStyle(color).fontWeight(.semibold).lineLimit(1)
            Text(event.detail).foregroundStyle(.white.opacity(0.9)).lineLimit(1).truncationMode(.tail)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14).frame(height: 30)
    }
    private var color: Color {
        switch event.kind {
        case .agentRequest: .orange
        case .agentDone: .green
        case .mail: .white
        }
    }
}
