import AthletePersonalization
import AthleteSensors
import AthleteStore
import Foundation

struct PersonalizationFeatureBuilder: Sendable {
    let store: AthleteStore

    func features(for sessionEvidenceID: UUID) async throws -> PersonalizationFeatures {
        guard try await store.evidence(id: sessionEvidenceID) != nil,
              let source = try await store.payload(for: sessionEvidenceID, as: SessionEvidenceV2.self) else {
            throw AthleteStoreError.invalidIdentifier(sessionEvidenceID.uuidString)
        }
        let envelopes = try await store.evidenceEnvelopes(kind: "activity.session.v2", observedBefore: source.observedTo)
        let sessions = try await envelopes.asyncCompactMap { envelope in
            try await store.payload(for: envelope.id, as: SessionEvidenceV2.self).map { (envelope, $0) }
        }
        let weekStart = source.observedTo.addingTimeInterval(-7 * 24 * 60 * 60)
        let weekMinutes = sessions.filter { $0.0.observedTo >= weekStart }.reduce(0) { $0 + $1.1.activeTime / 60 }
        let previous = sessions.first { $0.1.observedTo < source.observedFrom }
        let hoursSincePrevious = previous.map { max(0, source.observedFrom.timeIntervalSince($0.1.observedTo) / 3600) } ?? 0
        let foods = try await store.recentFoodObservations(limit: 50)
        let eligibleFoods = foods.filter { observation in
            observation.capturedAt <= source.observedTo && !observation.dismissed
        }.prefix(7)
        let nutritionSignal = eligibleFoods.reduce(0.0) { total, observation in
            guard let analysis = try? JSONDecoder().decode(LocalFoodAnalysis.self, from: observation.payload) else { return total }
            guard let low = analysis.caloriesLow, let high = analysis.caloriesHigh else { return total }
            return total + (low + high) / 2
        }
        return PersonalizationFeatures(
            activeMinutes: source.activeTime / 60,
            setCount: Double(source.activeBlockCount),
            trackingCoverage: source.trackingCoverage,
            workRestRatio: source.activeTime / max(source.restTime, 60),
            recentActiveMinutes: weekMinutes,
            hoursSincePrevious: hoursSincePrevious,
            nutritionSignal: nutritionSignal
        )
    }
}

private extension Array where Element: Sendable {
    func asyncCompactMap<T: Sendable>(_ transform: (Element) async throws -> T?) async throws -> [T] {
        var result: [T] = []
        for element in self { if let value = try await transform(element) { result.append(value) } }
        return result
    }
}
