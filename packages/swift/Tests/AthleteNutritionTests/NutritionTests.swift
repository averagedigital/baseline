import Testing
@testable import AthleteNutrition

@Test func matchesAliasAndCalculatesRange() {
    let item = NutritionItem(canonicalName: "banana", aliases: ["банан"], kcalPer100g: 89)
    let db = NutritionDatabase(items: [item])
    #expect(db.match("банан") == item)
    #expect(db.calories(for: item, gramsLow: 80, gramsHigh: 120) == MealCalories(low: 71.2, high: 106.8))
    #expect(db.calories(for: item, gramsLow: nil, gramsHigh: 120) == nil)
}

@Test func trackerRequiresTwoHitsAndKeepsStableIdentity() {
    var tracker = FoodDetectionTracker(minimumConfidence: 0.4, minimumHits: 2)
    let first = FoodDetection(label: "apple", confidence: 0.8, boundingBox: NormalizedFoodRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
    #expect(tracker.update([first], at: 1).isEmpty)
    let second = FoodDetection(label: "apple", confidence: 0.9, boundingBox: NormalizedFoodRect(x: 0.11, y: 0.1, width: 0.2, height: 0.2))
    let result = tracker.update([second], at: 2)
    #expect(result.count == 1)
    #expect(result[0].id == first.id)
    #expect(result[0].boundingBox.x > first.boundingBox.x)
}

@Test func matcherRanksSemanticNameAndRejectsUnrelatedFood() {
    let cooked = NutritionItem(canonicalName: "Rice, white, cooked", aliases: ["cooked rice"], kcalPer100g: 130)
    let flour = NutritionItem(canonicalName: "Rice flour", kcalPer100g: 366)
    let db = NutritionDatabase(items: [flour, cooked])
    #expect(db.match("white rice cooked") == cooked)
    #expect(db.match("rice flour") == flour)
    #expect(db.match("motor oil") == nil)
}

@Test func trackerExpiresAnObjectAfterConsecutiveMisses() {
    var tracker = FoodDetectionTracker(minimumConfidence: 0.4, minimumHits: 2, maximumMisses: 2)
    let detection = FoodDetection(label: "apple", confidence: 0.9, boundingBox: NormalizedFoodRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2))
    _ = tracker.update([detection], at: 1)
    #expect(tracker.update([detection], at: 2).count == 1)
    #expect(tracker.update([], at: 3).count == 1)
    #expect(tracker.update([], at: 4).count == 1)
    #expect(tracker.update([], at: 5).isEmpty)
}

@Test func trackerKeepsTwoIndependentObjects() {
    var tracker = FoodDetectionTracker(minimumConfidence: 0.4, minimumHits: 2)
    let left = FoodDetection(label: "apple", confidence: 0.9, boundingBox: NormalizedFoodRect(x: 0.1, y: 0.2, width: 0.15, height: 0.15))
    let right = FoodDetection(label: "apple", confidence: 0.8, boundingBox: NormalizedFoodRect(x: 0.7, y: 0.2, width: 0.15, height: 0.15))
    _ = tracker.update([left, right], at: 1)
    let result = tracker.update([left, right], at: 2)
    #expect(result.count == 2)
    #expect(Set(result.map(\.id)) == Set([left.id, right.id]))
}

@Test func trackerIgnoresWeakDetectionWithoutBreakingExistingTrack() {
    var tracker = FoodDetectionTracker(minimumConfidence: 0.4, minimumHits: 2)
    let strong = FoodDetection(label: "apple", confidence: 0.9, boundingBox: NormalizedFoodRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2))
    let weak = FoodDetection(label: "apple", confidence: 0.2, boundingBox: strong.boundingBox)
    _ = tracker.update([strong], at: 1)
    #expect(tracker.update([strong], at: 2).count == 1)
    #expect(tracker.update([weak], at: 3).count == 1)
}
