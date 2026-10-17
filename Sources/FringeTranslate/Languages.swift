import Foundation
import FringeCore

/// A language the tab offers. `code` is Google's code; `appleCode` is the BCP 47 identifier
/// Apple Translation expects (they differ only for Chinese).
public struct TranslateLanguage: Hashable, Sendable, Identifiable {
    public let code: String
    public let appleCode: String
    let russianName: String
    let englishName: String
    public var id: String { code }

    init(_ code: String, apple: String? = nil, _ russianName: String, _ englishName: String) {
        self.code = code; self.appleCode = apple ?? code
        self.russianName = russianName; self.englishName = englishName
    }

    public func name(language: AppLanguage = L10n.language) -> String {
        L10n.text(russianName, englishName, language: language)
    }

    /// A curated list of common languages, in menu order.
    public static let all: [TranslateLanguage] = [
        .init("ru", "Русский", "Russian"),
        .init("en", "Английский", "English"),
        .init("uk", "Украинский", "Ukrainian"),
        .init("de", "Немецкий", "German"),
        .init("fr", "Французский", "French"),
        .init("es", "Испанский", "Spanish"),
        .init("it", "Итальянский", "Italian"),
        .init("pt", "Португальский", "Portuguese"),
        .init("pl", "Польский", "Polish"),
        .init("nl", "Нидерландский", "Dutch"),
        .init("cs", "Чешский", "Czech"),
        .init("tr", "Турецкий", "Turkish"),
        .init("zh-CN", apple: "zh-Hans", "Китайский", "Chinese"),
        .init("ja", "Японский", "Japanese"),
        .init("ko", "Корейский", "Korean"),
        .init("ar", "Арабский", "Arabic"),
        .init("hi", "Хинди", "Hindi"),
        .init("vi", "Вьетнамский", "Vietnamese"),
        .init("th", "Тайский", "Thai"),
        .init("id", "Индонезийский", "Indonesian"),
    ]

    public static func find(_ code: String) -> TranslateLanguage? {
        all.first { $0.code == code } ?? all.first { $0.appleCode == code }
    }

    /// A display name for any code, including ones Google detects outside the curated list.
    public static func displayName(for code: String, language: AppLanguage = L10n.language) -> String {
        if let known = find(code) ?? find(String(code.prefix { $0 != "-" && $0 != "_" })) {
            return known.name(language: language)
        }
        return language.locale.localizedString(forIdentifier: code)?.capitalized(with: language.locale) ?? code
    }
}

/// The remembered "from → to" choice. `source == nil` means automatic detection.
public struct LanguagePair: Codable, Equatable, Sendable {
    public var source: String?
    public var target: String

    public init(source: String?, target: String) {
        self.source = source; self.target = target
    }

    /// Detect the source and translate into the interface language.
    public static func standard(for language: AppLanguage = L10n.language) -> Self {
        Self(source: nil, target: language.rawValue)
    }

    /// Swaps the sides. With automatic detection the detected language becomes the target;
    /// if nothing was detected yet, the old target becomes the source and the other of ru/en the target.
    public func swapped(detected: String?) -> Self {
        if let source { return Self(source: target, target: source) }
        if let detected, let language = TranslateLanguage.find(detected), language.code != target {
            return Self(source: target, target: language.code)
        }
        return Self(source: target, target: target == "en" ? "ru" : "en")
    }

    static let defaultsKey = "translate.languagePair"

    /// Unknown or broken stored values fall back to the default pair.
    public static func load(from defaults: UserDefaults = .standard, language: AppLanguage = L10n.language) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let pair = try? JSONDecoder().decode(Self.self, from: data),
              pair.isValid else { return standard(for: language) }
        return pair
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }

    var isValid: Bool {
        TranslateLanguage.find(target) != nil && (source.map { TranslateLanguage.find($0) != nil } ?? true)
    }
}
