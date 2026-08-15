import Testing
@testable import AthleteNutrition

@Test func matchesAliasAndCalculatesRange() {
    let item = NutritionItem(canonicalName: "banana", aliases: ["банан"], kcalPer100g: 89)
    let db = NutritionDatabase(items: [item])
    #expect(db.match("банан") == item)
    #expect(db.calories(for: item, gramsLow: 80, gramsHigh: 120) == MealCalories(low: 71.2, high: 106.8))
    #expect(db.calories(for: item, gramsLow: nil, gramsHigh: 120) == nil)
}
