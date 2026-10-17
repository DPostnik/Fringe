import AppKit
import Combine
import FringeCore
import SwiftUI

/// Live list of the latest screenshots. The Spotlight query runs only while the tab is visible.
@MainActor final class ScreenshotStore: ObservableObject {
    enum Status: Equatable { case idle, loading, ready, noAccess, missingFolder, queryFailed }

    @Published private(set) var status: Status = .idle
    @Published private(set) var items: [ScreenshotItem] = []
    @Published private(set) var folder: URL = ScreenshotFolder.current()
    /// Briefly marks the item just copied.
    @Published private(set) var copiedID: String?
    /// A short failure note (trash failed), cleared by the next action.
    @Published var notice: String?

    private var query: NSMetadataQuery?
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    private var copiedReset: Task<Void, Never>?

    func start() {
        stop()
        let token = generation
        let folder = ScreenshotFolder.current()
        if folder != self.folder { items = [] }
        self.folder = folder
        if items.isEmpty { status = .loading }
        Task {
            let access = await Task.detached(priority: .userInitiated) { ScreenshotFolder.checkAccess(folder) }.value
            guard token == self.generation else { return }
            switch access {
            case .granted: self.startQuery(in: folder)
            case .denied: self.items = []; self.status = .noAccess
            case .missing: self.items = []; self.status = .missingFolder
            }
        }
    }

    func stop() {
        generation &+= 1
        query?.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        query = nil
    }

    private func startQuery(in folder: URL) {
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [folder]
        query.notificationBatchingInterval = 0.3
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        self.query = query
        if !query.start() {
            stop()
            items = []
            status = .queryFailed
        }
    }

    private func refresh() {
        guard let query else { return }
        query.disableUpdates()
        var records: [ScreenshotRecord] = []
        records.reserveCapacity(query.resultCount)
        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem else { continue }
            let date = item.value(forAttribute: NSMetadataItemContentCreationDateKey) as? Date
                ?? item.value(forAttribute: NSMetadataItemFSCreationDateKey) as? Date
            records.append(ScreenshotRecord(path: item.value(forAttribute: NSMetadataItemPathKey) as? String, date: date))
        }
        query.enableUpdates()
        let latest = ScreenshotList.latest(records, in: folder.resolvingSymlinksInPath())
        if latest != items { items = latest }
        status = .ready
    }

    // MARK: Actions

    func copy(_ item: ScreenshotItem) {
        notice = nil
        ScreenshotActions.copy(item.url)
        copiedID = item.id
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.copiedID = nil
        }
    }

    func trash(_ item: ScreenshotItem) {
        notice = nil
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            withAnimation(.easeOut(duration: 0.2)) { items.removeAll { $0.id == item.id } }
        } catch {
            notice = L10n.text("Не удалось переместить в Корзину", "Couldn't move to Trash")
        }
    }
}

/// System actions on a screenshot file.
@MainActor enum ScreenshotActions {
    static func open(_ url: URL) { NSWorkspace.shared.open(url) }

    static func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    static func openFolder(_ url: URL) { NSWorkspace.shared.open(url) }

    /// Files and Folders privacy pane, where Desktop access is granted after a denial.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Puts the file URL and, for images, the image data on one pasteboard item.
    static func copy(_ url: URL) {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        switch ClipboardImageFlavor.forFile(extension: url.pathExtension) {
        case .png:
            if let data = try? Data(contentsOf: url) { item.setData(data, forType: .png) }
        case .tiff:
            if let tiff = NSImage(contentsOf: url)?.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        case .none:
            break
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }
}
