import Testing
import FringeCore
@testable import FringeTranslate

@MainActor @Test func moduleOwnsItsTab() {
    #expect(TranslateModule().tab == .translate)
}
