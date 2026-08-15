import Testing
@testable import AthletePersonalization

@Test func difficultyHasColdStartAndExplicitUpdates() {
    let f = PersonalizationFeatures(activeMinutes: 20, setCount: 4, trackingCoverage: 0.9, workRestRatio: 1, recentActiveMinutes: 40, hoursSincePrevious: 48)
    var model = LocalDifficultyModel()
    #expect(model.prediction == nil)
    model.update(features: f, rpe: 7); model.update(features: f, rpe: 8); model.update(features: f, rpe: 6)
    #expect(model.prediction == 7)
}

@Test func exposureIsSingleUse() {
    let f = PersonalizationFeatures(activeMinutes: 0, setCount: 0, trackingCoverage: 0, workRestRatio: 0, recentActiveMinutes: 0, hoursSincePrevious: 0)
    var exposure = RecommendationExposure(action: .recovery, features: f)
    let first = exposure.consumeReward()
    let second = exposure.consumeReward()
    #expect(first)
    #expect(!second)
}
