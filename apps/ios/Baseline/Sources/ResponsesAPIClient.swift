import AthleteStore
import Foundation

struct ResponsesInputMessage: Equatable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    let role: Role
    let text: String
    let imageDataURLs: [String]
    init(role: Role, content: String, imageDataURLs: [String] = []) { self.role = role; text = content; self.imageDataURLs = imageDataURLs }
    var dictionary: [String: Any] {
        let textType = role == .user ? "input_text" : "output_text"
        var content: [[String: Any]] = text.isEmpty ? [] : [["type": textType, "text": text]]
        content += imageDataURLs.map { ["type": "input_image", "image_url": $0, "detail": "auto"] }
        return ["role": role.rawValue, "content": content]
    }
}

enum CoachActivity: Equatable, Sendable { case thinking, analyzingImages, searchingWeb, callingTool(String), streamingText }
struct CoachCitation: Codable, Equatable, Sendable { let title: String?; let url: URL }
struct CoachToolCall: Equatable, Sendable { let callID: String; let name: String; let arguments: String }
struct CoachToolDefinition: Sendable {
    let name: String; let description: String; let parameters: [String: AnySendable]
    var dictionary: [String: Any] { ["type": "function", "name": name, "description": description, "parameters": parameters.mapValues(\.value)] }
    static let createFoodEntry = Self(name: "create_food_entry", description: "Create one consumed meal atomically", parameters: schema(
        properties: [
            "consumed_at": string("date-time"), "meal_type": enumString(["breakfast", "lunch", "dinner", "snack", "other"]),
            "notes": string(), "items": array(itemSchema())
        ],
        required: ["consumed_at", "meal_type", "items"]
    ))
    static let updateFoodEntry = Self(name: "update_food_entry", description: "Update an existing food entry", parameters: schema(
        properties: ["id": string("uuid"), "consumed_at": string("date-time"), "meal_type": enumString(["breakfast", "lunch", "dinner", "snack", "other"]), "notes": string(), "items": array(itemSchema())],
        required: ["id"]
    ))
    static let deleteFoodEntry = Self(name: "delete_food_entry", description: "Delete an existing food entry", parameters: schema(properties: ["id": string("uuid")], required: ["id"]))
    static let getFoodEntry = Self(name: "get_food_entry", description: "Read an existing food entry", parameters: schema(properties: ["id": string("uuid")], required: ["id"]))
    static let listFoodEntries = Self(name: "list_food_entries", description: "List food entries in an ISO-8601 date interval", parameters: schema(properties: ["from": string("date-time"), "to": string("date-time")], required: ["from", "to"]))
    static let foodDiary = [createFoodEntry, updateFoodEntry, deleteFoodEntry, getFoodEntry, listFoodEntries]
    private static func estimatedValue() -> [String: Any] {
        ["type": "object", "properties": ["exact": number(), "low": number(), "high": number()], "additionalProperties": false]
    }
    private static func itemSchema() -> [String: Any] { [
        "type": "object", "properties": [
            "name": string(), "amount": estimatedValue(), "unit": string(), "calories_kcal": estimatedValue(),
            "protein_g": estimatedValue(), "fat_g": estimatedValue(), "carbohydrates_g": estimatedValue(),
            "provenance": enumString(["userProvided", "modelEstimated", "databaseLookup", "webLookup", "sensorMeasured"]),
            "confidence": number(), "source_url": string("uri")
        ], "required": ["name", "amount", "calories_kcal", "protein_g", "fat_g", "carbohydrates_g", "provenance"], "additionalProperties": false
    ] }
    private static func schema(properties: [String: Any], required: [String]) -> [String: AnySendable] {
        ["type": AnySendable("object"), "properties": AnySendable(properties), "required": AnySendable(required), "additionalProperties": AnySendable(false)]
    }
    private static func string(_ format: String? = nil) -> [String: Any] { var value: [String: Any] = ["type": "string"]; if let format { value["format"] = format }; return value }
    private static func enumString(_ values: [String]) -> [String: Any] { ["type": "string", "enum": values] }
    private static func number() -> [String: Any] { ["type": "number"] }
    private static func array(_ items: [String: Any]) -> [String: Any] { ["type": "array", "items": items, "minItems": 1] }
}

