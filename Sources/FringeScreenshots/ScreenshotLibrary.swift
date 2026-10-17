import Foundation
import UniformTypeIdentifiers

/// One screenshot or screen recording found by Spotlight.
public struct ScreenshotItem: Identifiable, Hashable, Sendable {
    public let url: URL
    public let date: Date
    public init(url: URL, date: Date) { self.url = url; self.date = date }

    public var id: String { url.path }
    public var name: String { url.lastPathComponent }
    /// Changes when a file at the same path is replaced, so a cached thumbnail is not reused.
    public var cacheKey: String { "\(url.path)|\(date.timeIntervalSinceReferenceDate)" }
    public var isVideo: Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false }
}

/// Where macOS saves screenshots.
public enum ScreenshotFolder {
    public static let defaultsDomain = "com.apple.screencapture"
    public static let defaultsKey = "location"

    /// The `location` value of `com.apple.screencapture` when it names an existing folder,
    /// otherwise `~/Desktop`, which is what macOS itself falls back to.
    public static func resolve(location: String?, home: URL, isDirectory: (URL) -> Bool) -> URL {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        guard let raw = location?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return desktop }
        let path: String
        if raw == "~" {
            path = home.path
        } else if raw.hasPrefix("~/") {
            path = home.path + "/" + raw.dropFirst(2)
        } else {
            path = raw
        }
        guard path.hasPrefix("/") else { return desktop }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        return isDirectory(url) ? url : desktop
    }

    /// Reads the system setting fresh each time; the user may change it in the Screenshot app.
    public static func current() -> URL {
        let domain = defaultsDomain as CFString
        CFPreferencesAppSynchronize(domain)
        let location = CFPreferencesCopyAppValue(defaultsKey as CFString, domain) as? String
        return resolve(location: location, home: FileManager.default.homeDirectoryForCurrentUser) { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
    }

    public enum Access: Sendable, Equatable { case granted, denied, missing }

    /// Listing the folder triggers the one-time macOS prompt for Desktop/Documents/Downloads.
    /// Blocks while the prompt is shown, so call it off the main thread.
    public static func checkAccess(_ folder: URL) -> Access {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            return .granted
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .denied
        }
    }

    /// A short name for the header: "Desktop", "Screenshots".
    public static func displayName(_ folder: URL) -> String {
        FileManager.default.displayName(atPath: folder.path)
    }
}

/// A Spotlight result reduced to what the grid needs.
public struct ScreenshotRecord: Sendable {
    public var path: String?
    public var date: Date?
    public init(path: String?, date: Date?) { self.path = path; self.date = date }
}

public enum ScreenshotList {
    public static let limit = 30

    /// The newest `limit` captures directly inside `folder`, newest first. Spotlight scopes are
    /// recursive, so captures in subfolders are dropped; records without a path are skipped.
    public static func latest(_ records: [ScreenshotRecord], in folder: URL, limit: Int = ScreenshotList.limit) -> [ScreenshotItem] {
        let folderPath = folder.standardizedFileURL.path
        var seen = Set<String>()
        var items: [ScreenshotItem] = []
        for record in records {
            guard let path = record.path, !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path).standardizedFileURL
            guard url.deletingLastPathComponent().path == folderPath, seen.insert(url.path).inserted else { continue }
            items.append(ScreenshotItem(url: url, date: record.date ?? .distantPast))
        }
        items.sort { lhs, rhs in
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.name > rhs.name
        }
        return Array(items.prefix(max(0, limit)))
    }
}

/// Which image flavor goes to the pasteboard next to the file URL, so pasting works both in
/// apps that take files (Telegram, Slack) and in ones that only take image data (browsers).
public enum ClipboardImageFlavor: Equatable, Sendable {
    case png, tiff, none

    public static func forFile(extension ext: String) -> Self {
        guard let type = UTType(filenameExtension: ext) else { return .none }
        if type.conforms(to: .png) { return .png }
        return type.conforms(to: .image) ? .tiff : .none
    }
}
