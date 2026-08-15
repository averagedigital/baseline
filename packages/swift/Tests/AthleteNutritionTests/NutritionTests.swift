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
