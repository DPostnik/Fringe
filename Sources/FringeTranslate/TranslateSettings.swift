import Foundation
import FringeCore

public enum TranslateEngine: String, Codable, CaseIterable, Sendable {
    case google
    case apple

    public var title: String {
        switch self {
        case .google: "Google"
        case .apple: L10n.text("Apple (офлайн)", "Apple (offline)")
        }
    }
}

/// The tab's own settings, stored under its own key.
public struct TranslateSettings: Codable, Equatable, Sendable {
    /// Put the clipboard text into the input when the tab opens.
    public var prefillFromClipboard = false
    public var engine = TranslateEngine.google

    public init() {}

    private enum CodingKeys: String, CodingKey { case prefillFromClipboard, engine }
    /// Missing or unknown values keep their defaults.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        prefillFromClipboard = (try? container.decodeIfPresent(Bool.self, forKey: .prefillFromClipboard)) ?? defaults.prefillFromClipboard
        engine = (try? container.decodeIfPresent(TranslateEngine.self, forKey: .engine)) ?? defaults.engine
    }

    static let defaultsKey = "translate.settings"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } ?? Self()
    }
    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
