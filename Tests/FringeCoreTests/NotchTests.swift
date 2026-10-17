import Foundation
import Testing
@testable import FringeCore

@Test func notchGeometryNeedsAuxiliaryAreas() {
    #expect(NotchGeometry(screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: 664, auxiliaryRightWidth: 663) == NotchGeometry(width: 185, height: 32))
    #expect(NotchGeometry(screenWidth: 1512, safeAreaTop: 0, auxiliaryLeftWidth: 664, auxiliaryRightWidth: 663) == nil)
    #expect(NotchGeometry(screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: nil, auxiliaryRightWidth: 663) == nil)
    #expect(NotchGeometry(screenWidth: 1512, safeAreaTop: 32, auxiliaryLeftWidth: 100, auxiliaryRightWidth: 100) == nil)
}

@Test func restingModeHidesOnlyWhenNothingToShow() {
    #expect(NotchPolicy.restingMode(agents: .idle, unreadMail: 0, autoHide: true) == .hidden)
    #expect(NotchPolicy.restingMode(agents: .idle, unreadMail: 2, autoHide: true) == .compact)
    #expect(NotchPolicy.restingMode(agents: .working(1), unreadMail: 0, autoHide: true) == .compact)
    #expect(NotchPolicy.restingMode(agents: .idle, unreadMail: 0, autoHide: false) == .compact)
}

@Test func hoverAndPinOpenThePanel() {
    #expect(NotchPolicy.mode(resting: .hidden, hovering: true, pinnedOpen: false, peeking: true) == .expanded)
    #expect(NotchPolicy.mode(resting: .hidden, hovering: false, pinnedOpen: true, peeking: false) == .expanded)
    #expect(NotchPolicy.mode(resting: .compact, hovering: false, pinnedOpen: false, peeking: true) == .peek)
    #expect(NotchPolicy.mode(resting: .compact, hovering: false, pinnedOpen: false, peeking: false) == .compact)
    #expect(!NotchPolicy.closesOnHoverExit(editing: true))
}

@Test func durationIsLocalized() {
    let start = Date(timeIntervalSince1970: 0)
    #expect(NotchPolicy.duration(since: start, now: start.addingTimeInterval(42), language: .english) == "42s")
    #expect(NotchPolicy.duration(since: start, now: start.addingTimeInterval(3_900), language: .russian) == "1 ч 5 мин")
}

@Test func preferencesKeepDefaultsForMissingKeys() throws {
    let old = try JSONDecoder().decode(FringePreferences.self, from: Data(#"{"sound":false}"#.utf8))
    #expect(old.sound == false)
    #expect(old.autoHide == true)
    #expect(old.translateShortcut == .defaultTranslate)
    #expect(old.lastTab == .agents)
}

@Test func preferencesSurviveUnknownTabAndDisabledShortcut() throws {
    var preferences = FringePreferences()
    preferences.translateShortcut = nil
    let data = try JSONEncoder().encode(preferences)
    #expect(try JSONDecoder().decode(FringePreferences.self, from: data).translateShortcut == nil)
    let unknownTab = try JSONDecoder().decode(FringePreferences.self, from: Data(#"{"lastTab":"weather"}"#.utf8))
    #expect(unknownTab.lastTab == .agents)
}

@Test func shortcutNeedsAModifier() {
    #expect(KeyCombo.defaultTranslate.isValid)
    #expect(KeyCombo.defaultTranslate.display == "⌃⌥T")
    #expect(!KeyCombo(keyCode: 17, key: "t", modifiers: [.shift]).isValid)
}
