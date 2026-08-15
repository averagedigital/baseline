import AthleteCore
import Foundation

public enum CoachClaimType: String, Codable, Sendable { case observed, computed, userReported, inference, recommendation }

public struct GroundedFact: Codable, Equatable, Sendable {
    public let id: String; public let value: String; public let numericValue: Double?
    public init(id: String, value: String, numericValue: Double? = nil) { self.id = id; self.value = value; self.numericValue = numericValue }
}

public struct CoachClaim: Codable, Equatable, Sendable {
    public let text: String; public let factIDs: [String]; public let epistemicType: CoachClaimType
    public init(text: String, factIDs: [String], epistemicType: CoachClaimType) { self.text = text; self.factIDs = factIDs; self.epistemicType = epistemicType }
}

public struct CoachOutput: Codable, Equatable, Sendable {
    public let claims: [CoachClaim]; public let recommendationAction: String?
    public init(claims: [CoachClaim], recommendationAction: String? = nil) { self.claims = claims; self.recommendationAction = recommendationAction }
}

public struct CoachGenerationRequest: Sendable { public let prompt: String; public let facts: [GroundedFact] }
public protocol CoachGenerating: Sendable { func generate(request: CoachGenerationRequest) async throws -> CoachOutput }

public enum GroundingError: Error, Equatable { case unknownFact(String); case numericMismatch(String); case missingNumericFact(String) }

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
    public func generate(request: CoachGenerationRequest) async throws -> CoachOutput {
        CoachOutput(claims: [CoachClaim(text: "Локальная языковая модель недоступна на этом устройстве. Все измерения и история продолжают работать локально.", factIDs: [], epistemicType: .recommendation)])
    }
}
