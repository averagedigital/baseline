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
