import AthleteCore
import Testing
@testable import Baseline

@Test("Sample state разделяет вычисления, гипотезы и слова пользователя")
func sampleStateKeepsEpistemicRoles() {
    let state = SampleDashboard.fixture

    #expect(state.entries.map(\.role) == [.computed, .inferred, .userReported])
    #expect(state.entries.first?.artifactID != nil)
    #expect(state.entries.last?.artifactID == nil)
}

@Test("Sample state явно сообщает о пробеле данных")
func sampleStateShowsDataGap() {
    #expect(SampleDashboard.fixture.dataGap.isEmpty == false)
}
