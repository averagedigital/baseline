import Foundation
import GRDB

public enum NutritionDatabaseError: Error, Equatable, Sendable { case missingResource; case invalidSchema }

public extension NutritionDatabase {
    init(path: String) throws {
        let database = try DatabaseQueue(path: path)
        let items = try database.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, canonical_name, kcal_per_100g FROM foods")
            return try rows.map { row in
                let aliases = try String.fetchAll(db, sql: "SELECT alias FROM food_aliases WHERE food_id = ?", arguments: [row["id"] as Int64])
                return NutritionItem(canonicalName: row["canonical_name"], aliases: aliases, kcalPer100g: row["kcal_per_100g"])
            }
        }
        guard !items.isEmpty else { throw NutritionDatabaseError.invalidSchema }
        self.init(items: items)
    }
}
