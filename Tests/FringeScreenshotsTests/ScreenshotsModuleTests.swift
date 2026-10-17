import Foundation
import Testing
import FringeCore
@testable import FringeScreenshots

@MainActor @Test func moduleOwnsItsTab() {
    #expect(ScreenshotsModule().tab == .screenshots)
}

// MARK: Folder resolution

private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
private let desktop = "/Users/tester/Desktop"

private func resolve(_ location: String?, existing: Set<String> = []) -> String {
    ScreenshotFolder.resolve(location: location, home: home) { existing.contains($0.path) }.path
}

@Test func missingOrBlankLocationFallsBackToDesktop() {
    #expect(resolve(nil) == desktop)
    #expect(resolve("") == desktop)
    #expect(resolve("   \n") == desktop)
}

@Test func tildeLocationExpandsToHome() {
    #expect(resolve("~/Pictures/Shots", existing: ["/Users/tester/Pictures/Shots"]) == "/Users/tester/Pictures/Shots")
    #expect(resolve("~", existing: ["/Users/tester"]) == "/Users/tester")
}

@Test func absoluteLocationIsStandardized() {
    #expect(resolve("/Volumes/Data/Shots/", existing: ["/Volumes/Data/Shots"]) == "/Volumes/Data/Shots")
    #expect(resolve(" /Volumes/Data/./Shots ", existing: ["/Volumes/Data/Shots"]) == "/Volumes/Data/Shots")
}

@Test func nonexistentOrRelativeLocationFallsBackToDesktop() {
    #expect(resolve("/Volumes/Gone") == desktop)
    #expect(resolve("Pictures") == desktop)
    #expect(resolve("~other/Pictures", existing: ["~other/Pictures"]) == desktop)
}

@Test func accessCheckReportsMissingFolder() {
    let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
    #expect(ScreenshotFolder.checkAccess(missing) == .missing)
    #expect(ScreenshotFolder.checkAccess(FileManager.default.temporaryDirectory) == .granted)
}

// MARK: Latest list

private let folder = URL(fileURLWithPath: "/Users/tester/Shots", isDirectory: true)

private func record(_ name: String, _ seconds: TimeInterval?, in directory: String = "/Users/tester/Shots") -> ScreenshotRecord {
    ScreenshotRecord(path: directory + "/" + name, date: seconds.map { Date(timeIntervalSinceReferenceDate: $0) })
}

@Test func latestSortsNewestFirst() {
    let items = ScreenshotList.latest([record("a.png", 10), record("c.png", 30), record("b.png", 20)], in: folder)
    #expect(items.map(\.name) == ["c.png", "b.png", "a.png"])
}

@Test func latestKeepsOnlyDirectChildrenOfTheFolder() {
    let records = [
        record("top.png", 1),
        record("nested.png", 5, in: "/Users/tester/Shots/Old"),
        record("elsewhere.png", 9, in: "/Users/tester/Desktop"),
        ScreenshotRecord(path: nil, date: Date()),
        ScreenshotRecord(path: "", date: Date())
    ]
    let items = ScreenshotList.latest(records, in: folder)
    #expect(items.map(\.name) == ["top.png"])
}

@Test func latestDropsDuplicatesAndAppliesLimit() {
    var records = (0..<50).map { record("shot-\($0).png", TimeInterval($0)) }
    records.append(record("shot-49.png", 49))
    let items = ScreenshotList.latest(records, in: folder)
    #expect(items.count == 30)
    #expect(items.first?.name == "shot-49.png")
    #expect(items.last?.name == "shot-20.png")
    let small = ScreenshotList.latest(records, in: folder, limit: 2)
    #expect(small.map(\.name) == ["shot-49.png", "shot-48.png"])
    #expect(ScreenshotList.latest(records, in: folder, limit: -1).isEmpty)
}

@Test func latestPutsUndatedLastAndBreaksTiesByName() {
    let items = ScreenshotList.latest([record("undated.png", nil), record("a.png", 5), record("b.png", 5)], in: folder)
    #expect(items.map(\.name) == ["b.png", "a.png", "undated.png"])
}

@Test func itemFlagsVideosAndKeysCacheByDate() {
    let movie = ScreenshotItem(url: URL(fileURLWithPath: "/x/Recording.mov"), date: Date(timeIntervalSinceReferenceDate: 1))
    let image = ScreenshotItem(url: URL(fileURLWithPath: "/x/Shot.png"), date: Date(timeIntervalSinceReferenceDate: 1))
    let replaced = ScreenshotItem(url: URL(fileURLWithPath: "/x/Shot.png"), date: Date(timeIntervalSinceReferenceDate: 2))
    #expect(movie.isVideo)
    #expect(!image.isVideo)
    #expect(image.cacheKey != replaced.cacheKey)
}

// MARK: Clipboard

@Test func clipboardFlavorFollowsFileType() {
    #expect(ClipboardImageFlavor.forFile(extension: "png") == .png)
    #expect(ClipboardImageFlavor.forFile(extension: "PNG") == .png)
    #expect(ClipboardImageFlavor.forFile(extension: "jpg") == .tiff)
    #expect(ClipboardImageFlavor.forFile(extension: "heic") == .tiff)
    #expect(ClipboardImageFlavor.forFile(extension: "mov") == .none)
    #expect(ClipboardImageFlavor.forFile(extension: "") == .none)
}
