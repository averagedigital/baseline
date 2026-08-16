import AthleteIntelligence
import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum LocalCoachAvailability: Equatable, Sendable { case available, frameworkUnavailable, deviceUnsupported, appleIntelligenceDisabled, modelNotReady, unsupportedLocale, failed(String) }

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
private struct GeneratedCoachClaim {
    @Guide(description: "Краткое утверждение для пользователя") var text: String
    @Guide(description: "Fact IDs, подтверждающие утверждение") var factIDs: [String]
    @Guide(description: "Только observed, computed, userReported, inference или recommendation") var epistemicType: String
}

@available(iOS 26.0, *)
@Generable
private struct GeneratedCoachOutput {
    var claims: [GeneratedCoachClaim]
    @Guide(description: "Только technique, load, recovery, nutrition, consistency или пусто") var recommendationAction: String?
}

@available(iOS 26.0, *)
private actor FoundationModelsSessionStore {
    private var sessions: [UUID: LanguageModelSession] = [:]

    @available(iOS 26.0, *)
    func session(for threadID: UUID, instructions: String) -> LanguageModelSession {
        if let session = sessions[threadID] { return session }
        let session = LanguageModelSession(instructions: instructions)
        sessions[threadID] = session
        return session
    }
}
#endif

struct FoundationModelsCoachAdapter: CoachGenerating, @unchecked Sendable {
    let availability: LocalCoachAvailability
    private let sessions: AnyObject?

    init(locale: Locale = .current) {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                availability = SystemLanguageModel.default.supportsLocale(locale) ? .available : .unsupportedLocale
            case .unavailable(.deviceNotEligible): availability = .deviceUnsupported
            case .unavailable(.appleIntelligenceNotEnabled): availability = .appleIntelligenceDisabled
            case .unavailable(.modelNotReady): availability = .modelNotReady
            @unknown default: availability = .failed("unknown availability")
            }
            sessions = FoundationModelsSessionStore()
        } else { availability = .frameworkUnavailable; sessions = nil }
        #else
        availability = .frameworkUnavailable; sessions = nil
        #endif
    }

    func generate(request: CoachGenerationRequest) async throws -> CoachOutput {
        #if canImport(FoundationModels)
        guard case .available = availability, #available(iOS 26.0, *) else { throw CoachGenerationError.unavailable }
        let locale = request.prompt.range(of: #"[А-Яа-яЁё]"#, options: .regularExpression) != nil ? Locale(identifier: "ru-RU") : .current
        guard SystemLanguageModel.default.supportsLocale(locale) else { throw CoachGenerationError.unsupportedLocale }
        guard let store = sessions as? FoundationModelsSessionStore else { throw CoachGenerationError.failed }
        let threadID = request.threadID ?? UUID()
        let instructions = "Отвечай на языке последнего сообщения пользователя. Используй только переданные facts и их IDs. Не выдумывай числа."
        let session = await store.session(for: threadID, instructions: instructions)
        let facts = request.facts.map { "\($0.id)=\($0.displayValue)" }.joined(separator: "\n")
        let history = request.conversation.suffix(12).map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        do {
            let response = try await session.respond(to: "FACTS\n\(facts)\nRECENT_CONVERSATION\n\(history)\nUSER\n\(request.prompt)", generating: GeneratedCoachOutput.self)
            return CoachOutput(claims: response.content.claims.compactMap { claim in
                guard let type = CoachClaimType(rawValue: claim.epistemicType) else { return nil }
                return CoachClaim(text: claim.text, factIDs: claim.factIDs, epistemicType: type)
            }, recommendationAction: response.content.recommendationAction)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .unsupportedLanguageOrLocale: throw CoachGenerationError.unsupportedLocale
            case .exceededContextWindowSize: throw CoachGenerationError.contextWindowExceeded
            case .guardrailViolation, .refusal: throw CoachGenerationError.refused
            default: throw CoachGenerationError.failed
            }
        }
        #else
        throw CoachGenerationError.unavailable
        #endif
    }
}
