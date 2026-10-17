import Testing
@testable import FringeProtocol

@Test func versionIsPinned() {
    #expect(FringeProtocol.version == 1)
}
