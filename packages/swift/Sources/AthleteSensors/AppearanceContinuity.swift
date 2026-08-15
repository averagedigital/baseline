import Foundation

public struct AppearanceSignature: Equatable, Sendable {
    public let values: [Float]

    public init(values: [Float]) { self.values = values }
}

public protocol AppearanceComparing: Sendable {
    func distance(_ lhs: AppearanceSignature, _ rhs: AppearanceSignature) -> Double
}

public struct EuclideanAppearanceComparator: AppearanceComparing {
    public init() {}

    public func distance(_ lhs: AppearanceSignature, _ rhs: AppearanceSignature) -> Double {
        guard lhs.values.count == rhs.values.count, !lhs.values.isEmpty else { return .infinity }
        let sum = zip(lhs.values, rhs.values).reduce(0.0) { result, pair in
            let delta = Double(pair.0 - pair.1)
            return result + delta * delta
        }
        return sqrt(sum / Double(lhs.values.count))
    }
}
