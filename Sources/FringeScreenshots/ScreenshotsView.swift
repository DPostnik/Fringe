import SwiftUI
import FringeCore
import FringeNotch

struct ScreenshotsView: View {
    @ObservedObject var store: ScreenshotStore
    let thumbnails: ThumbnailCache
    let closePanel: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(spacing: 8) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var folderName: String { ScreenshotFolder.displayName(store.folder) }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 10, weight: .semibold))
            Text(folderName).font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            if let notice = store.notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.orange).lineLimit(1)
            }
            Spacer(minLength: 4)
            if store.status == .ready, !store.items.isEmpty {
                Text("\(store.items.count)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Button {
                ScreenshotActions.openFolder(store.folder); closePanel()
            } label: {
                Image(systemName: "arrow.up.forward.square").font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 20).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Открыть папку в Finder", "Open folder in Finder"))
        }
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var content: some View {
        switch store.status {
        case .idle, .loading:
            if store.items.isEmpty { ProgressView().controlSize(.small) } else { grid }
        case .noAccess:
            FringeEmptyState(
                symbol: "lock.fill",
                message: L10n.text(
                    "Нет доступа к папке «\(folderName)». Разрешите его в Системных настройках: Конфиденциальность и безопасность → Файлы и папки.",
                    "No access to the \(folderName) folder. Allow it in System Settings: Privacy & Security → Files and Folders."),
                actionTitle: L10n.text("Открыть настройки", "Open Settings")
            ) { ScreenshotActions.openPrivacySettings(); closePanel() }
        case .missingFolder:
            FringeEmptyState(symbol: "folder.badge.questionmark",
                             message: L10n.text("Папка «\(folderName)» не найдена.", "The \(folderName) folder wasn't found."))
        case .queryFailed:
            FringeEmptyState(symbol: "exclamationmark.triangle.fill",
                             message: L10n.text("Не удалось запустить поиск Spotlight.", "Couldn't start the Spotlight search."),
                             actionTitle: L10n.text("Повторить", "Retry")) { store.start() }
        case .ready:
            if store.items.isEmpty {
                FringeEmptyState(symbol: "camera.viewfinder",
                                 message: L10n.text("Здесь появятся новые скриншоты.\n⇧⌘4 снимает область, ⇧⌘5 открывает все режимы.",
                                                    "New screenshots will show up here.\n⇧⌘4 captures an area, ⇧⌘5 opens all modes."))
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(store.items) { item in
                    ScreenshotCell(
                        item: item, thumbnails: thumbnails, copied: store.copiedID == item.id,
                        open: { ScreenshotActions.open(item.url); closePanel() },
                        copy: { store.copy(item) },
                        reveal: { ScreenshotActions.reveal(item.url); closePanel() },
                        trash: { store.trash(item) })
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(1)
        }
    }
}

private struct ScreenshotCell: View {
    let item: ScreenshotItem
    let thumbnails: ThumbnailCache
    let copied: Bool
    let open: () -> Void
    let copy: () -> Void
    let reveal: () -> Void
    let trash: () -> Void

    @State private var image: NSImage?
    @State private var hovering = false
    @Environment(\.displayScale) private var displayScale

    private static let height: CGFloat = 70
    private let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        Color.white.opacity(0.06)
            .frame(height: Self.height)
            .overlay { thumbnail }
            .overlay(alignment: .bottomLeading) { if item.isVideo { videoBadge } }
            .overlay { if hovering { hoverChrome } }
            .overlay { if copied { copiedBadge } }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(hovering ? 0.35 : 0.08), lineWidth: 1))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .animation(.easeOut(duration: 0.15), value: copied)
            .onTapGesture(perform: open)
            .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL) }
            .contextMenu {
                Button(L10n.text("Открыть", "Open"), action: open)
                Button(L10n.text("Скопировать", "Copy"), action: copy)
                Button(L10n.text("Показать в Finder", "Show in Finder"), action: reveal)
                Divider()
                Button(L10n.text("Переместить в Корзину", "Move to Trash"), role: .destructive, action: trash)
            }
            .help(item.name)
            .task(id: item.cacheKey) {
                image = thumbnails.cached(item)
                if image == nil {
                    image = await thumbnails.thumbnail(for: item, size: CGSize(width: 220, height: 150), scale: displayScale)
                }
            }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image {
            Image(nsImage: image).resizable().interpolation(.medium).scaledToFill()
        } else {
            Image(systemName: item.isVideo ? "film" : "photo").font(.system(size: 16)).foregroundStyle(.white.opacity(0.25))
        }
    }

    private var videoBadge: some View {
        Image(systemName: "video.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            .padding(4).background(.black.opacity(0.6), in: Circle()).padding(5)
    }

    private var hoverChrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text(relativeDate).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                CellAction(symbol: "doc.on.doc", help: L10n.text("Скопировать", "Copy"), action: copy)
                CellAction(symbol: "magnifyingglass", help: L10n.text("Показать в Finder", "Show in Finder"), action: reveal)
                CellAction(symbol: "trash", help: L10n.text("В Корзину", "Move to Trash"), action: trash)
            }
            .padding(2)
            .background(.black.opacity(0.65), in: Capsule())
        }
        .padding(5)
        .background(LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
        .transition(.opacity)
    }

    private var copiedBadge: some View {
        ZStack {
            Color.black.opacity(0.55)
            Label(L10n.text("Скопировано", "Copied"), systemImage: "checkmark")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
        }
        .transition(.opacity)
    }

    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.date, relativeTo: Date())
    }
}

private struct CellAction: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(hovering ? 1 : 0.8))
                .frame(width: 22, height: 18)
                .background(.white.opacity(hovering ? 0.2 : 0), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
