import AthleteStore
import Foundation

struct ResponsesInputMessage: Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable { case user, assistant }
    let role: Role
    let content: String
}

enum ResponsesAPIError: Error, Equatable, Sendable {
    case invalidBaseURL, invalidHTTPResponse, httpStatus(Int), remote(String), malformedEvent, incompleteStream
}

struct ResponsesAPIClient: Sendable {
    private struct RequestBody: Encodable {
        let model: String
        let input: [ResponsesInputMessage]
        let instructions: String?
        let stream = true
        let store = false
    }
    private struct EventEnvelope: Decodable {
        struct Response: Decodable { struct APIError: Decodable { let message: String }; let error: APIError? }
        let type: String; let delta: String?; let message: String?; let response: Response?
    }

    func stream(provider: ProviderConfiguration, apiKey: String, messages: [ResponsesInputMessage], instructions: String? = nil) async throws -> String {
        let base = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/responses"), url.scheme != nil, url.host != nil else { throw ResponsesAPIError.invalidBaseURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(model: provider.model, input: messages, instructions: instructions))
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ResponsesAPIError.invalidHTTPResponse }
        guard 200..<300 ~= http.statusCode else { throw ResponsesAPIError.httpStatus(http.statusCode) }
        var output = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { return output }
            guard let data = payload.data(using: .utf8) else { throw ResponsesAPIError.malformedEvent }
            let event: EventEnvelope
            do { event = try JSONDecoder().decode(EventEnvelope.self, from: data) } catch { throw ResponsesAPIError.malformedEvent }
            switch event.type {
            case "response.output_text.delta": if let delta = event.delta { output += delta }
            case "response.completed": return output
            case "error": throw ResponsesAPIError.remote(event.message ?? "Responses API вернул ошибку")
            case "response.failed": throw ResponsesAPIError.remote(event.response?.error?.message ?? "Responses API не завершил ответ")
            default: continue
            }
        }
        throw ResponsesAPIError.incompleteStream
    }
}
