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
    struct Handle {
        let session: LanguageModelSession
        let isNew: Bool
    }

    private var sessions: [UUID: LanguageModelSession] = [:]
    private var lastUsed: [UUID: UInt64] = [:]
    private var tick: UInt64 = 0
    private let maximumSessions = 4

    @available(iOS 26.0, *)
    func session(for threadID: UUID, instructions: String) -> Handle {
        tick += 1
        if let session = sessions[threadID] {
            lastUsed[threadID] = tick
            return Handle(session: session, isNew: false)
        }
        let session = LanguageModelSession(instructions: instructions)
        sessions[threadID] = session
        lastUsed[threadID] = tick
        while sessions.count > maximumSessions, let oldest = lastUsed.min(by: { $0.value < $1.value })?.key {
            sessions.removeValue(forKey: oldest)
            lastUsed.removeValue(forKey: oldest)
        }
        return Handle(session: session, isNew: true)
    }

    func reset(threadID: UUID) {
        sessions.removeValue(forKey: threadID)
        lastUsed.removeValue(forKey: threadID)
    }
}
#endif

struct FoundationModelsCoachAdapter: CoachGenerating, @unchecked Sendable {
    let availability: LocalCoachAvailability
    private let sessions: AnyObject?

    init(locale: Locale = .current) {
        _ = locale
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                availability = .available
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
        let handle = await store.session(for: threadID, instructions: instructions)
        let facts = request.facts.map { "\($0.id)=\($0.displayValue)" }.joined(separator: "\n")
        let history = request.conversation.suffix(8).map { "\($0.role.rawValue): \($0.text)" }.joined(separator: "\n")
        let bootstrap = handle.isNew && !history.isEmpty ? "BOOTSTRAP_CONVERSATION\n\(history)\n" : ""
        do {
            let response = try await handle.session.respond(to: "\(bootstrap)FACTS\n\(facts)\nUSER\n\(request.prompt)", generating: GeneratedCoachOutput.self)
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

    func reset(threadID: UUID) async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), let store = sessions as? FoundationModelsSessionStore {
            await store.reset(threadID: threadID)
        }
        #endif
    }
}
