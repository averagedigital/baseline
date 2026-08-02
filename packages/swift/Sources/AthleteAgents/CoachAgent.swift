import AthleteCore
import Foundation

public struct CoachTurn: Equatable, Sendable {
    public let text: String
    public let providerID: String
    public let modelID: String
    public let planProposal: PlanProposal?

    public init(text: String, providerID: String, modelID: String, planProposal: PlanProposal?) {
        self.text = text
        self.providerID = providerID
        self.modelID = modelID
        self.planProposal = planProposal
    }
}

public struct CoachAgent: Sendable {
    private let provider: any LLMProvider

    public init(provider: any LLMProvider) {
        self.provider = provider
    }

    public func respond(context: String, promptVersion: String) async throws -> CoachTurn {
        let response = try await provider.complete(AgentRequest(
            role: .coach,
            promptVersion: promptVersion,
            context: context
        ))
        let proposal = response.planProposalMarkdown.map {
            PlanProposal(markdown: $0, evidenceIDs: [])
        }
        return CoachTurn(
            text: response.text,
            providerID: response.providerID,
            modelID: response.modelID,
            planProposal: proposal
        )
    }
}

public actor PlanLedger {
    public private(set) var activePlan: PlanProposal?
    private var proposals: [PlanProposal.ID: PlanProposal] = [:]

    public init() {}

    public func submit(_ proposal: PlanProposal) {
        proposals[proposal.id] = proposal
    }

    public func approve(proposalID: PlanProposal.ID) throws -> PlanEvent {
        guard let proposal = proposals.removeValue(forKey: proposalID) else {
            throw PlanLedgerError.proposalNotFound(proposalID)
        }
        activePlan = proposal
        return PlanEvent(proposalID: proposalID, decision: .approved)
    }

    public func reject(proposalID: PlanProposal.ID) throws -> PlanEvent {
        guard proposals.removeValue(forKey: proposalID) != nil else {
            throw PlanLedgerError.proposalNotFound(proposalID)
        }
        return PlanEvent(proposalID: proposalID, decision: .rejected)
    }
}

public enum PlanLedgerError: Error, Equatable, Sendable {
    case proposalNotFound(UUID)
}
