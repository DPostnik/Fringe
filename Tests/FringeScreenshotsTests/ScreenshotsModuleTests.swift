import Testing
import FringeCore
@testable import FringeScreenshots

@MainActor @Test func moduleOwnsItsTab() {
    #expect(ScreenshotsModule().tab == .screenshots)
}
