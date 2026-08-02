public enum AgentRole: String, Sendable {
    case stateBuilder
    case coach
}

public struct AgentRequest: Equatable, Sendable {
    public let role: AgentRole
    public let promptVersion: String
    public let context: String

    public init(role: AgentRole, promptVersion: String, context: String) {
        self.role = role
        self.promptVersion = promptVersion
        self.context = context
    }
}

public struct AgentResponse: Equatable, Sendable {
    public let text: String
    public let providerID: String
    public let modelID: String
    public let planProposalMarkdown: String?

    public init(
        text: String,
        providerID: String,
        modelID: String,
        planProposalMarkdown: String? = nil
    ) {
        self.text = text
        self.providerID = providerID
        self.modelID = modelID
        self.planProposalMarkdown = planProposalMarkdown
    }
}

public protocol LLMProvider: Sendable {
    func complete(_ request: AgentRequest) async throws -> AgentResponse
}

public actor MockProvider: LLMProvider {
    private var responses: [AgentResponse]

    public init(responses: [AgentResponse]) {
        self.responses = responses
    }

    public func complete(_ request: AgentRequest) throws -> AgentResponse {
        guard !responses.isEmpty else {
            throw MockProviderError.noResponse
        }
        return responses.removeFirst()
    }
}

public enum MockProviderError: Error, Equatable, Sendable {
    case noResponse
}
