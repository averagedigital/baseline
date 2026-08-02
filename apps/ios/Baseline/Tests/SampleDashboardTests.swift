import Testing
import AthleteStore
import Foundation
@testable import Baseline

@Test("Приложение содержит только камеру и чат")
func exposesTwoPrimaryTabs() {
    #expect(AppTab.allCases == [.camera, .chat])
}

@Test("График интенсивности хранит ограниченное число значений")
func boundsIntensityHistory() {
    var history = MotionIntensityHistory(limit: 3)

    history.append(-1)
    history.append(0.4)
    history.append(0.8)
    history.append(2)

    #expect(history.values == [0.4, 0.8, 1])
}

@Test("Положение камеры переключается между фронтальным и задним")
func togglesCameraPosition() {
    #expect(CaptureCameraPosition.front.toggled == .back)
    #expect(CaptureCameraPosition.back.toggled == .front)
}

@Test("Отправка создаёт пользовательское сообщение и потоковый ответ")
func startsChatTurn() {
    var conversation = ChatConversation()

    let started = conversation.startUserTurn("  Как восстановиться?  ")

    #expect(started)
    #expect(conversation.messages.count == 2)
    #expect(conversation.messages[0].role == .user)
    #expect(conversation.messages[0].text == "Как восстановиться?")
    #expect(conversation.messages[1].role == .assistant)
    #expect(conversation.messages[1].state == .streaming)
    #expect(conversation.isResponding)
}

@Test("Пустое сообщение не начинает диалог")
func rejectsEmptyChatTurn() {
    var conversation = ChatConversation()

    let started = conversation.startUserTurn(" \n ")

    #expect(!started)
    #expect(conversation.messages.isEmpty)
}

@Test("Потоковый ответ накапливается и завершается")
func completesStreamingReply() {
    var conversation = ChatConversation()
    _ = conversation.startUserTurn("Разбери тренировку")

    conversation.appendAssistantDelta("Сначала ")
    conversation.appendAssistantDelta("проверим нагрузку.")
    conversation.finishAssistantReply()

    #expect(conversation.messages.last?.text == "Сначала проверим нагрузку.")
    #expect(conversation.messages.last?.state == .sent)
    #expect(!conversation.isResponding)
}

@Test("Responses API запрос содержит локальный контекст и не хранится у провайдера")
func buildsResponsesAPIRequest() throws {
    let provider = ProviderConfiguration(
        name: "OpenAI",
        baseURL: "https://api.openai.com/v1/",
        model: "gpt-5.6"
    )
    let messages = [
        ResponsesInputMessage(role: .user, content: "Разбери подход"),
        ResponsesInputMessage(role: .assistant, content: "Пришли запись"),
    ]

    let request = try ResponsesAPIClient.makeRequest(
        provider: provider,
        apiKey: "test-key",
        messages: messages
    )
    let body = try #require(request.httpBody)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let input = try #require(json["input"] as? [[String: Any]])

    #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    #expect(json["model"] as? String == "gpt-5.6")
    #expect(json["stream"] as? Bool == true)
    #expect(json["store"] as? Bool == false)
    #expect(input.map { $0["role"] as? String } == ["user", "assistant"])
    #expect(input.map { $0["content"] as? String } == ["Разбери подход", "Пришли запись"])
}

@Test("Responses API parser принимает только текстовые delta")
func parsesResponsesAPIEvents() throws {
    let delta = try ResponsesAPIClient.parseEvent(
        #"data: {"type":"response.output_text.delta","delta":"Ровный темп"}"#
    )
    let completed = try ResponsesAPIClient.parseEvent(
        #"data: {"type":"response.completed","response":{"id":"resp_1"}}"#
    )

    #expect(delta == .textDelta("Ровный темп"))
    #expect(completed == .completed)
    #expect(try ResponsesAPIClient.parseEvent("event: response.output_text.delta") == nil)
}

@Test("Responses API parser возвращает ошибку провайдера")
func parsesResponsesAPIError() throws {
    let event = try ResponsesAPIClient.parseEvent(
        #"data: {"type":"error","message":"Неверный ключ"}"#
    )

    #expect(event == .failure("Неверный ключ"))
}
