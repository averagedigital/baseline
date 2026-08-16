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
                .number("session:latest:active_minutes", session.activeMinutes),
                .number("session:latest:active_blocks", Double(session.activeBlocks)),
                .number("session:latest:tracking_coverage", session.coverage),
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

public struct CoachOrchestrator: Sendable {
    private let generator: any CoachGenerating

    public init(generator: any CoachGenerating) { self.generator = generator }

    public func generate(request: CoachGenerationRequest) async throws -> CoachOutput {
        let first = try await generator.generate(request: request)
        do {
            try GroundingValidator().validate(first, facts: request.facts)
            return first
        } catch let validationError as GroundingError {
            let previous = String(data: (try? JSONEncoder().encode(first)) ?? Data(), encoding: .utf8) ?? ""
            let repair = CoachGenerationRequest(
                prompt: "PREVIOUS_OUTPUT\n\(previous)\nVALIDATION_ERRORS\n- \(validationError)\nORIGINAL_USER_REQUEST\n\(request.prompt)",
                facts: request.facts,
                conversation: request.conversation,
                threadID: request.threadID
            )
            let repaired = try await generator.generate(request: repair)
            try GroundingValidator().validate(repaired, facts: request.facts)
            return repaired
        }
    }
}

public enum GroundingError: Error, Equatable { case unknownFact(String); case duplicateFactID(String); case numericMismatch(String); case missingNumericFact(String) }
public enum CoachGenerationError: Error, Equatable { case unavailable, unsupportedLocale, contextWindowExceeded, refused, failed }

public struct GroundingValidator: Sendable {
    public init() {}
    public func validate(_ output: CoachOutput, facts: [GroundedFact]) throws {
        var byID: [String: GroundedFact] = [:]
        for fact in facts {
            guard byID[fact.id] == nil else { throw GroundingError.duplicateFactID(fact.id) }
            byID[fact.id] = fact
        }
        for claim in output.claims {
            for id in claim.factIDs { guard byID[id] != nil else { throw GroundingError.unknownFact(id) } }
            if claim.epistemicType == .inference && claim.factIDs.isEmpty { throw GroundingError.missingNumericFact(claim.text) }
            for mention in NumericMention.parse(claim.text) {
                guard claim.factIDs.contains(where: { factMatches(byID[$0], mention: mention) }) else {
                    throw GroundingError.numericMismatch(claim.text)
                }
            }
        }
    }

    private func factMatches(_ fact: GroundedFact?, mention: NumericMention) -> Bool {
        guard let value = fact?.numberValue else { return false }
        let canonical = mention.isPercent ? value * 100 : value
        return abs(canonical - mention.value) <= 0.000001
            || (mention.isPercent && abs(value - mention.value) <= 0.000001)
    }
}

private struct NumericMention {
    let value: Double
    let isPercent: Bool

    static func parse(_ text: String) -> [NumericMention] {
        let pattern = #"(?<![\p{L}\d])\d+(?:[\.,]\d+)?(?:\s*[-–]\s*\d+(?:[\.,]\d+)?)?\s*%?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, range: range).flatMap { match -> [NumericMention] in
            guard let swiftRange = Range(match.range, in: text) else { return [] }
            let raw = String(text[swiftRange]).replacingOccurrences(of: " ", with: "")
            let isPercent = raw.hasSuffix("%")
            let numeric = isPercent ? String(raw.dropLast()) : raw
            let endpoints = numeric.split { $0 == "-" || $0 == "–" }.compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            return endpoints.map { NumericMention(value: $0, isPercent: isPercent) }
        }
    }
}

public struct UnavailableCoachGenerator: CoachGenerating {
    public init() {}
    public func generate(request: CoachGenerationRequest) async throws -> CoachOutput { throw CoachGenerationError.unavailable }
}
