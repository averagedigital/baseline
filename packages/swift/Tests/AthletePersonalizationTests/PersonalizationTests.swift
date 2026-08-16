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

@Test func ambiguousIdentitySampleDoesNotPolluteGallery() {
    var gallery = PersonalIdentityGallery()
    let accepted = gallery.update(embedding: [1, 0], quality: 0.95, isAmbiguous: false)
    #expect(accepted)
    let before = gallery
    let rejected = gallery.update(embedding: [0, 1], quality: 0.99, isAmbiguous: true)
    #expect(!rejected)
    #expect(gallery == before)
    #expect(gallery.similarity(to: [1, 0]) == 1)
}

@Test func exercisePrototypeRequiresPersonalExamplesAndAsksOnLowConfidence() {
    var library = ExercisePrototypeLibrary()
    #expect(library.classify([1, 0]).needsConfirmation)
    library.confirm(exerciseID: "bench", displayName: "Жим лёжа", representation: [1, 0], at: Date(timeIntervalSince1970: 1))
    #expect(library.classify([0.99, 0.01]).needsConfirmation)
    library.confirm(exerciseID: "bench", displayName: "Жим лёжа", representation: [0.98, 0.02], at: Date(timeIntervalSince1970: 2))
    let result = library.classify([0.97, 0.03])
    #expect(result.exerciseID == "bench")
    #expect(!result.needsConfirmation)
}

@Test func movementBaselineReportsOnlyObservedRobustDeviation() {
    var baseline = PersonalMovementBaseline()
    for value in [0.78, 0.80, 0.81, 0.79, 0.82] {
        baseline.observe(exerciseID: "squat", feature: "rom", value: value, confidence: 0.9)
    }
    #expect(baseline.deviation(exerciseID: "squat", feature: "rom", value: 0.80, confidence: 0.9) == nil)
    let deviation = baseline.deviation(exerciseID: "squat", feature: "rom", value: 0.45, confidence: 0.9)
    #expect(deviation?.direction == .belowUsual)
    #expect(baseline.deviation(exerciseID: "squat", feature: "unobserved", value: 0.1, confidence: 1) == nil)
}

@Test func continualPersonalizationCanBeReset() {
    var state = ContinualPersonalizationState()
    _ = state.identity.update(embedding: [1, 0], quality: 1, isAmbiguous: false)
    state.exercises.confirm(exerciseID: "custom", displayName: "Моё упражнение", representation: [0, 1])
    state.reset()
    #expect(state == ContinualPersonalizationState())
}
