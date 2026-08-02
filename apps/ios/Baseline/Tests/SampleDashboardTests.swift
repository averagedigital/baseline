import Testing
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
