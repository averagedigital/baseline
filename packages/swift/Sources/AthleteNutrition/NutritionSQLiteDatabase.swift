import Foundation
import GRDB

public enum NutritionDatabaseError: Error, Equatable, Sendable { case missingResource; case invalidSchema }

public extension NutritionDatabase {
    init(path: String) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let database = try DatabaseQueue(path: path, configuration: configuration)
        let items = try database.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT foods.canonical_name, foods.kcal_per_100g,
                       GROUP_CONCAT(food_aliases.alias, '|') AS aliases
                FROM foods
                LEFT JOIN food_aliases ON food_aliases.food_id = foods.id
                GROUP BY foods.id
                """)
            return rows.map { row in
                NutritionItem(canonicalName: row["canonical_name"], aliases: (row["aliases"] as String? ?? "").split(separator: "|").map(String.init), kcalPer100g: row["kcal_per_100g"])
            }
        }
        guard !items.isEmpty else { throw NutritionDatabaseError.invalidSchema }
        self.init(items: items)
    }
}