struct AnySendable: @unchecked Sendable { let value: Any; init(_ value: Any) { self.value = value } }

enum ResponsesAPIError: Error, Equatable, Sendable, LocalizedError {
    case invalidBaseURL, invalidHTTPResponse, httpStatus(Int), remote(String), malformedEvent, incompleteStream, unsupportedVision, toolLoopLimit
    var errorDescription: String? { switch self {
    case .invalidBaseURL: "Некорректный Base URL провайдера."
    case .invalidHTTPResponse: "Провайдер вернул некорректный HTTP-ответ."
    case let .httpStatus(code): "Cloud API вернул HTTP \(code)."
    case let .remote(message): message
    case .malformedEvent: "Cloud API вернул неподдерживаемый SSE event."
    case .incompleteStream: "Cloud API не завершил ответ."
    case .unsupportedVision: "Выбранный провайдер не поддерживает изображения."
    case .toolLoopLimit: "Coach превысил лимит последовательных tool calls."
    } }
}

struct ResponsesEventParser: Sendable {
    private(set) var responseID: String?
    private(set) var text = ""
    private(set) var functionCalls: [CoachToolCall] = []
    private(set) var outputItems: [AnySendable] = []
    private(set) var citations: [CoachCitation] = []
    private(set) var completed = false
    private(set) var failedMessage: String?

    mutating func consume(_ payload: String) throws -> CoachActivity? {
        guard let data = payload.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = object["type"] as? String else { throw ResponsesAPIError.malformedEvent }
        if let response = object["response"] as? [String: Any] { responseID = response["id"] as? String ?? responseID }
        switch type {
        case "response.output_text.delta": text += object["delta"] as? String ?? ""; return .streamingText
        case "response.output_item.done":
            if let item = object["item"] as? [String: Any] {
                outputItems.append(AnySendable(item))
                if item["type"] as? String == "function_call", let callID = item["call_id"] as? String, let name = item["name"] as? String, let arguments = item["arguments"] as? String { functionCalls.append(.init(callID: callID, name: name, arguments: arguments)); return .callingTool(name) }
            }
        case "response.web_search_call.in_progress", "response.web_search_call.searching": return .searchingWeb
        case "response.reasoning_summary_text.delta": return .thinking
        case "response.output_text.annotation.added":
            if let annotation = object["annotation"] as? [String: Any], let rawURL = annotation["url"] as? String, let url = URL(string: rawURL) { citations.append(.init(title: annotation["title"] as? String, url: url)) }
        case "response.completed": completed = true
        case "response.failed": failedMessage = ((object["response"] as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
        case "error": failedMessage = object["message"] as? String
        default: break
        }
        return nil
    }
}

struct ResponsesResult: Sendable { let text: String; let citations: [CoachCitation] }

protocol ResponsesEventTransport: Sendable {
    func streamEvents(for request: URLRequest, onEvent: @escaping (String) async throws -> Void) async throws
}

struct URLSessionResponsesEventTransport: ResponsesEventTransport {
    func streamEvents(for request: URLRequest, onEvent: @escaping (String) async throws -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ResponsesAPIError.invalidHTTPResponse }
        guard 200..<300 ~= http.statusCode else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = object["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ResponsesAPIError.remote(message)
            }
            throw ResponsesAPIError.httpStatus(http.statusCode)
        }
        for try await line in bytes.lines where line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            try await onEvent(payload)
        }
    }
}

