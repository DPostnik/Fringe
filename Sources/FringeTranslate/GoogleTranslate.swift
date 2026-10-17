import Foundation

/// What the unofficial Google endpoint returned, after validation.
public struct GoogleTranslation: Equatable, Sendable {
    public var text: String
    /// Google's code for the source language it detected or was given.
    public var detectedSource: String?
}

/// The unofficial, keyless `translate_a/single?client=gtx` endpoint. Google may limit or change it
/// without notice, so everything it returns is validated and anything unexpected is an error.
public enum GoogleTranslateAPI {
    static let endpoint = "https://translate.googleapis.com/translate_a/single"
    /// The endpoint rejects very long input; longer text goes to Apple or is refused.
    public static let maxCharacters = 5000

    /// A POST request: the text travels in a form body, so long text never hits URL length limits.
    public static func request(text: String, source: String?, target: String) throws(TranslateError) -> URLRequest {
        guard text.count <= maxCharacters else { throw .textTooLong(limit: maxCharacters) }
        var components = URLComponents(string: endpoint)!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: source ?? "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(("q=" + formEncode(text)).utf8)
        return request
    }

    /// `application/x-www-form-urlencoded` value encoding: only unreserved characters stay literal.
    static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// Expected shape: `[[["translated","source",...], ...], null, "detected", ...]`.
    /// Segments are joined in order; a segment without a translated string (null) is skipped.
    public static func parse(_ data: Data) throws(TranslateError) -> GoogleTranslation {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [Any],
              let segments = root.first as? [Any] else { throw .unexpectedFormat }
        var text = ""
        for segment in segments {
            guard let parts = segment as? [Any], let first = parts.first else { throw .unexpectedFormat }
            if first is NSNull { continue }
            guard let piece = first as? String else { throw .unexpectedFormat }
            text += piece
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyResult }
        var detected: String?
        if root.count > 2 {
            switch root[2] {
            case let code as String where isLanguageCode(code): detected = code
            case is NSNull: detected = nil
            default: throw .unexpectedFormat
            }
        }
        return GoogleTranslation(text: text, detectedSource: detected)
    }

    static func isLanguageCode(_ code: String) -> Bool {
        (2...12).contains(code.count) && code.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "-" || $0 == "_") }
    }

    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// No cookies or cache: the text is not kept on disk.
    static let session = URLSession(configuration: .ephemeral)
    public static let liveFetch: Fetch = { try await session.data(for: $0) }

    public static func translate(text: String, source: String?, target: String, fetch: Fetch) async throws(TranslateError) -> GoogleTranslation {
        let request = try request(text: text, source: source, target: target)
        let data: Data, response: URLResponse
        do {
            (data, response) = try await fetch(request)
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw .cancelled }
            throw .network((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw .unexpectedFormat }
        guard http.statusCode == 200 else { throw .http(http.statusCode) }
        return try parse(data)
    }
}
