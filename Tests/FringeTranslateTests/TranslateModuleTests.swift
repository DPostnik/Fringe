import Foundation
import Testing
import FringeCore
@testable import FringeTranslate

@MainActor @Test func moduleOwnsItsTab() {
    #expect(TranslateModule().tab == .translate)
}

// MARK: Google response parser

private func data(_ json: String) -> Data { Data(json.utf8) }

/// Captured from a real `sl=auto&tl=en` request on 2026-10-17.
private let multiSentence = #"[[["Hello World. ","Привет, мир. ",null,null,10],["How are you? ","Как дела? ",null,null,10],["Everything is fine.","Всё хорошо.",null,null,10]],null,"ru",null,null,null,1,[],[["ru"],null,[1],["ru"]]]"#

@Test func parsesSingleSegment() throws {
    let result = try GoogleTranslateAPI.parse(data(#"[[["Hallo","Hello",null,null,10]],null,"en",null,null,null,null,[]]"#))
    #expect(result == GoogleTranslation(text: "Hallo", detectedSource: "en"))
}

@Test func joinsSentencesInOrder() throws {
    let result = try GoogleTranslateAPI.parse(data(multiSentence))
    #expect(result.text == "Hello World. How are you? Everything is fine.")
    #expect(result.detectedSource == "ru")
}

@Test func readsDetectedLanguageWithRegion() throws {
    let result = try GoogleTranslateAPI.parse(data(#"[[["Hello","你好",null,null,10]],null,"zh-CN"]"#))
    #expect(result.detectedSource == "zh-CN")
    #expect(TranslateLanguage.displayName(for: "zh-CN", language: .english) == "Chinese")
}

@Test func missingDetectedLanguageIsAllowed() throws {
    let short = try GoogleTranslateAPI.parse(data(#"[[["Hallo","Hello"]]]"#))
    #expect(short.detectedSource == nil)
    let null = try GoogleTranslateAPI.parse(data(#"[[["Hallo","Hello"]],null,null]"#))
    #expect(null.detectedSource == nil)
}

@Test func skipsSegmentsWithoutTranslation() throws {
    let result = try GoogleTranslateAPI.parse(data(#"[[["Hi","Привет"],[null,null,"Privet"]],null,"ru"]"#))
    #expect(result.text == "Hi")
}

@Test(arguments: [
    "",
    "not json",
    "<html>429 Too Many Requests</html>",
    #"{"sentences":[]}"#,
    "[]",
    "[null]",
    #"["text"]"#,
    #"[["Hallo"]]"#,
    #"[[[]]]"#,
    #"[[[42,"Hello"]]]"#,
    #"[[["Hallo","Hello"]],null,42]"#,
    #"[[["Hallo","Hello"]],null,"<script>"]"#,
])
func malformedResponseIsAnError(_ json: String) {
    #expect(throws: TranslateError.unexpectedFormat) { try GoogleTranslateAPI.parse(data(json)) }
}

@Test func emptyTranslationIsAnError() {
    #expect(throws: TranslateError.emptyResult) { try GoogleTranslateAPI.parse(data(#"[[]]"#)) }
    #expect(throws: TranslateError.emptyResult) { try GoogleTranslateAPI.parse(data(#"[[["  ","x"]],null,"en"]"#)) }
}

// MARK: Request builder

@Test func buildsPostRequestWithFormBody() throws {
    let request = try GoogleTranslateAPI.request(text: "a&b=c+d 100% Привет\nмир?", source: nil, target: "en")
    #expect(request.httpMethod == "POST")
    let url = try #require(request.url)
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "translate.googleapis.com")
    #expect(components.path == "/translate_a/single")
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(query == ["client": "gtx", "sl": "auto", "tl": "en", "dt": "t"])
    #expect(url.absoluteString.contains("Привет") == false)
    #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-www-form-urlencoded") == true)
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(body == "q=a%26b%3Dc%2Bd%20100%25%20%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82%0A%D0%BC%D0%B8%D1%80%3F")
    #expect(body.dropFirst(2).removingPercentEncoding == "a&b=c+d 100% Привет\nмир?")
}

@Test func usesExplicitSourceLanguage() throws {
    let request = try GoogleTranslateAPI.request(text: "Hallo", source: "de", target: "zh-CN")
    let url = try #require(request.url)
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    #expect(query.contains(URLQueryItem(name: "sl", value: "de")))
    #expect(query.contains(URLQueryItem(name: "tl", value: "zh-CN")))
}

@Test func longTextIsCarriedInTheBodyUpToTheLimit() throws {
    let text = String(repeating: "слово ", count: GoogleTranslateAPI.maxCharacters / 6)
    let request = try GoogleTranslateAPI.request(text: text, source: "ru", target: "en")
    #expect((request.url?.absoluteString.count ?? 0) < 200)
    #expect((request.httpBody?.count ?? 0) > GoogleTranslateAPI.maxCharacters)
    let tooLong = String(repeating: "a", count: GoogleTranslateAPI.maxCharacters + 1)
    #expect(throws: TranslateError.textTooLong(limit: GoogleTranslateAPI.maxCharacters)) {
        try GoogleTranslateAPI.request(text: tooLong, source: nil, target: "en")
    }
}

// MARK: Google client with a stubbed transport (no network)

private func response(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://translate.googleapis.com")!, statusCode: status, httpVersion: nil, headerFields: nil)!
}

@Test func clientParsesSuccessfulResponse() async throws {
    let result = try await GoogleTranslateAPI.translate(text: "Привет", source: nil, target: "en") { _ in
        (data(multiSentence), response(200))
    }
    #expect(result.detectedSource == "ru")
}

@Test func clientMapsHTTPAndNetworkErrors() async {
    await #expect(throws: TranslateError.http(429)) {
        try await GoogleTranslateAPI.translate(text: "x", source: nil, target: "en") { _ in (Data(), response(429)) }
    }
    await #expect(throws: TranslateError.self) {
        try await GoogleTranslateAPI.translate(text: "x", source: nil, target: "en") { _ in throw URLError(.notConnectedToInternet) }
    }
    await #expect(throws: TranslateError.cancelled) {
        try await GoogleTranslateAPI.translate(text: "x", source: nil, target: "en") { _ in throw URLError(.cancelled) }
    }
}

// MARK: Engine choice and fallback

private actor Calls {
    var google = 0, apple = 0
    func hitGoogle() { google += 1 }
    func hitApple() { apple += 1 }
}

private func translator(_ calls: Calls, google: TranslateError? = nil, apple: TranslateError? = nil) -> Translator {
    Translator(
        google: { text, _, _ throws(TranslateError) in
            await calls.hitGoogle()
            if let google { throw google }
            return GoogleTranslation(text: "G:" + text, detectedSource: "ru")
        },
        apple: { text, source, target throws(TranslateError) in
            await calls.hitApple()
            if let apple { throw apple }
            return AppleTranslation(text: "A:\(text):\(target)", source: source ?? "ru")
        })
}

@Test func googleIsUsedByDefault() async {
    let calls = Calls()
    let result = await translator(calls).translate("привет", pair: LanguagePair(source: nil, target: "en"), engine: .google)
    #expect(result == .success(TranslationOutput(text: "G:привет", detectedSource: "ru", engine: .google, googleFailure: nil)))
    #expect(await calls.apple == 0)
}

@Test func explicitSourceHidesDetection() async {
    let result = await translator(Calls()).translate("привет", pair: LanguagePair(source: "ru", target: "en"), engine: .google)
    #expect((try? result.get())?.detectedSource == nil)
}

@Test(arguments: [TranslateError.network("offline"), .http(503), .unexpectedFormat, .emptyResult])
func googleFailureFallsBackToApple(_ error: TranslateError) async {
    let calls = Calls()
    let result = await translator(calls, google: error).translate("hi", pair: LanguagePair(source: nil, target: "zh-CN"), engine: .google)
    #expect(result == .success(TranslationOutput(text: "A:hi:zh-Hans", detectedSource: "ru", engine: .apple, googleFailure: error)))
}

@Test func appleEngineSkipsGoogle() async {
    let calls = Calls()
    let result = await translator(calls).translate("hi", pair: LanguagePair(source: "en", target: "ru"), engine: .apple)
    #expect((try? result.get())?.engine == .apple)
    #expect(await calls.google == 0)
}

@Test func bothEnginesFailingReportsBoth() async {
    let result = await translator(Calls(), google: .http(500), apple: .appleNotInstalled(source: "en", target: "ru"))
        .translate("hi", pair: LanguagePair(source: "en", target: "ru"), engine: .google)
    let failure = TranslationFailure(primary: .http(500), fallback: .appleNotInstalled(source: "en", target: "ru"))
    #expect(result == .failure(failure))
    #expect(failure.message.contains("500"))
}

@Test func cancellationDoesNotFallBack() async {
    let calls = Calls()
    let result = await translator(calls, google: .cancelled).translate("hi", pair: .standard(for: .russian), engine: .google)
    #expect(result == .failure(TranslationFailure(primary: .cancelled)))
    #expect(await calls.apple == 0)
}

// MARK: Languages and persistence

private func freshDefaults() -> UserDefaults {
    let name = "FringeTranslateTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func languageListIsUniqueAndHasTheCommonOnes() {
    let codes = TranslateLanguage.all.map(\.code)
    #expect(Set(codes).count == codes.count)
    for code in ["ru", "en", "de", "fr", "es", "it", "pt", "uk", "pl", "tr", "zh-CN", "ja", "ko", "ar"] {
        #expect(codes.contains(code))
    }
    #expect(TranslateLanguage.find("zh-CN")?.appleCode == "zh-Hans")
    #expect(TranslateLanguage.find("zh-Hans")?.code == "zh-CN")
    #expect(TranslateLanguage.find("ru")?.name(language: .russian) == "Русский")
}

@Test func unknownDetectedCodeStillGetsAName() {
    #expect(TranslateLanguage.displayName(for: "be", language: .english) == "Belarusian")
    #expect(TranslateLanguage.displayName(for: "pt-BR", language: .english) == "Portuguese")
}

@Test func defaultPairDetectsAndTargetsTheInterfaceLanguage() {
    let defaults = freshDefaults()
    #expect(LanguagePair.load(from: defaults, language: .russian) == LanguagePair(source: nil, target: "ru"))
    #expect(LanguagePair.load(from: defaults, language: .english) == LanguagePair(source: nil, target: "en"))
}

@Test func pairRoundTrips() {
    let defaults = freshDefaults()
    LanguagePair(source: "de", target: "uk").save(to: defaults)
    #expect(LanguagePair.load(from: defaults) == LanguagePair(source: "de", target: "uk"))
    LanguagePair(source: nil, target: "ja").save(to: defaults)
    #expect(LanguagePair.load(from: defaults) == LanguagePair(source: nil, target: "ja"))
}

@Test func brokenOrUnknownStoredPairFallsBack() {
    let defaults = freshDefaults()
    defaults.set(Data("garbage".utf8), forKey: LanguagePair.defaultsKey)
    #expect(LanguagePair.load(from: defaults, language: .english) == .standard(for: .english))
    defaults.set(Data(#"{"source":"xx","target":"en"}"#.utf8), forKey: LanguagePair.defaultsKey)
    #expect(LanguagePair.load(from: defaults, language: .english) == .standard(for: .english))
}

@Test func swappingLanguages() {
    #expect(LanguagePair(source: "de", target: "en").swapped(detected: nil) == LanguagePair(source: "en", target: "de"))
    // Auto: the detected language becomes the target.
    #expect(LanguagePair(source: nil, target: "en").swapped(detected: "ru") == LanguagePair(source: "en", target: "ru"))
    #expect(LanguagePair(source: nil, target: "en").swapped(detected: "zh-Hans") == LanguagePair(source: "en", target: "zh-CN"))
    // Auto without a usable detection: switch between ru and en.
    #expect(LanguagePair(source: nil, target: "ru").swapped(detected: nil) == LanguagePair(source: "ru", target: "en"))
    #expect(LanguagePair(source: nil, target: "en").swapped(detected: "en") == LanguagePair(source: "en", target: "ru"))
    #expect(LanguagePair(source: nil, target: "en").swapped(detected: "be") == LanguagePair(source: "en", target: "ru"))
}

@Test func settingsDefaultsAndRoundTrip() {
    let defaults = freshDefaults()
    let initial = TranslateSettings.load(from: defaults)
    #expect(initial.prefillFromClipboard == false)
    #expect(initial.engine == .google)
    var changed = initial
    changed.engine = .apple
    changed.prefillFromClipboard = true
    changed.save(to: defaults)
    #expect(TranslateSettings.load(from: defaults) == changed)
    defaults.set(Data(#"{"engine":"deepl"}"#.utf8), forKey: TranslateSettings.defaultsKey)
    #expect(TranslateSettings.load(from: defaults) == TranslateSettings())
}

// MARK: Apple helpers (on device, no network)

@Test func mapsAppleLanguagesBackToOurCodes() {
    #expect(AppleTranslate.ourCode(for: Locale.Language(identifier: "zh-Hans")) == "zh-CN")
    #expect(AppleTranslate.ourCode(for: Locale.Language(identifier: "ru")) == "ru")
    #expect(AppleTranslate.ourCode(for: Locale.Language(identifier: "pt-BR")) == "pt")
}

@Test func detectsLanguageOnDevice() {
    #expect(AppleTranslate.detectLanguage(of: "Привет, как у тебя сегодня дела?") == "ru")
    #expect(AppleTranslate.detectLanguage(of: "The weather is nice today, isn't it?") == "en")
}
