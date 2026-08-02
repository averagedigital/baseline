import Foundation

public struct PlanProposal: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let markdown: String
    public let evidenceIDs: [UUID]
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        markdown: String,
        evidenceIDs: [UUID],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.markdown = markdown
        self.evidenceIDs = evidenceIDs
        self.createdAt = createdAt
    }
}

public enum PlanDecision: String, Codable, Equatable, Sendable {
    case approved
    case rejected
}

public struct PlanEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let proposalID: UUID
    public let decision: PlanDecision
    public let createdAt: Date

    public init(id: UUID = UUID(), proposalID: UUID, decision: PlanDecision, createdAt: Date = Date()) {
        self.id = id
        self.proposalID = proposalID
        self.decision = decision
        self.createdAt = createdAt
    }
}
