import AthleteCore
import Foundation

public enum CoachClaimType: String, Codable, Sendable { case observed, computed, userReported, inference, recommendation }

public struct GroundedFact: Codable, Equatable, Sendable {
    public let id: String; public let value: String; public let numericValue: Double?
    public init(id: String, value: String, numericValue: Double? = nil) { self.id = id; self.value = value; self.numericValue = numericValue }
}

public struct CoachContext: Codable, Equatable, Sendable {
    public let facts: [GroundedFact]
    public init(facts: [GroundedFact]) { self.facts = facts }
}

public struct CoachContextAssembler: Sendable {
    public init() {}
    public func assemble(session: SessionFacts?, personalization: PersonalizationFacts?, food: FoodFacts?) -> CoachContext {
        var facts: [GroundedFact] = []
        if let session {
            facts += [
                GroundedFact(id: "session.active_minutes", value: String(format: "%.1f", session.activeMinutes), numericValue: session.activeMinutes),
                GroundedFact(id: "session.active_blocks", value: "\(session.activeBlocks)", numericValue: Double(session.activeBlocks)),
                GroundedFact(id: "session.coverage", value: String(format: "%.2f", session.coverage), numericValue: session.coverage),
            ]
        }
        if let personalization, let prediction = personalization.predictedDifficulty {
            facts.append(GroundedFact(id: "personalization.predicted_difficulty", value: String(format: "%.1f", prediction), numericValue: prediction))
        }
        if let food, let calories = food.caloriesMidpoint {
            facts.append(GroundedFact(id: "food.calories_midpoint", value: String(format: "%.0f", calories), numericValue: calories))
        }
        return CoachContext(facts: facts)
    }
}

public struct SessionFacts: Codable, Equatable, Sendable { public let activeMinutes: Double; public let activeBlocks: Int; public let coverage: Double; public init(activeMinutes: Double, activeBlocks: Int, coverage: Double) { self.activeMinutes = activeMinutes; self.activeBlocks = activeBlocks; self.coverage = coverage } }
public struct PersonalizationFacts: Codable, Equatable, Sendable { public let predictedDifficulty: Double?; public init(predictedDifficulty: Double?) { self.predictedDifficulty = predictedDifficulty } }
public struct FoodFacts: Codable, Equatable, Sendable { public let caloriesMidpoint: Double?; public init(caloriesMidpoint: Double?) { self.caloriesMidpoint = caloriesMidpoint } }

public struct CoachClaim: Codable, Equatable, Sendable {
    public let text: String; public let factIDs: [String]; public let epistemicType: CoachClaimType
    public init(text: String, factIDs: [String], epistemicType: CoachClaimType) { self.text = text; self.factIDs = factIDs; self.epistemicType = epistemicType }
}

public struct CoachOutput: Codable, Equatable, Sendable {
    public let claims: [CoachClaim]; public let recommendationAction: String?
    public init(claims: [CoachClaim], recommendationAction: String? = nil) { self.claims = claims; self.recommendationAction = recommendationAction }
}

public struct CoachGenerationRequest: Sendable { public let prompt: String; public let facts: [GroundedFact]; public init(prompt: String, facts: [GroundedFact]) { self.prompt = prompt; self.facts = facts } }
public protocol CoachGenerating: Sendable { func generate(request: CoachGenerationRequest) async throws -> CoachOutput }

public enum GroundingError: Error, Equatable { case unknownFact(String); case numericMismatch(String); case missingNumericFact(String) }
public enum CoachGenerationError: Error, Equatable { case unavailable }

public struct GroundingValidator: Sendable {
    public init() {}
    public func validate(_ output: CoachOutput, facts: [GroundedFact]) throws {
        let byID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
        for claim in output.claims {
            for id in claim.factIDs { guard byID[id] != nil else { throw GroundingError.unknownFact(id) } }
            if claim.epistemicType == .inference && claim.factIDs.isEmpty { throw GroundingError.missingNumericFact(claim.text) }
            let numbers = claim.text.split { !$0.isNumber && $0 != "." }.compactMap { Double($0) }
            for number in numbers {
                guard claim.factIDs.contains(where: { byID[$0]?.numericValue == number }) else { throw GroundingError.numericMismatch(claim.text) }
            }
        }
    }
}

public struct UnavailableCoachGenerator: CoachGenerating {
    public init() {}
    public func generate(request: CoachGenerationRequest) async throws -> CoachOutput { throw CoachGenerationError.unavailable }
}
