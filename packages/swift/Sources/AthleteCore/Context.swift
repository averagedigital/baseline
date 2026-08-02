import Foundation

public enum ContextPurpose: String, Codable, Hashable, Sendable {
    case coverage
    case analysis
    case previousMemory
    case goal
    case plan
}

public struct ContextFragment: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let moduleID: String
    public let scope: DateInterval
    public let purpose: ContextPurpose
    public let evidenceIDs: [UUID]
    public let estimatedTokenCount: Int
    public let markdown: String

    public init(
        id: String,
        moduleID: String,
        scope: DateInterval,
        purpose: ContextPurpose,
        evidenceIDs: [UUID],
        estimatedTokenCount: Int,
        markdown: String
    ) {
        self.id = id
        self.moduleID = moduleID
        self.scope = scope
        self.purpose = purpose
        self.evidenceIDs = evidenceIDs
        self.estimatedTokenCount = estimatedTokenCount
        self.markdown = markdown
    }
}
