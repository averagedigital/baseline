import Foundation
import GRDB

public struct StoredFeedbackEvent<Payload: Codable & Sendable>: Codable, Sendable {
    public let id: UUID
    public let kind: String
    public let payload: Payload
    public let createdAt: Date

    public init(id: UUID, kind: String, payload: Payload, createdAt: Date = Date()) {
        self.id = id; self.kind = kind; self.payload = payload; self.createdAt = createdAt
    }
}

public struct StoredRecommendationExposure: Codable, Equatable, Sendable {
    public let id: UUID
    public let payload: Data
    public let createdAt: Date
    public var rewardedAt: Date?
    public var reward: Double?

    public init(id: UUID, payload: Data, createdAt: Date, rewardedAt: Date? = nil, reward: Double? = nil) {
        self.id = id; self.payload = payload; self.createdAt = createdAt; self.rewardedAt = rewardedAt; self.reward = reward
    }
}

public struct StoredFoodObservation: Codable, Equatable, Sendable {
    public let id: UUID
    public let payload: Data
    public let capturedAt: Date
    public var dismissed: Bool

    public init(id: UUID, payload: Data, capturedAt: Date, dismissed: Bool = false) {
        self.id = id; self.payload = payload; self.capturedAt = capturedAt; self.dismissed = dismissed
    }
}

extension AthleteStore {
    public func loadPersonalizationState<State: Decodable>(as type: State.Type) throws -> State? {
        try database.read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM personalization_state WHERE id = ?", arguments: ["personalization-v1"]) else { return nil }
            return try JSONDecoder().decode(State.self, from: data)
        }
    }

    public func savePersonalizationState<State: Encodable>(_ state: State, at date: Date) throws {
        let data = try JSONEncoder().encode(state)
        try database.write { db in
            try db.execute(sql: "INSERT INTO personalization_state (id, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at", arguments: ["personalization-v1", data, date])
        }
    }

    public func hasFeedbackEvent(id: UUID) throws -> Bool {
        try database.read { db in try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM feedback_events WHERE id = ?)", arguments: [id.uuidString]) ?? false }
    }

    @discardableResult
    public func insertFeedbackEvent<Payload: Codable & Sendable>(_ event: StoredFeedbackEvent<Payload>) throws -> Bool {
        let data = try JSONEncoder().encode(event.payload)
        return try database.write { db in
            guard try !Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM feedback_events WHERE id = ?)", arguments: [event.id.uuidString])! else { return false }
            try db.execute(sql: "INSERT INTO feedback_events (id, kind, payload, created_at) VALUES (?, ?, ?, ?)", arguments: [event.id.uuidString, event.kind, data, event.createdAt])
            return true
        }
    }

    public func saveRecommendationExposure(_ exposure: StoredRecommendationExposure) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO recommendation_exposures (id, payload, rewarded) VALUES (?, ?, ?)", arguments: [exposure.id.uuidString, exposure.payload, exposure.rewardedAt != nil])
        }
    }

    public func recommendationExposure(id: UUID) throws -> StoredRecommendationExposure? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT payload, rewarded FROM recommendation_exposures WHERE id = ?", arguments: [id.uuidString]) else { return nil }
            return StoredRecommendationExposure(id: id, payload: row["payload"], createdAt: Date(), rewardedAt: (row["rewarded"] as Bool) ? Date() : nil)
        }
    }

    @discardableResult
    public func markRecommendationExposureRewarded(id: UUID, reward: Double, at date: Date = Date()) throws -> Bool {
        try database.write { db in
            guard let rewarded: Bool = try Bool.fetchOne(db, sql: "SELECT rewarded FROM recommendation_exposures WHERE id = ?", arguments: [id.uuidString]), !rewarded else { return false }
            try db.execute(sql: "UPDATE recommendation_exposures SET rewarded = ? WHERE id = ?", arguments: [true, id.uuidString])
            return true
        }
    }

    public func saveFoodObservation(_ observation: StoredFoodObservation) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO food_observations (id, payload, captured_at) VALUES (?, ?, ?)", arguments: [observation.id.uuidString, observation.payload, observation.capturedAt])
        }
    }

    public func recentFoodObservations(limit: Int = 20) throws -> [StoredFoodObservation] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, payload, captured_at FROM food_observations ORDER BY captured_at DESC LIMIT ?", arguments: [max(1, limit)]).compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                return StoredFoodObservation(id: id, payload: row["payload"], capturedAt: row["captured_at"])
            }
        }
    }

    public func dismissFoodObservation(id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE food_observations SET payload = ? WHERE id = ?", arguments: [Data("{\"dismissed\":true}".utf8), id.uuidString])
        }
    }
}
