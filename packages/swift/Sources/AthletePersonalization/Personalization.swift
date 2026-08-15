import Foundation

public enum PersonalizationFeatureVersion: String, Codable, Sendable { case v1 }

public struct PersonalizationFeatures: Codable, Equatable, Sendable {
    public let values: [Double]
    public let version: PersonalizationFeatureVersion

    public init?(values: [Double], version: PersonalizationFeatureVersion = .v1) {
        guard values.count == 8, values.allSatisfy(\.isFinite) else { return nil }
        self.values = values
        self.version = version
    }

    public init(activeMinutes: Double, setCount: Double, trackingCoverage: Double, workRestRatio: Double, recentActiveMinutes: Double, hoursSincePrevious: Double, nutritionSignal: Double = 0) {
        values = [1, activeMinutes / 60, setCount / 20, min(workRestRatio / 4, 1), trackingCoverage, recentActiveMinutes / 300, min(hoursSincePrevious / 168, 1), nutritionSignal / 2000]
        version = .v1
    }
}

public struct DifficultyRegressionState: Codable, Equatable, Sendable {
    public var inverseCovariance: [[Double]]
    public var weights: [Double]
    public var sampleCount: Int
    public init(dimension: Int = 8, regularization: Double = 1) {
        inverseCovariance = (0..<dimension).map { row in (0..<dimension).map { $0 == row ? 1 / regularization : 0 } }
        weights = Array(repeating: 0, count: dimension); sampleCount = 0
    }
}

public struct LocalDifficultyModel: Codable, Equatable, Sendable {
    public private(set) var state: DifficultyRegressionState
    public init() { state = DifficultyRegressionState() }
    public var samples: Int { state.sampleCount }
    public var dataConfidence: Double { min(Double(state.sampleCount) / 20, 1) }

    public mutating func update(features: PersonalizationFeatures, rpe: Double) {
        let x = features.values; guard x.count == state.weights.count else { return }
        let px = multiply(state.inverseCovariance, x); let denominator = 1 + dot(x, px)
        guard denominator.isFinite, denominator > 0 else { return }
        let gain = px.map { $0 / denominator }; let error = min(max(rpe, 1), 10) - dot(state.weights, x)
        state.weights = zip(state.weights, gain).map { $0 + $1 * error }
        for row in state.inverseCovariance.indices { for col in state.inverseCovariance[row].indices { state.inverseCovariance[row][col] -= gain[row] * px[col] } }
        state.sampleCount += 1
    }

    public func predict(features: PersonalizationFeatures) -> Double? {
        guard state.sampleCount >= 3 else { return nil }
        guard features.values.count == state.weights.count else { return nil }
        return min(max(dot(state.weights, features.values), 1), 10)
    }
}

public enum CoachingAction: String, Codable, Sendable, CaseIterable { case technique, load, recovery, nutrition, consistency }

public struct LinUCBArm: Codable, Equatable, Sendable {
    public var inverseCovariance: [[Double]]; public var b: [Double]; public var sampleCount: Int
    public init(dimension: Int = 8) { inverseCovariance = (0..<dimension).map { row in (0..<dimension).map { $0 == row ? 1.0 : 0 } }; b = Array(repeating: 0, count: dimension); sampleCount = 0 }
    public func score(_ x: [Double], alpha: Double) -> Double { let theta = multiply(inverseCovariance, b); return dot(theta, x) + alpha * sqrt(max(0, dot(x, multiply(inverseCovariance, x)))) }
    public mutating func update(_ x: [Double], reward: Double) {
        let ax = multiply(inverseCovariance, x); let d = 1 + dot(x, ax); guard d.isFinite, d > 0 else { return }
        let k = ax.map { $0 / d }; b = zip(b, x).map { $0 + $1 * reward }
        for row in inverseCovariance.indices { for col in inverseCovariance[row].indices { inverseCovariance[row][col] -= k[row] * ax[col] } }
        sampleCount += 1
    }
}

public struct LocalBanditState: Codable, Equatable, Sendable {
    public var arms: [CoachingAction: LinUCBArm]; public var totalExplicitRewards: Int
    public init() { arms = Dictionary(uniqueKeysWithValues: CoachingAction.allCases.map { ($0, LinUCBArm()) }); totalExplicitRewards = 0 }
    public func choose(features: PersonalizationFeatures) -> (action: CoachingAction, personalized: Bool, confidence: Double) {
        guard totalExplicitRewards >= 5 else { return (.consistency, false, 0) }
        let best = CoachingAction.allCases.max { (arms[$0]?.score(features.values, alpha: 0.5) ?? 0) < (arms[$1]?.score(features.values, alpha: 0.5) ?? 0) } ?? .consistency
        return (best, true, min(Double(totalExplicitRewards) / 20, 1))
    }
    public mutating func update(action: CoachingAction, features: PersonalizationFeatures, reward: Double) { arms[action, default: LinUCBArm()].update(features.values, reward: min(max(reward, -1), 1)); totalExplicitRewards += 1 }
}

public struct RecommendationExposure: Codable, Equatable, Sendable {
    public let id: UUID; public let action: CoachingAction; public let featureVector: [Double]; public let featureVersion: PersonalizationFeatureVersion; public let contextDigest: String; public let createdAt: Date
    public var rewardedAt: Date?; public var reward: Double?
    public init(id: UUID = UUID(), action: CoachingAction, features: PersonalizationFeatures, contextDigest: String = "local", createdAt: Date = Date()) { self.id = id; featureVector = features.values; featureVersion = features.version; self.action = action; self.contextDigest = contextDigest; self.createdAt = createdAt }
    public mutating func consumeReward() -> Bool {
        guard rewardedAt == nil else { return false }
        rewardedAt = Date()
        reward = 1
        return true
    }
}

public struct PersonalizationState: Codable, Equatable, Sendable {
    public var difficulty: LocalDifficultyModel
    public var bandit: LocalBanditState
    public init(difficulty: LocalDifficultyModel = LocalDifficultyModel(), bandit: LocalBanditState = LocalBanditState()) {
        self.difficulty = difficulty
        self.bandit = bandit
    }
}

private func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
private func multiply(_ matrix: [[Double]], _ vector: [Double]) -> [Double] { matrix.map { dot($0, vector) } }
