import Foundation
import Testing
@testable import AthletePersonalization

@Test func difficultyHasColdStartAndExplicitUpdates() {
    let f = PersonalizationFeatures(activeMinutes: 20, setCount: 4, trackingCoverage: 0.9, workRestRatio: 1, recentActiveMinutes: 40, hoursSincePrevious: 48)
    var model = LocalDifficultyModel()
    #expect(model.predict(features: f) == nil)
    model.update(features: f, rpe: 7); model.update(features: f, rpe: 8); model.update(features: f, rpe: 6)
    #expect(model.predict(features: f) != nil)
}

@Test func featureAwarePredictionChangesWithContext() {
    let easy = PersonalizationFeatures(activeMinutes: 10, setCount: 2, trackingCoverage: 1, workRestRatio: 0.5, recentActiveMinutes: 10, hoursSincePrevious: 72)
    let hard = PersonalizationFeatures(activeMinutes: 60, setCount: 16, trackingCoverage: 1, workRestRatio: 3, recentActiveMinutes: 240, hoursSincePrevious: 12)
    var model = LocalDifficultyModel()
    for _ in 0..<3 { model.update(features: easy, rpe: 3) }
    for _ in 0..<3 { model.update(features: hard, rpe: 9) }
    #expect(model.predict(features: easy) != model.predict(features: hard))
}

@Test func compositeStateKeepsBothModels() throws {
    var state = PersonalizationState()
    let features = PersonalizationFeatures(activeMinutes: 20, setCount: 4, trackingCoverage: 1, workRestRatio: 1, recentActiveMinutes: 20, hoursSincePrevious: 24)
    state.difficulty.update(features: features, rpe: 7)
    state.bandit.update(action: .recovery, features: features, reward: 1)
    let data = try JSONEncoder().encode(state)
    let restored = try JSONDecoder().decode(PersonalizationState.self, from: data)
    #expect(restored.difficulty.samples == 1)
    #expect(restored.bandit.totalExplicitRewards == 1)
}

@Test func exposureIsSingleUse() {
    let f = PersonalizationFeatures(activeMinutes: 0, setCount: 0, trackingCoverage: 0, workRestRatio: 0, recentActiveMinutes: 0, hoursSincePrevious: 0)
    var exposure = RecommendationExposure(action: .recovery, features: f)
    let first = exposure.consumeReward()
    let second = exposure.consumeReward()
    #expect(first)
    #expect(!second)
}
