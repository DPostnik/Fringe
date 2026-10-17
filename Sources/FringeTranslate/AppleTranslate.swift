import Foundation
import NaturalLanguage
import SwiftUI
import Translation

/// Offline translation through Apple's Translation framework. Nothing is downloaded from here:
/// a pair that is not installed produces `.appleNotInstalled` with instructions.
///
/// macOS 26 creates a session directly with `TranslationSession(installedSource:target:)`.
/// macOS 15 can only get a session from SwiftUI's `.translationTask`, so the tab view hosts
/// `AppleSessionBridge`, which hands each request to the session the modifier provides.
enum AppleTranslate {
    static func translate(text: String, source: String?, target: String, bridge: AppleSessionBridge) async throws(TranslateError) -> AppleTranslation {
        guard let sourceCode = source ?? detectLanguage(of: text) else { throw .appleCannotDetect }
        let sourceLanguage = Locale.Language(identifier: sourceCode)
        let targetLanguage = Locale.Language(identifier: target)
        let ourSource = ourCode(for: sourceLanguage)
        if sourceLanguage.languageCode == targetLanguage.languageCode {
            return AppleTranslation(text: text, source: ourSource)
        }
        switch await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage) {
        case .installed: break
        case .supported: throw .appleNotInstalled(source: ourSource, target: ourCode(for: targetLanguage))
        case .unsupported: throw .appleUnsupported(source: ourSource, target: ourCode(for: targetLanguage))
        @unknown default: break
        }
        do {
            let translated: String
            if #available(macOS 26, *) {
                translated = try await translateInstalled(text, from: sourceLanguage, to: targetLanguage)
            } else {
                translated = try await bridge.translate(text, from: sourceLanguage, to: targetLanguage)
            }
            return AppleTranslation(text: translated, source: ourSource)
        } catch let error as TranslateError {
            throw error
        } catch {
            throw map(error, source: ourSource, target: ourCode(for: targetLanguage))
        }
    }

    @available(macOS 26, *)
    private static func translateInstalled(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        let session = TranslationSession(installedSource: source, target: target)
        return try await session.translate(text).targetText
    }

    /// The dominant language among those the tab offers, so short text is not misread as a rare language.
    static func detectLanguage(of text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = TranslateLanguage.all.map { NLLanguage(rawValue: $0.appleCode) }
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// Maps Apple's language back to the tab's code (e.g. `zh-Hans` → `zh-CN`).
    static func ourCode(for language: Locale.Language) -> String {
        TranslateLanguage.all.first { Locale.Language(identifier: $0.appleCode).languageCode == language.languageCode }?.code
            ?? language.minimalIdentifier
    }

    static func map(_ error: any Error, source: String, target: String) -> TranslateError {
        if error is CancellationError { return .cancelled }
        if TranslationError.unsupportedLanguagePairing ~= error || TranslationError.unsupportedSourceLanguage ~= error
            || TranslationError.unsupportedTargetLanguage ~= error {
            return .appleUnsupported(source: source, target: target)
        }
        if TranslationError.unableToIdentifyLanguage ~= error { return .appleCannotDetect }
        if #available(macOS 26, *) {
            if TranslationError.notInstalled ~= error { return .appleNotInstalled(source: source, target: target) }
            if TranslationError.alreadyCancelled ~= error { return .cancelled }
        }
        return .appleFailed(error.localizedDescription)
    }
}

/// Lends requests to the session that `.translationTask` provides (macOS 15 only).
@MainActor final class AppleSessionBridge: ObservableObject {
    @Published private(set) var configuration: TranslationSession.Configuration?
    private var pending: Pending?
    /// Whether a view with `.translationTask` is on screen to serve requests.
    var attached = false

    private struct Pending {
        let id: UUID
        let text: String
        let continuation: CheckedContinuation<String, any Error>
    }

    func translate(_ text: String, from source: Locale.Language, to target: Locale.Language) async throws -> String {
        guard attached else { throw TranslateError.appleUnavailable }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending?.continuation.resume(throwing: CancellationError())
                pending = Pending(id: id, text: text, continuation: continuation)
                let next = TranslationSession.Configuration(source: source, target: target)
                if configuration == next { configuration?.invalidate() } else { configuration = next }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let pending, pending.id == id else { return }
        self.pending = nil
        pending.continuation.resume(throwing: CancellationError())
    }

    private func take() -> (text: String, finish: @Sendable (Result<String, any Error>) -> Void)? {
        guard let pending else { return nil }
        self.pending = nil
        let continuation = pending.continuation
        return (pending.text, { continuation.resume(with: $0) })
    }

    /// Called from `.translationTask` with the session for the current configuration.
    nonisolated func serve(_ session: SessionBox) async {
        guard let request = await take() else { return }
        do {
            request.finish(.success(try await session.session.translate(request.text).targetText))
        } catch {
            request.finish(.failure(error))
        }
    }
}

/// `TranslationSession` is not Sendable; the framework hands it to the `.translationTask` closure and
/// it is used only inside that call, one request at a time.
struct SessionBox: @unchecked Sendable {
    let session: TranslationSession
}

/// Hosts the macOS 15 bridge; does nothing on macOS 26, where sessions are created directly.
struct AppleSessionHost: ViewModifier {
    @ObservedObject var bridge: AppleSessionBridge

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content
                .translationTask(bridge.configuration) { session in
                    await bridge.serve(SessionBox(session: session))
                }
                .onAppear { bridge.attached = true }
                .onDisappear { bridge.attached = false }
        }
    }
}
