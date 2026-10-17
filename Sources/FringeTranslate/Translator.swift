import Foundation
import FringeCore

/// Everything that can go wrong; each case has user-facing copy.
public enum TranslateError: Error, Equatable, Sendable {
    case textTooLong(limit: Int)
    case network(String)
    case http(Int)
    case unexpectedFormat
    case emptyResult
    case cancelled
    case appleNotInstalled(source: String, target: String)
    case appleUnsupported(source: String, target: String)
    case appleCannotDetect
    /// The offline engine needs the tab to be open on macOS 15.
    case appleUnavailable
    case appleFailed(String)

    /// Google failures that Apple may still be able to cover.
    public var allowsFallback: Bool {
        switch self {
        case .network, .http, .unexpectedFormat, .emptyResult, .textTooLong: true
        default: false
        }
    }

    public var message: String {
        switch self {
        case .textTooLong(let limit):
            L10n.text("Текст длиннее \(limit) символов.", "The text is longer than \(limit) characters.")
        case .network(let detail):
            L10n.text("Google недоступен: \(detail)", "Google is unreachable: \(detail)")
        case .http(429):
            L10n.text("Google временно ограничил запросы (HTTP 429).", "Google is rate limiting requests (HTTP 429).")
        case .http(let code):
            L10n.text("Google ответил ошибкой HTTP \(code).", "Google returned HTTP \(code).")
        case .unexpectedFormat:
            L10n.text("Google вернул ответ в неожиданном формате.", "Google returned an unexpected response.")
        case .emptyResult:
            L10n.text("Google вернул пустой перевод.", "Google returned an empty translation.")
        case .cancelled:
            L10n.text("Перевод отменён.", "Translation cancelled.")
        case .appleNotInstalled(let source, let target):
            L10n.text("Офлайн-языки не скачаны (\(TranslateLanguage.displayName(for: source)) → \(TranslateLanguage.displayName(for: target))). Скачайте их: Системные настройки → Основные → Язык и регион → Языки перевода.",
                      "Offline languages are not downloaded (\(TranslateLanguage.displayName(for: source)) → \(TranslateLanguage.displayName(for: target))). Download them in System Settings → General → Language & Region → Translation Languages.")
        case .appleUnsupported(let source, let target):
            L10n.text("Apple не переводит \(TranslateLanguage.displayName(for: source)) → \(TranslateLanguage.displayName(for: target)).",
                      "Apple cannot translate \(TranslateLanguage.displayName(for: source)) → \(TranslateLanguage.displayName(for: target)).")
        case .appleCannotDetect:
            L10n.text("Apple не смог определить язык. Выберите язык исходного текста.", "Apple could not detect the language. Pick the source language.")
        case .appleUnavailable:
            L10n.text("Офлайн-перевод Apple сейчас недоступен.", "Apple offline translation is unavailable right now.")
        case .appleFailed(let detail):
            L10n.text("Ошибка офлайн-перевода Apple: \(detail)", "Apple offline translation failed: \(detail)")
        }
    }
}

/// A finished translation and the engine that produced it.
public struct TranslationOutput: Equatable, Sendable {
    public var text: String
    /// Set when the source was detected automatically.
    public var detectedSource: String?
    public var engine: TranslateEngine
    /// Why Google was skipped when Apple stood in for it.
    public var googleFailure: TranslateError?
}

/// Both engines failed (or the only one tried did).
public struct TranslationFailure: Error, Equatable, Sendable {
    public var primary: TranslateError
    public var fallback: TranslateError?

    public var message: String {
        guard let fallback else { return primary.message }
        return primary.message + "\n" + fallback.message
    }
}

public struct AppleTranslation: Equatable, Sendable {
    public var text: String
    /// Our code for the source language Apple used.
    public var source: String
}

/// Chooses an engine and falls back from Google to Apple. Engines are injected so the policy is testable.
public struct Translator: Sendable {
    public typealias Google = @Sendable (_ text: String, _ source: String?, _ target: String) async throws(TranslateError) -> GoogleTranslation
    public typealias Apple = @Sendable (_ text: String, _ source: String?, _ target: String) async throws(TranslateError) -> AppleTranslation

    var google: Google
    var apple: Apple

    public init(google: @escaping Google, apple: @escaping Apple) {
        self.google = google; self.apple = apple
    }

    public func translate(_ text: String, pair: LanguagePair, engine: TranslateEngine) async -> Result<TranslationOutput, TranslationFailure> {
        let auto = pair.source == nil
        let googleSource = pair.source
        let appleSource = pair.source.flatMap { TranslateLanguage.find($0)?.appleCode }
        let appleTarget = TranslateLanguage.find(pair.target)?.appleCode ?? pair.target

        func runApple(googleFailure: TranslateError?) async -> Result<TranslationOutput, TranslationFailure> {
            do {
                let result = try await apple(text, appleSource, appleTarget)
                return .success(TranslationOutput(text: result.text, detectedSource: auto ? result.source : nil,
                                                  engine: .apple, googleFailure: googleFailure))
            } catch {
                return .failure(googleFailure.map { TranslationFailure(primary: $0, fallback: error) } ?? TranslationFailure(primary: error))
            }
        }

        if engine == .apple { return await runApple(googleFailure: nil) }
        do {
            let result = try await google(text, googleSource, pair.target)
            return .success(TranslationOutput(text: result.text, detectedSource: auto ? result.detectedSource : nil,
                                              engine: .google, googleFailure: nil))
        } catch {
            guard error.allowsFallback else { return .failure(TranslationFailure(primary: error)) }
            return await runApple(googleFailure: error)
        }
    }
}
