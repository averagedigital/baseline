import AthleteStore
import Foundation

struct ResponsesInputMessage: Codable, Equatable, Sendable {
    enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    let role: Role
    let content: String
}

enum ResponsesStreamEvent: Equatable, Sendable {
    case textDelta(String)
    case completed
    case failure(String)
}

enum ResponsesAPIError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidHTTPResponse
    case httpStatus(Int)
    case remote(String)
    case malformedEvent
    case incompleteStream
}

struct ResponsesAPIClient: Sendable {
    private struct RequestBody: Encodable {
        let model: String
        let input: [ResponsesInputMessage]
        let stream = true
        let store = false
    }

    private struct EventEnvelope: Decodable {
        struct Response: Decodable {
            struct APIError: Decodable {
                let message: String
            }

            let error: APIError?
        }

        let type: String
        let delta: String?
        let message: String?
        let response: Response?
    }

    static func makeRequest(
        provider: ProviderConfiguration,
        apiKey: String,
        messages: [ResponsesInputMessage]
    ) throws -> URLRequest {
        let base = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/responses"), url.scheme != nil, url.host != nil else {
            throw ResponsesAPIError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            RequestBody(model: provider.model, input: messages)
        )
        return request
    }

    static func parseEvent(_ line: String) throws -> ResponsesStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" { return .completed }
        guard let data = payload.data(using: .utf8) else {
            throw ResponsesAPIError.malformedEvent
        }
        let event: EventEnvelope
        do {
            event = try JSONDecoder().decode(EventEnvelope.self, from: data)
        } catch {
            throw ResponsesAPIError.malformedEvent
        }
        switch event.type {
        case "response.output_text.delta":
            guard let delta = event.delta else { throw ResponsesAPIError.malformedEvent }
            return .textDelta(delta)
        case "response.completed":
            return .completed
        case "error":
            return .failure(event.message ?? "Responses API вернул ошибку")
        case "response.failed":
            return .failure(event.response?.error?.message ?? "Responses API не завершил ответ")
        default:
            return nil
        }
    }

    func stream(
        provider: ProviderConfiguration,
        apiKey: String,
        messages: [ResponsesInputMessage],
        receive: @escaping @Sendable (String) async -> Void
    ) async throws {
        let request = try Self.makeRequest(provider: provider, apiKey: apiKey, messages: messages)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ResponsesAPIError.invalidHTTPResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw ResponsesAPIError.httpStatus(http.statusCode)
        }
        for try await line in bytes.lines {
            switch try Self.parseEvent(line) {
            case let .textDelta(delta):
                await receive(delta)
            case .completed:
                return
            case let .failure(message):
                throw ResponsesAPIError.remote(message)
            case nil:
                continue
            }
        }
        throw ResponsesAPIError.incompleteStream
    }
}
