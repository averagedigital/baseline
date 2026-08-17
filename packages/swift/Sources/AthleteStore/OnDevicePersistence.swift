import AthleteCore
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
    public func applySessionRPE(eventID: UUID, sourceEvidenceID: UUID, feedbackPayload: Data, createdAt: Date, statePayload: Data, narrativeEnvelope: EvidenceEnvelope, narrativePayload: Data) throws -> Bool {
        try database.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM evidence_events WHERE id = ?)", arguments: [sourceEvidenceID.uuidString]) ?? false else { throw AthleteStoreError.invalidIdentifier(sourceEvidenceID.uuidString) }
            guard !(try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM feedback_events WHERE id = ?)", arguments: [eventID.uuidString]) ?? false) else { return false }
            try db.execute(sql: "INSERT INTO feedback_events (id, kind, payload, created_at) VALUES (?, ?, ?, ?)", arguments: [eventID.uuidString, "session.rpe", feedbackPayload, createdAt])
            try Self.insert(narrativeEnvelope, in: db)
            try db.execute(sql: "INSERT INTO evidence_payloads (evidence_id, payload) VALUES (?, ?)", arguments: [narrativeEnvelope.id.uuidString, narrativePayload])
            try db.execute(sql: "INSERT INTO personalization_state (id, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at", arguments: ["personalization-v1", statePayload, createdAt])
            return true
        }
    }

    public func applyRecommendationReward(exposureID: UUID, reward: Double, feedbackEventID: UUID, feedbackPayload: Data, createdAt: Date, statePayload: Data) throws -> Bool {
        try database.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT rewarded FROM recommendation_exposures WHERE id = ?", arguments: [exposureID.uuidString]) else { throw AthleteStoreError.invalidIdentifier(exposureID.uuidString) }
            guard !(row["rewarded"] as Bool) else { return false }
            try db.execute(sql: "UPDATE recommendation_exposures SET rewarded = ?, rewarded_at = ?, reward = ? WHERE id = ?", arguments: [true, createdAt, reward, exposureID.uuidString])
            try db.execute(sql: "INSERT INTO feedback_events (id, kind, payload, created_at) VALUES (?, ?, ?, ?)", arguments: [feedbackEventID.uuidString, "recommendation.reward", feedbackPayload, createdAt])
            try db.execute(sql: "INSERT INTO personalization_state (id, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at", arguments: ["personalization-v1", statePayload, createdAt])
            return true
        }
    }

    public func loadPersonalizationState<State: Decodable>(id: String = "personalization-v1", as type: State.Type) throws -> State? {
        try database.read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT payload FROM personalization_state WHERE id = ?", arguments: [id]) else { return nil }
            return try JSONDecoder().decode(State.self, from: data)
        }
    }

    public func savePersonalizationState<State: Encodable>(_ state: State, id: String = "personalization-v1", at date: Date) throws {
        let data = try JSONEncoder().encode(state)
        try database.write { db in
            try db.execute(sql: "INSERT INTO personalization_state (id, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at", arguments: [id, data, date])
        }
    }

    public func clearPersonalizationState() throws {
        try database.write { try $0.execute(sql: "DELETE FROM personalization_state") }
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
            try db.execute(sql: "INSERT OR REPLACE INTO recommendation_exposures (id, payload, created_at, rewarded, rewarded_at, reward) VALUES (?, ?, ?, ?, ?, ?)", arguments: [exposure.id.uuidString, exposure.payload, exposure.createdAt, exposure.rewardedAt != nil, exposure.rewardedAt, exposure.reward])
        }
    }

    public func recommendationExposure(id: UUID) throws -> StoredRecommendationExposure? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT payload, created_at, rewarded_at, reward FROM recommendation_exposures WHERE id = ?", arguments: [id.uuidString]) else { return nil }
            return StoredRecommendationExposure(id: id, payload: row["payload"], createdAt: row["created_at"], rewardedAt: row["rewarded_at"], reward: row["reward"])
        }
    }

    public func recentRecommendationExposures(limit: Int = 20) throws -> [StoredRecommendationExposure] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, payload, created_at, rewarded_at, reward FROM recommendation_exposures ORDER BY created_at DESC LIMIT ?", arguments: [max(1, limit)]).compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                return StoredRecommendationExposure(id: id, payload: row["payload"], createdAt: row["created_at"], rewardedAt: row["rewarded_at"], reward: row["reward"])
            }
        }
    }

    @discardableResult
    public func markRecommendationExposureRewarded(id: UUID, reward: Double, at date: Date = Date()) throws -> Bool {
        try database.write { db in
            guard let rewarded: Bool = try Bool.fetchOne(db, sql: "SELECT rewarded FROM recommendation_exposures WHERE id = ?", arguments: [id.uuidString]), !rewarded else { return false }
            try db.execute(sql: "UPDATE recommendation_exposures SET rewarded = ?, rewarded_at = ?, reward = ? WHERE id = ?", arguments: [true, date, reward, id.uuidString])
            return true
        }
    }

    public func saveFoodObservation(_ observation: StoredFoodObservation) throws {
        try database.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO food_observations (id, payload, captured_at, dismissed) VALUES (?, ?, ?, ?)", arguments: [observation.id.uuidString, observation.payload, observation.capturedAt, observation.dismissed])
        }
    }

    public func recentFoodObservations(limit: Int = 20) throws -> [StoredFoodObservation] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT id, payload, captured_at, dismissed FROM food_observations ORDER BY captured_at DESC LIMIT ?", arguments: [max(1, limit)]).compactMap { row in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                return StoredFoodObservation(id: id, payload: row["payload"], capturedAt: row["captured_at"], dismissed: row["dismissed"])
            }
        }
    }

    public func dismissFoodObservation(id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "UPDATE food_observations SET dismissed = ? WHERE id = ?", arguments: [true, id.uuidString])
        }
    }
}
