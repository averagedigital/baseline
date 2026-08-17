import Foundation
import GRDB

public enum EstimatedValue: Codable, Equatable, Sendable {
    case exact(Double)
    case range(low: Double, high: Double)
    case unknown

    var isValid: Bool {
        switch self {
        case let .exact(value): value.isFinite && value >= 0
        case let .range(low, high): low.isFinite && high.isFinite && low >= 0 && high >= low
        case .unknown: true
        }
    }
}

public enum FoodProvenance: String, Codable, Equatable, Sendable {
    case userProvided, modelEstimated, databaseLookup, webLookup, sensorMeasured
}

public enum MealType: String, Codable, Equatable, Sendable { case breakfast, lunch, dinner, snack, other }

public struct FoodItemDraft: Codable, Equatable, Sendable {
    public let name: String
    public let amount: EstimatedValue
    public let unit: String?
    public let caloriesKcal: EstimatedValue
    public let proteinG: EstimatedValue
    public let fatG: EstimatedValue
    public let carbohydratesG: EstimatedValue
    public let provenance: FoodProvenance
    public let confidence: Double?
    public let sourceURL: URL?

    public init(name: String, amount: EstimatedValue, unit: String?, caloriesKcal: EstimatedValue, proteinG: EstimatedValue, fatG: EstimatedValue, carbohydratesG: EstimatedValue, provenance: FoodProvenance, confidence: Double?, sourceURL: URL? = nil) {
        self.name = name; self.amount = amount; self.unit = unit; self.caloriesKcal = caloriesKcal
        self.proteinG = proteinG; self.fatG = fatG; self.carbohydratesG = carbohydratesG
        self.provenance = provenance; self.confidence = confidence; self.sourceURL = sourceURL
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount.isValid && caloriesKcal.isValid && proteinG.isValid && fatG.isValid && carbohydratesG.isValid && (confidence == nil || (0...1).contains(confidence!))
    }
}

public struct FoodEntryDraft: Codable, Equatable, Sendable {
    public let consumedAt: Date
    public let mealType: MealType
    public let items: [FoodItemDraft]
    public let notes: String?
    public let linkedChatMessageID: UUID?
    public let linkedAttachmentIDs: [UUID]

    public init(consumedAt: Date, mealType: MealType, items: [FoodItemDraft], notes: String? = nil, linkedChatMessageID: UUID? = nil, linkedAttachmentIDs: [UUID] = []) {
        self.consumedAt = consumedAt; self.mealType = mealType; self.items = items; self.notes = notes
        self.linkedChatMessageID = linkedChatMessageID; self.linkedAttachmentIDs = linkedAttachmentIDs
    }
}

public struct FoodDiaryItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let entryID: UUID
    public let value: FoodItemDraft
    public var name: String { value.name }
}

public struct FoodEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let consumedAt: Date
    public let mealType: MealType
    public let items: [FoodDiaryItem]
    public let notes: String?
    public let linkedChatMessageID: UUID?
    public let linkedAttachmentIDs: [UUID]
    public let createdAt: Date
    public let updatedAt: Date
}

public struct FoodEntryPatch: Codable, Equatable, Sendable {
    public let consumedAt: Date?
    public let mealType: MealType?
    public let items: [FoodItemDraft]?
    public let notes: String?
    public init(consumedAt: Date? = nil, mealType: MealType? = nil, items: [FoodItemDraft]? = nil, notes: String? = nil) {
        self.consumedAt = consumedAt; self.mealType = mealType; self.items = items; self.notes = notes
    }
}

public enum FoodDiaryError: Error, Equatable, Sendable { case invalidInput, notFound }

extension AthleteStore {
    public func createFoodEntry(_ draft: FoodEntryDraft, toolCallID: String, at date: Date = Date()) throws -> FoodEntry {
        guard !toolCallID.isEmpty, !draft.items.isEmpty, draft.items.allSatisfy(\.isValid) else { throw FoodDiaryError.invalidInput }
        return try database.write { db in
            if let result = try Self.toolResult(toolCallID, in: db) { return result }
            let id = UUID()
            try db.execute(sql: "INSERT INTO food_entries (id, consumed_at, meal_type, notes, linked_chat_message_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)", arguments: [id.uuidString, draft.consumedAt, draft.mealType.rawValue, draft.notes, draft.linkedChatMessageID?.uuidString, date, date])
            try Self.replaceItems(draft.items, entryID: id, in: db)
            for attachmentID in draft.linkedAttachmentIDs {
                try db.execute(sql: "INSERT INTO food_entry_attachments (entry_id, attachment_id) VALUES (?, ?)", arguments: [id.uuidString, attachmentID.uuidString])
            }
            let entry = try Self.readFoodEntry(id: id, in: db)!
            try Self.saveToolResult(entry, callID: toolCallID, operation: "create", in: db)
            return entry
        }
    }

