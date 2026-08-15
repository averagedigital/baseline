import AthleteIntelligence
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum LocalCoachAvailability: Equatable, Sendable { case available, frameworkUnavailable, deviceUnsupported, appleIntelligenceDisabled, modelNotReady, failed(String) }

struct FoundationModelsCoachAdapter: CoachGenerating, @unchecked Sendable {
    let availability: LocalCoachAvailability

    init() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: availability = .available
            case .unavailable(.deviceNotEligible): availability = .deviceUnsupported
            case .unavailable(.appleIntelligenceNotEnabled): availability = .appleIntelligenceDisabled
            case .unavailable(.modelNotReady): availability = .modelNotReady
            @unknown default: availability = .failed("unknown availability")
            }
        } else { availability = .frameworkUnavailable }
        #else
        availability = .frameworkUnavailable
        #endif
    }

    func generate(request: CoachGenerationRequest) async throws -> CoachOutput {
        #if canImport(FoundationModels)
        guard case .available = availability else { throw CoachGenerationError.unavailable }
        guard #available(iOS 26.0, *) else { throw CoachGenerationError.unavailable }
        let facts = request.facts.map { "\($0.id)=\($0.value)" }.joined(separator: "\n")
        let instructions = "Return only JSON matching CoachOutput: {claims:[{text,factIDs,epistemicType}],recommendationAction}. Use only fact IDs and numbers from facts."
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(to: "Facts:\n\(facts)\nUser: \(request.prompt)")
        guard let data = response.content.data(using: .utf8) else { throw CoachGenerationError.unavailable }
        return try JSONDecoder().decode(CoachOutput.self, from: data)
        #else
        throw CoachGenerationError.unavailable
        #endif
    }
}
