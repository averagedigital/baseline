import AthleteStore
import XCTest
@testable import Baseline

final class ResponsesAPIClientTests: XCTestCase {
    func testRequestIncludesOnlySupportedCapabilities() throws {
        let provider = ProviderConfiguration(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-5.4", capabilities: .openAI, webSearchEnabled: true, reasoningEffort: .high)
        let payload = ResponsesAPIClient.requestPayload(provider: provider, input: [["role": "user", "content": [["type": "input_text", "text": "Обед"]]]], tools: [CoachToolDefinition.createFoodEntry.dictionary], previousResponseID: nil)
        let tools = payload["tools"] as? [[String: Any]]
        XCTAssertTrue(tools?.contains { $0["type"] as? String == "web_search" } == true)
        XCTAssertEqual((payload["reasoning"] as? [String: String])?["effort"], "high")

        let legacy = ProviderConfiguration(name: "Legacy", baseURL: "https://example.invalid/v1", model: "text")
        let legacyPayload = ResponsesAPIClient.requestPayload(provider: legacy, input: [], tools: [CoachToolDefinition.createFoodEntry.dictionary], previousResponseID: nil)
        XCTAssertNil(legacyPayload["reasoning"])
        XCTAssertNil(legacyPayload["tools"])
    }

    func testEventParserCollectsMultipleToolCalls() throws {
        var parser = ResponsesEventParser()
        try parser.consume(#"{"type":"response.output_item.done","item":{"type":"function_call","call_id":"a","name":"list_food_entries","arguments":"{}"}}"#)
        try parser.consume(#"{"type":"response.output_item.done","item":{"type":"function_call","call_id":"b","name":"delete_food_entry","arguments":"{\"id\":\"x\"}"}}"#)
        XCTAssertEqual(parser.functionCalls.map(\.callID), ["a", "b"])
        XCTAssertEqual(parser.outputItems.count, 2)
    }

    func testFoodToolSchemaDescribesArgumentsAndRejectsUnknownFields() throws {
        let tool = CoachToolDefinition.createFoodEntry.dictionary
        let parameters = try XCTUnwrap(tool["parameters"] as? [String: Any])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: Any])
        XCTAssertNotNil(properties["consumed_at"])
        XCTAssertNotNil(properties["meal_type"])
        XCTAssertNotNil(properties["items"])
        XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
    }

    func testMultimodalMessageKeepsTextAndAllImages() throws {
        let message = ResponsesInputMessage(role: .user, content: "Ужин", imageDataURLs: ["data:image/jpeg;base64,AA==", "data:image/png;base64,AA=="])
        let content = try XCTUnwrap(message.dictionary["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { $0["type"] as? String }, ["input_text", "input_image", "input_image"])
    }

    func testEventParserStreamsTextAndCompletes() throws {
        var parser = ResponsesEventParser()
        try parser.consume(#"{"type":"response.output_text.delta","delta":"При"}"#)
        try parser.consume(#"{"type":"response.output_text.delta","delta":"вет"}"#)
        try parser.consume(#"{"type":"response.completed","response":{"id":"resp_1"}}"#)
        XCTAssertEqual(parser.text, "Привет")
        XCTAssertTrue(parser.completed)
        XCTAssertEqual(parser.responseID, "resp_1")
    }

    func testMalformedEventIsRejected() {
        var parser = ResponsesEventParser()
        XCTAssertThrowsError(try parser.consume("not-json"))
    }

    func testVisionIsRejectedBeforeNetworkForTextOnlyProvider() async {
        let provider = ProviderConfiguration(name: "Text", baseURL: "https://example.invalid/v1", model: "text")
        do {
            _ = try await ResponsesAPIClient().run(provider: provider, apiKey: "unused", messages: [.init(role: .user, content: "", imageDataURLs: ["data:image/jpeg;base64,AA=="])], instructions: "", tools: [], onActivity: { _ in }, onTextUpdate: { _ in }, execute: { _ in "" })
            XCTFail("Expected unsupportedVision")
        } catch {
            XCTAssertEqual(error as? ResponsesAPIError, .unsupportedVision)
        }
    }

    func testAgentLoopReturnsToolOutputsAcrossSequentialCalls() async throws {
        let state = ScriptState(scripts: [
            [#"{"type":"response.output_item.done","item":{"type":"function_call","call_id":"a","name":"create_food_entry","arguments":"{}"}}"#, #"{"type":"response.completed","response":{"id":"r1"}}"#],
            [#"{"type":"response.output_item.done","item":{"type":"function_call","call_id":"b","name":"list_food_entries","arguments":"{}"}}"#, #"{"type":"response.completed","response":{"id":"r2"}}"#],
            [#"{"type":"response.output_text.delta","delta":"Готово"}"#, #"{"type":"response.completed","response":{"id":"r3"}}"#],
        ])
        let calls = ToolCallRecorder()
        let provider = ProviderConfiguration(name: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-5.4", capabilities: .openAI)

        let result = try await ResponsesAPIClient(transport: ScriptedTransport(state: state)).run(
            provider: provider, apiKey: "unused", messages: [.init(role: .user, content: "Мой обед")], instructions: "test",
            tools: CoachToolDefinition.foodDiary, onActivity: { _ in }, onTextUpdate: { _ in },
            execute: { call in await calls.record(call); return #"{"success":true}"# }
        )

        XCTAssertEqual(result.text, "Готово")
        let recordedNames = await calls.names
        XCTAssertEqual(recordedNames, ["create_food_entry", "list_food_entries"])
        let bodies = await state.requestBodies
        XCTAssertEqual(bodies.count, 3)
        XCTAssertTrue(try containsFunctionOutput(bodies[1], callID: "a"))
        XCTAssertTrue(try containsFunctionOutput(bodies[2], callID: "b"))
    }

    private func containsFunctionOutput(_ data: Data, callID: String) throws -> Bool {
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        return input.contains { $0["type"] as? String == "function_call_output" && $0["call_id"] as? String == callID }
    }
}

private struct ScriptedTransport: ResponsesEventTransport {
    let state: ScriptState
    func streamEvents(for request: URLRequest, onEvent: @escaping (String) async throws -> Void) async throws {
        let events = try await state.next(request: request)
        for event in events { try await onEvent(event) }
    }
}

private actor ScriptState {
    private var scripts: [[String]]
    private(set) var requestBodies: [Data] = []
    init(scripts: [[String]]) { self.scripts = scripts }
    func next(request: URLRequest) throws -> [String] {
        requestBodies.append(try XCTUnwrap(request.httpBody))
        guard !scripts.isEmpty else { throw ResponsesAPIError.incompleteStream }
        return scripts.removeFirst()
    }
}

private actor ToolCallRecorder {
    private(set) var names: [String] = []
    func record(_ call: CoachToolCall) { names.append(call.name) }
}
