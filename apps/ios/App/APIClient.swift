import Foundation
import MuralCore

final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct APIUsage { var input = 0; var output = 0; var searches = 0 }
struct APIResult { var text: String; var sources: [SourceLink]; var usage: APIUsage }

@MainActor final class APIClient {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 60
        config.httpCookieStorage = nil; config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let key = CredentialStore.read() else { throw APIError.missingKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/" + path)!)
        request.httpMethod = "POST"; request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode, Self.providerMessage(data)) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.invalidResponse }
        return json
    }
    /// Opens a Realtime call: the SDP offer and the session travel as multipart form fields, and
    /// the SDP answer comes back as the body. Sent through the same redirect-blocking session as
    /// every other request, so the Authorization header only ever reaches api.openai.com.
    func realtimeCall(sdp: String, session: [String: Any]) async throws -> String {
        guard let key = CredentialStore.read() else { throw APIError.missingKey }
        let boundary = "mural-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ type: String, _ value: Data) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\nContent-Type: \(type)\r\n\r\n".utf8))
            body.append(value); body.append(Data("\r\n".utf8))
        }
        field("sdp", "application/sdp", Data(sdp.utf8))
        field("session", "application/json", try JSONSerialization.data(withJSONObject: session))
        body.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls")!)
        request.httpMethod = "POST"; request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await self.session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode, Self.providerMessage(data)) }
        guard let answer = String(data: data, encoding: .utf8), answer.hasPrefix("v=") else { throw APIError.invalidResponse }
        return answer
    }
    func respond(instructions: String, input: String, schema: [String: Any]? = nil, search: Bool = false) async throws -> APIResult {
        var body: [String: Any] = ["model": "gpt-5.6-luna", "store": false, "instructions": instructions,
                                  "input": [["role": "user", "content": input]], "max_output_tokens": schema == nil ? 1400 : 2200,
                                  "reasoning": ["effort": "low"]]
        if let schema { body["text"] = ["format": ["type": "json_schema", "name": "mural_result", "strict": true, "schema": schema]] }
        if search { body["tools"] = [["type": "web_search"]]; body["tool_choice"] = "auto"; body["max_tool_calls"] = 1 }
        let json = try await post("responses", body: body)
        guard json["status"] as? String == "completed" else { throw APIError.incomplete }
        var text = "", sources: [SourceLink] = [], usage = APIUsage()
        for item in json["output"] as? [[String: Any]] ?? [] {
            if item["type"] as? String == "web_search_call" { usage.searches += 1 }
            for content in item["content"] as? [[String: Any]] ?? [] {
                if content["type"] as? String == "refusal" { throw APIError.refused }
                if content["type"] as? String == "output_text" { text += content["text"] as? String ?? "" }
                for citation in content["annotations"] as? [[String: Any]] ?? [] {
                    guard citation["type"] as? String == "url_citation", let url = citation["url"] as? String else { continue }
                    let source = SourceLink(title: citation["title"] as? String ?? "Source", url: url)
                    if source.safeURL != nil && !sources.contains(where: { $0.url == url }) { sources.append(source) }
                }
            }
        }
        if let u = json["usage"] as? [String: Any] { usage.input = u["input_tokens"] as? Int ?? 0; usage.output = u["output_tokens"] as? Int ?? 0 }
        guard !text.isEmpty else { throw APIError.incomplete }
        return APIResult(text: text, sources: sources, usage: usage)
    }
    /// The provider's own explanation of a rejection, so a bad field is diagnosable instead of
    /// showing a bare status. Only the message and the parameter it names are read, and the
    /// request — which carries the Authorization header — is never included.
    private static func providerMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        let parts = [error["message"] as? String, (error["param"] as? String).map { "(\($0))" }]
        let text = parts.compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(300))
    }
    static func object(_ fields: [String: Any]) -> [String: Any] { ["type": "object", "properties": fields, "required": fields.keys.sorted(), "additionalProperties": false] }
    static let string: [String: Any] = ["type": "string"]
    static func assessmentSchema(language: LanguageModule) -> [String: Any] { object([
        "outcome": ["type": "string", "enum": ["success", "partial", "breakdown", "uncertain"]],
        "suggestedLevel": ["type": "integer", "minimum": 0, "maximum": 5], "nextGoal": string, "capability": string,
        "words": ["type": "array", "maxItems": 12, "items": object([
            "lemma": string, "meaning": string, "form": string, "quote": string, "language": ["type": "string", "enum": Array(Set([language.id, "en", "mixed", "uncertain"])).sorted()],
            "kind": ["type": "string", "enum": ["exposure", "understanding", "assisted", "independent", "lapse"]],
            "confidence": ["type": "number", "minimum": 0, "maximum": 1], "sourceIDs": ["type": "array", "items": string]
        ])]
    ]) }
    static func phraseMeaningSchema() -> [String: Any] { object([
        "meanings": ["type": "array", "maxItems": Phrases.maximumPerLine, "items": string]
    ]) }
    enum APIError: LocalizedError {
        case missingKey, invalidResponse, incomplete, refused, http(Int, String?)
        var errorDescription: String? {
            switch self {
            case .missingKey: "Add your OpenAI key in Settings to begin."
            case .invalidResponse, .incomplete: "OpenAI returned an incomplete response. Please try again."
            case .refused: "Mural couldn’t complete that request. Try a different topic."
            case .http(401, _): "Your OpenAI key wasn’t accepted. Check it in Settings."
            case .http(403, let detail), .http(404, let detail):
                "This API key may not have access to the requested model. Check your OpenAI project." + (detail.map { " OpenAI said: \($0)" } ?? "")
            case .http(429, _): "OpenAI’s usage or rate limit was reached. Check your project’s billing and limits."
            case .http(let status, let detail):
                "OpenAI couldn’t complete the request (HTTP \(status))." + (detail.map { " OpenAI said: \($0)" } ?? "") + " Please try again."
            }
        }
    }
}
