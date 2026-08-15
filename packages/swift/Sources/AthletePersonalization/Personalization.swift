import Foundation

public struct PersonalizationFeatures: Codable, Equatable, Sendable {
    public let activeMinutes: Double; public let setCount: Double; public let trackingCoverage: Double
    public let workRestRatio: Double; public let recentActiveMinutes: Double; public let hoursSincePrevious: Double
    public init(activeMinutes: Double, setCount: Double, trackingCoverage: Double, workRestRatio: Double, recentActiveMinutes: Double, hoursSincePrevious: Double) {
        self.activeMinutes = activeMinutes; self.setCount = setCount; self.trackingCoverage = trackingCoverage; self.workRestRatio = workRestRatio; self.recentActiveMinutes = recentActiveMinutes; self.hoursSincePrevious = hoursSincePrevious
    }
}

public struct LocalDifficultyModel: Codable, Equatable, Sendable {
    public private(set) var samples = 0
    private var weightedTarget = 0.0
    public init() {}
    public var prediction: Double? { samples >= 3 ? weightedTarget / Double(samples) : nil }
    public mutating func update(features: PersonalizationFeatures, rpe: Double) {
        weightedTarget += min(max(rpe, 1), 10); samples += 1
    }
}

public enum CoachingAction: String, Codable, Sendable, CaseIterable { case technique, load, recovery, nutrition, consistency }

public struct RecommendationExposure: Codable, Equatable, Sendable {
    public let id: UUID; public let action: CoachingAction; public let features: PersonalizationFeatures
    public private(set) var rewarded = false
    public init(id: UUID = UUID(), action: CoachingAction, features: PersonalizationFeatures) { self.id = id; self.action = action; self.features = features }
    public mutating func consumeReward() -> Bool { guard !rewarded else { return false }; rewarded = true; return true }
}
