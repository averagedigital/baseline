import AthleteCore
import Foundation

struct BackendConfiguration: Sendable {
    let baseURL: URL
    let apiToken: String
    let userID: String

    static var current: BackendConfiguration {
        let environment = ProcessInfo.processInfo.environment
        let baseValue = environment["BASELINE_BACKEND_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "BASELINE_BACKEND_URL") as? String
            ?? "http://127.0.0.1:8000"
        let token = environment["BASELINE_API_TOKEN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "BASELINE_API_TOKEN") as? String
            ?? "dev-only-change-me"
        guard let url = URL(string: baseValue) else {
            preconditionFailure("BASELINE_BACKEND_URL is invalid")
        }
        return BackendConfiguration(baseURL: url, apiToken: token, userID: DeviceIdentity.userID)
    }
}

enum BackendAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Backend вернул некорректный ответ."
        case let .httpStatus(code, message): "Backend HTTP \(code): \(message)"
        case .invalidConfiguration: "Не настроен адрес или токен backend."
        }
    }
}

struct BackendFoodItem: Codable, Equatable, Sendable, Identifiable {
    var id: String { "\(name)-\(estimatedGrams)-\(fdcID ?? 0)" }
    let name: String
    let estimatedGrams: Double
    let gramsLow: Double
    let gramsHigh: Double
    let labelConfidence: Double
    let portionConfidence: Double
    let fdcID: Int?
    let kcalPer100g: Double
    let nutrientSource: String
    let caloriesLow: Double
    let caloriesHigh: Double
}

struct BackendFoodAnalysis: Codable, Equatable, Sendable {
    let containsFood: Bool
    let stored: Bool
    let duplicateOf: UUID?
    let observationID: UUID?
    let confidence: Double
    let caloriesLow: Double
    let caloriesHigh: Double
    let items: [BackendFoodItem]
}

struct BackendChatResponse: Codable, Equatable, Sendable {
    let threadID: UUID
    let answerMarkdown: String
    let recommendationCategory: String
    let evidenceIDs: [UUID]
    let foodIDs: [UUID]
    let contextDigest: String
    let feedbackContextID: UUID?
}

struct BackendFeedbackResponse: Codable, Equatable, Sendable {
    let stored: Bool
    let personalizationSamples: Int
}

struct BackendLatestSession: Codable, Equatable, Sendable {
    let id: UUID
    let observedTo: Date
    let trackingCoverage: Double?
    let activeTime: Double?
    let restTime: Double?
    let trackingGapTime: Double?
    let setCount: Int?
}

struct BackendLatestFood: Codable, Equatable, Sendable {
    let id: UUID
    let capturedAt: Date
    let caloriesLow: Double
    let caloriesHigh: Double
    let items: [BackendFoodItem]
}

struct BackendHome: Codable, Equatable, Sendable {
    let latestSession: BackendLatestSession?
    let latestFood: BackendLatestFood?
    let suggestedAction: String
    let predictedDifficulty: Double?
    let predictionConfidence: Double
}

struct PersonalizationContext: Codable, Equatable, Sendable {
    let activeMinutes: Double
    let setCount: Int
    let workRestRatio: Double
    let trackingCoverage: Double
    let sevenDayActiveMinutes: Double
    let hoursSincePreviousSession: Double
    let recentFoodKcalMidpoint: Double
}

