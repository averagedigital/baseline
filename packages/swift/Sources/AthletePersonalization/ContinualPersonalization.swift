import Foundation

public struct IdentityEmbeddingSample: Codable, Equatable, Sendable {
    public let values: [Double]
    public let quality: Double
    public let createdAt: Date
}

public struct PersonalIdentityGallery: Codable, Equatable, Sendable {
    public private(set) var meanEmbedding: [Double] = []
    public private(set) var representativeEmbeddings: [IdentityEmbeddingSample] = []
    public private(set) var sampleCount = 0

    public init() {}

    @discardableResult
    public mutating func update(embedding: [Double], quality: Double, isAmbiguous: Bool, at date: Date = Date()) -> Bool {
        guard !isAmbiguous, quality >= 0.8, valid(embedding), meanEmbedding.isEmpty || meanEmbedding.count == embedding.count else { return false }
        sampleCount += 1
        if meanEmbedding.isEmpty { meanEmbedding = normalized(embedding) }
        else {
            let weight = 1 / Double(sampleCount)
            meanEmbedding = normalized(zip(meanEmbedding, normalized(embedding)).map { $0 + weight * ($1 - $0) })
        }
        representativeEmbeddings.append(IdentityEmbeddingSample(values: normalized(embedding), quality: quality, createdAt: date))
        representativeEmbeddings = Array(representativeEmbeddings.sorted { $0.quality > $1.quality }.prefix(8))
        return true
    }

    public func similarity(to embedding: [Double]) -> Double? {
        guard meanEmbedding.count == embedding.count, valid(embedding) else { return nil }
        return cosine(meanEmbedding, embedding)
    }
}

public struct ExercisePrototype: Codable, Equatable, Sendable {
    public let exerciseID: String
    public var displayName: String
    public var centroid: [Double]
    public var variance: [Double]
    public var sampleCount: Int
    public var timestamps: [Date]
    public var confidenceHistory: [Double]
}

public struct ExerciseClassification: Equatable, Sendable {
    public let exerciseID: String?
    public let confidence: Double
    public let needsConfirmation: Bool
}

public struct ExercisePrototypeLibrary: Codable, Equatable, Sendable {
    public private(set) var prototypes: [String: ExercisePrototype] = [:]
    public init() {}

    public mutating func confirm(exerciseID: String, displayName: String, representation: [Double], confidence: Double = 1, at date: Date = Date()) {
        guard !exerciseID.isEmpty, !displayName.isEmpty, valid(representation) else { return }
        let vector = normalized(representation)
        guard var current = prototypes[exerciseID] else {
            prototypes[exerciseID] = ExercisePrototype(exerciseID: exerciseID, displayName: displayName, centroid: vector, variance: Array(repeating: 0, count: vector.count), sampleCount: 1, timestamps: [date], confidenceHistory: [confidence])
            return
        }
        guard current.centroid.count == vector.count else { return }
        let oldMean = current.centroid
        let count = Double(current.sampleCount + 1)
        current.centroid = normalized(zip(oldMean, vector).map { $0 + ($1 - $0) / count })
        current.variance = current.variance.indices.map { index in
            current.variance[index] + (vector[index] - oldMean[index]) * (vector[index] - current.centroid[index]) / count
        }
        current.sampleCount += 1
        current.displayName = displayName
        current.timestamps = Array((current.timestamps + [date]).suffix(20))
        current.confidenceHistory = Array((current.confidenceHistory + [confidence]).suffix(20))
        prototypes[exerciseID] = current
    }

    public func classify(_ representation: [Double]) -> ExerciseClassification {
        guard valid(representation) else { return .init(exerciseID: nil, confidence: 0, needsConfirmation: true) }
        let ranked = prototypes.values.filter { $0.sampleCount >= 2 && $0.centroid.count == representation.count }.map { ($0.exerciseID, cosine($0.centroid, representation)) }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return .init(exerciseID: nil, confidence: 0, needsConfirmation: true) }
        let margin = ranked.count > 1 ? best.1 - ranked[1].1 : best.1
        let accepted = best.1 >= 0.90 && margin >= 0.08
        return .init(exerciseID: accepted ? best.0 : nil, confidence: best.1, needsConfirmation: !accepted)
    }
}

public enum MovementDeviationDirection: String, Codable, Equatable, Sendable { case belowUsual, aboveUsual }
public struct MovementDeviation: Equatable, Sendable {
    public let direction: MovementDeviationDirection
    public let observed: Double
    public let median: Double
    public let dispersion: Double
    public let sampleCount: Int
}

public struct PersonalMovementBaseline: Codable, Equatable, Sendable {
    private var history: [String: [Double]] = [:]
    public init() {}

    public mutating func observe(exerciseID: String, feature: String, value: Double, confidence: Double) {
        guard value.isFinite, confidence >= 0.6 else { return }
        let key = "\(exerciseID):\(feature)"
        history[key] = Array((history[key, default: []] + [value]).suffix(30))
    }

    public func deviation(exerciseID: String, feature: String, value: Double, confidence: Double) -> MovementDeviation? {
        let values = history["\(exerciseID):\(feature)"] ?? []
        guard value.isFinite, confidence >= 0.6, values.count >= 5 else { return nil }
        let center = median(values)
        let dispersion = max(median(values.map { abs($0 - center) }) * 1.4826, 0.03)
        guard abs(value - center) > max(3 * dispersion, 0.08) else { return nil }
        return MovementDeviation(direction: value < center ? .belowUsual : .aboveUsual, observed: value, median: center, dispersion: dispersion, sampleCount: values.count)
    }
}

public struct ContinualPersonalizationState: Codable, Equatable, Sendable {
    public var version = 1
    public var identity = PersonalIdentityGallery()
    public var exercises = ExercisePrototypeLibrary()
    public var movement = PersonalMovementBaseline()
    public init() {}
    public mutating func reset() { self = Self() }
}

private func valid(_ vector: [Double]) -> Bool { !vector.isEmpty && vector.allSatisfy(\.isFinite) && vector.contains { $0 != 0 } }
private func normalized(_ vector: [Double]) -> [Double] {
    let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
    return magnitude > 0 ? vector.map { $0 / magnitude } : vector
}
private func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double { zip(normalized(lhs), normalized(rhs)).reduce(0) { $0 + $1.0 * $1.1 } }
private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted(); let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}
