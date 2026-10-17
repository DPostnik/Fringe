import SwiftUI
import FringeCore
import FringeNotch
import FringeProtocol

struct AgentsView: View {
    @ObservedObject var link: AgentsLink
    let onOpenChat: (String) -> Void

    var body: some View {
        switch link.status {
        case .notRunning:
            FringeEmptyState(symbol: "sparkles", message: L10n.text("Switchboard не запущен", "Switchboard is not running"),
                             actionTitle: L10n.text("Запустить", "Open"), action: link.launchSwitchboard)
        case .connecting:
            FringeEmptyState(symbol: "bolt.horizontal", message: L10n.text("Подключение к Switchboard…", "Connecting to Switchboard…"))
        case .incompatible(let detail):
            FringeEmptyState(symbol: "exclamationmark.triangle",
                             message: L10n.text("Версии Fringe и Switchboard несовместимы (\(detail)). Обнови оба приложения.",
                                                "Fringe and Switchboard versions are incompatible (\(detail)). Update both apps."))
        case .connected:
            if link.snapshot.chats.isEmpty {
                FringeEmptyState(symbol: "moon.zzz", message: L10n.text("Сейчас агенты не работают", "No agents are working right now"))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(link.snapshot.chats) { chat in
                            ChatRow(chat: chat, requests: link.snapshot.requests.filter { $0.chatID == chat.id }, link: link, onOpenChat: onOpenChat)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct ChatRow: View {
    let chat: FringeChat
    let requests: [FringeRequest]
    @ObservedObject var link: AgentsLink
    let onOpenChat: (String) -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { onOpenChat(chat.id) } label: {
                HStack(alignment: .top, spacing: 10) {
                    StatusMark(phase: chat.phase).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chat.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(subtitle(now: context.date)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.forward").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(hovered ? 0.7 : 0)).padding(.top, 3)
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Открыть чат", "Open chat"))
            ForEach(requests) { request in RequestCard(request: request, link: link, onOpenChat: onOpenChat) }
        }
        .padding(FringeMetrics.rowPadding)
        .fringeCard(highlighted: hovered)
        .onHover { hovered = $0 }
    }

    private func subtitle(now: Date) -> String {
        var parts = [chat.project].filter { !$0.isEmpty }
        switch chat.phase {
        case .waiting: parts.append(L10n.text("ждёт ответа", "waiting for you"))
        case .finished: parts.append(L10n.text("готово", "done"))
        case .working:
            parts.append(chat.activity ?? L10n.text("работает", "working"))
            if let since = chat.since { parts.append(NotchPolicy.duration(since: since, now: now)) }
        }
        return parts.joined(separator: " · ")
    }
}

private struct StatusMark: View {
    let phase: FringeChat.Phase
    var body: some View {
        Group {
            switch phase {
            case .working: ProgressView().controlSize(.mini).tint(.cyan)
            case .waiting: Circle().fill(.orange).frame(width: 8, height: 8)
            case .finished: Image(systemName: "checkmark.circle.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(.green)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// A pending request. Approvals can be answered in place when Switchboard supports it; the answer
/// is sent once and a lost connection asks the user to check the chat instead of resending.
private struct RequestCard: View {
    let request: FringeRequest
    @ObservedObject var link: AgentsLink
    let onOpenChat: (String) -> Void
    @State private var showingDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let reason = request.reason, !reason.isEmpty {
                Text(reason).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9)).lineLimit(4)
            } else {
                Text(request.title).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
            if !request.details.isEmpty {
                ScrollView {
                    Text(request.details).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: showingDetails ? 160 : 48)
                .padding(8).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showingDetails.toggle() } }
            }
            switch link.answers[request.id] {
            case .unknown:
                Text(L10n.text("Связь прервалась, ответ мог не дойти. Проверь в чате.", "The connection dropped; the answer may not have arrived. Check the chat."))
                    .font(.system(size: 11)).foregroundStyle(.orange)
            case .failed(let message):
                Text(message).font(.system(size: 11)).foregroundStyle(.red)
            case .sending, nil:
                EmptyView()
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if request.kind == .approval, link.canAnswer, link.answers[request.id] == nil || link.answers[request.id] == .sending {
                    Button(L10n.text("Отклонить", "Decline")) { link.answer(request, .deny) }
                        .buttonStyle(FringeButtonStyle(prominent: false))
                    if request.canAllow {
                        Button(L10n.text("Разрешить один раз", "Allow once")) { link.answer(request, .allowOnce) }
                            .buttonStyle(FringeButtonStyle(prominent: true))
                    }
                } else {
                    Button(L10n.text("Ответить в чате", "Answer in chat")) { onOpenChat(request.chatID) }
                        .buttonStyle(FringeButtonStyle(prominent: true))
                }
            }
            .disabled(link.answers[request.id] == .sending)
        }
    }
}
