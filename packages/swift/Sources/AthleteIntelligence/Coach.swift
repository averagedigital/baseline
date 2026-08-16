import AthleteCore
import Foundation

public enum CoachClaimType: String, Codable, Sendable { case observed, computed, userReported, inference, recommendation }

public enum GroundedFactValueType: String, Codable, Sendable { case number, text, boolean }

public struct GroundedFact: Codable, Equatable, Sendable {
    public let id: String
    public let type: GroundedFactValueType
    public let numberValue: Double?
    public let textValue: String?
    public let booleanValue: Bool?
    public let sourceEvidenceID: UUID?
    public let sourceFoodObservationID: UUID?

    private init(id: String, type: GroundedFactValueType, numberValue: Double?, textValue: String?, booleanValue: Bool?, sourceEvidenceID: UUID?, sourceFoodObservationID: UUID?) {
        self.id = id; self.type = type; self.numberValue = numberValue; self.textValue = textValue; self.booleanValue = booleanValue
        self.sourceEvidenceID = sourceEvidenceID; self.sourceFoodObservationID = sourceFoodObservationID
    }
    public static func number(_ id: String, _ value: Double, sourceEvidenceID: UUID? = nil, sourceFoodObservationID: UUID? = nil) -> GroundedFact { GroundedFact(id: id, type: .number, numberValue: value, textValue: nil, booleanValue: nil, sourceEvidenceID: sourceEvidenceID, sourceFoodObservationID: sourceFoodObservationID) }
    public static func text(_ id: String, _ value: String, sourceEvidenceID: UUID? = nil, sourceFoodObservationID: UUID? = nil) -> GroundedFact { GroundedFact(id: id, type: .text, numberValue: nil, textValue: value, booleanValue: nil, sourceEvidenceID: sourceEvidenceID, sourceFoodObservationID: sourceFoodObservationID) }
    public static func boolean(_ id: String, _ value: Bool, sourceEvidenceID: UUID? = nil, sourceFoodObservationID: UUID? = nil) -> GroundedFact { GroundedFact(id: id, type: .boolean, numberValue: nil, textValue: nil, booleanValue: value, sourceEvidenceID: sourceEvidenceID, sourceFoodObservationID: sourceFoodObservationID) }
    public var displayValue: String { numberValue.map { String($0) } ?? textValue ?? booleanValue.map(String.init) ?? "" }
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
                .number("session.active_minutes", session.activeMinutes),
                .number("session.active_blocks", Double(session.activeBlocks)),
                .number("session.coverage", session.coverage),
            ]
        }
        if let personalization, let prediction = personalization.predictedDifficulty {
            facts.append(.number("personalization.predicted_difficulty", prediction))
        }
        if let food, let calories = food.caloriesMidpoint {
            facts.append(.number("food.calories_midpoint", calories))
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

public struct CoachConversationTurn: Codable, Equatable, Sendable { public enum Role: String, Codable, Sendable { case user, assistant }; public let role: Role; public let text: String; public init(role: Role, text: String) { self.role = role; self.text = text } }
public struct CoachGenerationRequest: Sendable { public let prompt: String; public let facts: [GroundedFact]; public let conversation: [CoachConversationTurn]; public let threadID: UUID?; public init(prompt: String, facts: [GroundedFact], conversation: [CoachConversationTurn] = [], threadID: UUID? = nil) { self.prompt = prompt; self.facts = facts; self.conversation = conversation; self.threadID = threadID } }
public protocol CoachGenerating: Sendable { func generate(request: CoachGenerationRequest) async throws -> CoachOutput }

public enum GroundingError: Error, Equatable { case unknownFact(String); case numericMismatch(String); case missingNumericFact(String) }
public enum CoachGenerationError: Error, Equatable { case unavailable, unsupportedLocale, contextWindowExceeded, refused, failed }

public struct GroundingValidator: Sendable {
    public init() {}
    public func validate(_ output: CoachOutput, facts: [GroundedFact]) throws {
        let byID = Dictionary(uniqueKeysWithValues: facts.map { ($0.id, $0) })
        for claim in output.claims {
            for id in claim.factIDs { guard byID[id] != nil else { throw GroundingError.unknownFact(id) } }
            if claim.epistemicType == .inference && claim.factIDs.isEmpty { throw GroundingError.missingNumericFact(claim.text) }
            let normalized = claim.text.replacingOccurrences(of: ",", with: ".")
            let numbers = normalized.split { !$0.isNumber && $0 != "." && $0 != "-" }.compactMap { Double($0) }
            for number in numbers where !claim.text.contains("\(number)%") {
                guard claim.factIDs.contains(where: { byID[$0]?.numberValue == number }) else { throw GroundingError.numericMismatch(claim.text) }
            }
        }
    }
}

public struct UnavailableCoachGenerator: CoachGenerating {
    public init() {}
    public func generate(request: CoachGenerationRequest) async throws -> CoachOutput { throw CoachGenerationError.unavailable }
}