struct ResponsesAPIClient: Sendable {
    private let transport: any ResponsesEventTransport
    init(transport: any ResponsesEventTransport = URLSessionResponsesEventTransport()) { self.transport = transport }
    static func requestPayload(provider: ProviderConfiguration, input: [[String: Any]], tools: [[String: Any]], previousResponseID: String?) -> [String: Any] {
        var body: [String: Any] = ["model": provider.model, "input": input, "stream": true, "store": false]
        if let previousResponseID { body["previous_response_id"] = previousResponseID }
        if provider.capabilities.supportsFunctionCalling {
            var enabledTools = tools
            if provider.capabilities.supportsWebSearch && provider.webSearchEnabled { enabledTools.append(["type": "web_search"]) }
            if !enabledTools.isEmpty { body["tools"] = enabledTools }
        }
        if provider.capabilities.supportsReasoning, provider.reasoningEffort != .off {
            var reasoning = ["effort": provider.reasoningEffort.rawValue]
            if provider.capabilities.supportsReasoningSummary { reasoning["summary"] = "auto" }
            body["reasoning"] = reasoning
        }
        if provider.capabilities.supportsReasoning { body["include"] = ["reasoning.encrypted_content"] }
        return body
    }

    func run(provider: ProviderConfiguration, apiKey: String, messages: [ResponsesInputMessage], instructions: String, tools: [CoachToolDefinition], onActivity: @escaping @Sendable (CoachActivity) async -> Void, onTextUpdate: @escaping @Sendable (String) async -> Void, execute: @escaping @Sendable (CoachToolCall) async -> String) async throws -> ResponsesResult {
        guard provider.capabilities.supportsVision || messages.allSatisfy(\.imageDataURLs.isEmpty) else { throw ResponsesAPIError.unsupportedVision }
        var input = messages.map(\.dictionary)
        var citations: [CoachCitation] = []
        for _ in 0..<8 {
            await onActivity(messages.contains { !$0.imageDataURLs.isEmpty } ? .analyzingImages : .thinking)
            var body = Self.requestPayload(provider: provider, input: input, tools: tools.map(\.dictionary), previousResponseID: nil)
            body["instructions"] = instructions
            let parser = try await stream(provider: provider, apiKey: apiKey, body: body, onActivity: onActivity, onTextUpdate: onTextUpdate)
            citations += parser.citations
            if let failure = parser.failedMessage { throw ResponsesAPIError.remote(failure) }
            guard parser.completed else { throw ResponsesAPIError.incompleteStream }
            guard !parser.functionCalls.isEmpty else { return ResponsesResult(text: parser.text, citations: citations) }
            input += parser.outputItems.compactMap { $0.value as? [String: Any] }
            for call in parser.functionCalls { input.append(["type": "function_call_output", "call_id": call.callID, "output": await execute(call)]) }
        }
        throw ResponsesAPIError.toolLoopLimit
    }

    func stream(provider: ProviderConfiguration, apiKey: String, messages: [ResponsesInputMessage], instructions: String? = nil) async throws -> String {
        try await run(provider: provider, apiKey: apiKey, messages: messages, instructions: instructions ?? "", tools: [], onActivity: { _ in }, onTextUpdate: { _ in }, execute: { _ in #"{"error":"tool unavailable"}"# }).text
    }

    private func stream(provider: ProviderConfiguration, apiKey: String, body: [String: Any], onActivity: @escaping @Sendable (CoachActivity) async -> Void, onTextUpdate: @escaping @Sendable (String) async -> Void) async throws -> ResponsesEventParser {
        let base = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/responses"), url.scheme != nil, url.host != nil else { throw ResponsesAPIError.invalidBaseURL }
        var request = URLRequest(url: url); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("text/event-stream", forHTTPHeaderField: "Accept"); request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        var parser = ResponsesEventParser()
        try await transport.streamEvents(for: request) { payload in
            let previousText = parser.text
            if let activity = try parser.consume(payload) { await onActivity(activity) }
            if parser.text != previousText { await onTextUpdate(parser.text) }
        }
        return parser
    }
}