    public func updateFoodEntry(id: UUID, patch: FoodEntryPatch, toolCallID: String, at date: Date = Date()) throws -> FoodEntry {
        guard !toolCallID.isEmpty, patch.items?.allSatisfy(\.isValid) ?? true, patch.items?.isEmpty != true else { throw FoodDiaryError.invalidInput }
        return try database.write { db in
            if let result = try Self.toolResult(toolCallID, in: db) { return result }
            guard let existing = try Self.readFoodEntry(id: id, in: db) else { throw FoodDiaryError.notFound }
            try db.execute(sql: "UPDATE food_entries SET consumed_at = ?, meal_type = ?, notes = ?, updated_at = ? WHERE id = ?", arguments: [patch.consumedAt ?? existing.consumedAt, (patch.mealType ?? existing.mealType).rawValue, patch.notes ?? existing.notes, date, id.uuidString])
            if let items = patch.items { try Self.replaceItems(items, entryID: id, in: db) }
            let entry = try Self.readFoodEntry(id: id, in: db)!
            try Self.saveToolResult(entry, callID: toolCallID, operation: "update", in: db)
            return entry
        }
    }

    public func deleteFoodEntry(id: UUID, toolCallID: String) throws -> Bool {
        guard !toolCallID.isEmpty else { throw FoodDiaryError.invalidInput }
        return try database.write { db in
            if try Data.fetchOne(db, sql: "SELECT result FROM food_tool_calls WHERE id = ?", arguments: [toolCallID]) != nil { return true }
            try db.execute(sql: "DELETE FROM food_entries WHERE id = ?", arguments: [id.uuidString])
            guard db.changesCount > 0 else { throw FoodDiaryError.notFound }
            try db.execute(sql: "INSERT INTO food_tool_calls (id, operation, entry_id, result, created_at) VALUES (?, 'delete', ?, ?, ?)", arguments: [toolCallID, id.uuidString, Data("true".utf8), Date()])
            return true
        }
    }

    public func foodEntry(id: UUID) throws -> FoodEntry? { try database.read { try Self.readFoodEntry(id: id, in: $0) } }
    public func foodEntries(from: Date, to: Date) throws -> [FoodEntry] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM food_entries WHERE consumed_at >= ? AND consumed_at < ? ORDER BY consumed_at DESC", arguments: [from, to]).compactMap { UUID(uuidString: $0) }.compactMap { try Self.readFoodEntry(id: $0, in: db) }
        }
    }

    private static func readFoodEntry(id: UUID, in db: Database) throws -> FoodEntry? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM food_entries WHERE id = ?", arguments: [id.uuidString]) else { return nil }
        let typeValue: String = row["meal_type"]
        guard let mealType = MealType(rawValue: typeValue) else { throw FoodDiaryError.invalidInput }
        let items = try Row.fetchAll(db, sql: "SELECT id, payload FROM food_items WHERE entry_id = ? ORDER BY rowid", arguments: [id.uuidString]).compactMap { itemRow -> FoodDiaryItem? in
            let itemIDValue: String = itemRow["id"]
            guard let itemID = UUID(uuidString: itemIDValue) else { return nil }
            return FoodDiaryItem(id: itemID, entryID: id, value: try JSONDecoder().decode(FoodItemDraft.self, from: itemRow["payload"]))
        }
        let attachmentIDs = try String.fetchAll(db, sql: "SELECT attachment_id FROM food_entry_attachments WHERE entry_id = ?", arguments: [id.uuidString]).compactMap(UUID.init(uuidString:))
        let linkedMessage: String? = row["linked_chat_message_id"]
        return FoodEntry(id: id, consumedAt: row["consumed_at"], mealType: mealType, items: items, notes: row["notes"], linkedChatMessageID: linkedMessage.flatMap(UUID.init(uuidString:)), linkedAttachmentIDs: attachmentIDs, createdAt: row["created_at"], updatedAt: row["updated_at"])
    }

    private static func replaceItems(_ items: [FoodItemDraft], entryID: UUID, in db: Database) throws {
        try db.execute(sql: "DELETE FROM food_items WHERE entry_id = ?", arguments: [entryID.uuidString])
        for item in items { try db.execute(sql: "INSERT INTO food_items (id, entry_id, payload) VALUES (?, ?, ?)", arguments: [UUID().uuidString, entryID.uuidString, try JSONEncoder().encode(item)]) }
    }
    private static func toolResult(_ id: String, in db: Database) throws -> FoodEntry? {
        guard let data = try Data.fetchOne(db, sql: "SELECT result FROM food_tool_calls WHERE id = ?", arguments: [id]) else { return nil }
        return try JSONDecoder().decode(FoodEntry.self, from: data)
    }
    private static func saveToolResult(_ entry: FoodEntry, callID: String, operation: String, in db: Database) throws {
        try db.execute(sql: "INSERT INTO food_tool_calls (id, operation, entry_id, result, created_at) VALUES (?, ?, ?, ?, ?)", arguments: [callID, operation, entry.id.uuidString, try JSONEncoder().encode(entry), Date()])
    }
}
