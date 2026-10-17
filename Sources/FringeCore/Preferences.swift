import Foundation

/// A global shortcut: a virtual key code with Carbon-independent modifier flags.
public struct KeyCombo: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let command = Self(rawValue: 1 << 0)
        public static let option = Self(rawValue: 1 << 1)
        public static let control = Self(rawValue: 1 << 2)
        public static let shift = Self(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    /// The character printed on the key, captured when recorded; used only for display.
    public var key: String
    public var modifiers: Modifiers
    public init(keyCode: UInt32, key: String, modifiers: Modifiers) {
        self.keyCode = keyCode; self.key = key; self.modifiers = modifiers
    }

    /// ⌃⌥T: free in common apps and easy to reach with one hand.
    public static let defaultTranslate = KeyCombo(keyCode: 17, key: "T", modifiers: [.control, .option])

    /// A shortcut without ⌘, ⌥ or ⌃ would swallow ordinary typing.
    public var isValid: Bool { !modifiers.intersection([.command, .option, .control]).isEmpty }

    public var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key.uppercased()
    }
}

/// App-wide settings. Feature tabs keep their own settings under their own keys.
public struct FringePreferences: Codable, Equatable, Sendable {
    /// Hide the strip while no agent is active and no mail is unread.
    public var autoHide = true
    public var sound = true
    public var systemNotifications = false
    public var lastTab = FringeTab.agents
    /// Nil turns the translate shortcut off.
    public var translateShortcut: KeyCombo? = .defaultTranslate

    public init() {}

    private enum CodingKeys: String, CodingKey { case autoHide, sound, systemNotifications, lastTab, translateShortcut }
    /// Values saved before a key existed keep their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        autoHide = try container.decodeIfPresent(Bool.self, forKey: .autoHide) ?? defaults.autoHide
        sound = try container.decodeIfPresent(Bool.self, forKey: .sound) ?? defaults.sound
        systemNotifications = try container.decodeIfPresent(Bool.self, forKey: .systemNotifications) ?? defaults.systemNotifications
        // A tab removed in a later version falls back to the first one.
        lastTab = (try? container.decodeIfPresent(FringeTab.self, forKey: .lastTab)) ?? defaults.lastTab
        if container.contains(.translateShortcut) {
            translateShortcut = try container.decodeIfPresent(KeyCombo.self, forKey: .translateShortcut)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(autoHide, forKey: .autoHide)
        try container.encode(sound, forKey: .sound)
        try container.encode(systemNotifications, forKey: .systemNotifications)
        try container.encode(lastTab, forKey: .lastTab)
        // Encoded explicitly as null so "off" survives a reload instead of turning back into the default.
        try container.encode(translateShortcut, forKey: .translateShortcut)
    }

    public static let defaultsKey = "fringePreferences"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