actor BackendAPIClient {
    private let configuration: BackendConfiguration
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: BackendConfiguration = .current,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = BackendDateParser.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
    }

    func health() async throws {
        var request = URLRequest(url: endpoint("healthz"))
        request.httpMethod = "GET"
        _ = try await execute(request)
    }

    func home() async throws -> BackendHome {
        try await requestJSON(path: "v1/home", method: "GET", body: Optional<String>.none)
    }

    func uploadEvidence<Payload: Encodable & Sendable>(
        envelope: EvidenceEnvelope,
        payload: Payload
    ) async throws {
        let body = EvidenceUploadRequest(
            id: envelope.id,
            kind: envelope.kind,
            moduleID: envelope.moduleID,
            observedFrom: envelope.observedFrom,
            observedTo: envelope.observedTo,
            epistemicRole: envelope.epistemicRole.rawValue,
            contentDigest: envelope.contentDigest,
            payload: payload
        )
        let _: EvidenceUploadResponse = try await requestJSON(path: "v1/evidence", method: "POST", body: body)
    }

    func analyzeFood(jpeg: Data, capturedAt: Date) async throws -> BackendFoodAnalysis {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = authenticatedRequest(path: "v1/food/analyze")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartFormData(boundary: boundary)
            .adding(name: "captured_at", value: ISO8601DateFormatter().string(from: capturedAt))
            .adding(name: "image", filename: "candidate.jpg", mediaType: "image/jpeg", data: jpeg)
            .finish()
        let data = try await execute(request)
        return try decoder.decode(BackendFoodAnalysis.self, from: data)
    }

    func chat(threadID: UUID?, message: String) async throws -> BackendChatResponse {
        try await requestJSON(
            path: "v1/chat",
            method: "POST",
            body: ChatRequest(threadID: threadID, message: message)
        )
    }

    func sendSessionRPE(
        value: Double,
        sourceEvidenceID: UUID,
        note: String,
        context: PersonalizationContext
    ) async throws -> BackendFeedbackResponse {
        try await requestJSON(
            path: "v1/feedback",
            method: "POST",
            body: FeedbackRequest(
                eventType: "session_rpe",
                action: nil,
                reward: nil,
                targetValue: value,
                sourceEvidenceID: sourceEvidenceID,
                feedbackContextID: nil,
                note: note,
                context: context
            )
        )
    }

    func sendRecommendationReward(
        feedbackContextID: UUID,
        reward: Double,
        context: PersonalizationContext
    ) async throws -> BackendFeedbackResponse {
        try await requestJSON(
            path: "v1/feedback",
            method: "POST",
            body: FeedbackRequest(
                eventType: "recommendation_reward",
                action: nil,
                reward: reward,
                targetValue: nil,
                sourceEvidenceID: nil,
                feedbackContextID: feedbackContextID,
                note: nil,
                context: context
            )
        )
    }

    func dismissFood(observationID: UUID) async throws {
        let _: FoodDismissResponse = try await requestJSON(
            path: "v1/food/\(observationID.uuidString)/dismiss",
            method: "POST",
            body: Optional<String>.none
        )
    }

    private func requestJSON<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?
    ) async throws -> Response {
        var request = authenticatedRequest(path: path)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }
        let data = try await execute(request)
        return try decoder.decode(Response.self, from: data)
    }

    private func authenticatedRequest(path: String) -> URLRequest {
        var request = URLRequest(url: endpoint(path))
        request.setValue("Bearer \(configuration.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.userID, forHTTPHeaderField: "X-Baseline-User-ID")
        request.timeoutInterval = 60
        return request
    }

    private func endpoint(_ path: String) -> URL {
        configuration.baseURL.appending(path: path)
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "unknown error"
            throw BackendAPIError.httpStatus(http.statusCode, message)
        }
        return data
    }
}

private struct EvidenceUploadRequest<Payload: Encodable & Sendable>: Encodable, Sendable {
    let id: UUID
    let kind: String
    let moduleID: String
    let observedFrom: Date
    let observedTo: Date
    let epistemicRole: String
    let contentDigest: String
    let payload: Payload
}

private struct EvidenceUploadResponse: Codable, Sendable {
    let id: UUID
    let stored: Bool
}

private struct ChatRequest: Codable, Sendable {
    let threadID: UUID?
    let message: String
}

private struct FeedbackRequest: Codable, Sendable {
    let eventType: String
    let action: String?
    let reward: Double?
    let targetValue: Double?
    let sourceEvidenceID: UUID?
    let feedbackContextID: UUID?
    let note: String?
    let context: PersonalizationContext
}

private struct FoodDismissResponse: Codable, Sendable {
    let dismissed: Bool
}

private struct MultipartFormData {
    let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func adding(name: String, value: String) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.data.append("\(value)\r\n")
        return copy
    }

    func adding(name: String, filename: String, mediaType: String, data value: Data) -> MultipartFormData {
        var copy = self
        copy.data.append("--\(boundary)\r\n")
        copy.data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        copy.data.append("Content-Type: \(mediaType)\r\n\r\n")
        copy.data.append(value)
        copy.data.append("\r\n")
        return copy
    }

    func finish() -> Data {
        var copy = data
        copy.append("--\(boundary)--\r\n")
        return copy
    }
}

private enum BackendDateParser {
    static func date(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}
