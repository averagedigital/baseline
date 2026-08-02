import Foundation

public enum EpistemicRole: String, Codable, Hashable, Sendable {
    case observed
    case computed
    case inferred
    case userReported
}

public enum PrivacyClass: String, Codable, Hashable, Sendable {
    case standard
    case sensitiveLocal
    case sensitiveExportable
}

public struct Provenance: Codable, Hashable, Sendable {
    public let sourceID: String
    public let producerID: String
    public let producerVersion: String
    public let method: String?

    public init(sourceID: String, producerID: String, producerVersion: String, method: String?) {
        self.sourceID = sourceID
        self.producerID = producerID
        self.producerVersion = producerVersion
        self.method = method
    }
}

public struct PayloadReference: Codable, Hashable, Sendable {
    public let mediaType: String
    public let schemaID: String?
    public let schemaVersion: String?
    public let storageURI: String

    public init(mediaType: String, schemaID: String?, schemaVersion: String?, storageURI: String) {
        self.mediaType = mediaType
        self.schemaID = schemaID
        self.schemaVersion = schemaVersion
        self.storageURI = storageURI
    }
}

public struct EvidenceEnvelope: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let moduleID: String
    public let moduleVersion: String
    public let kind: String
    public let observedFrom: Date
    public let observedTo: Date
    public let ingestedAt: Date
    public let epistemicRole: EpistemicRole
    public let provenance: Provenance
    public let privacyClass: PrivacyClass
    public let payload: PayloadReference
    public let derivedFrom: [UUID]
    public let supersedes: UUID?
    public let contentDigest: String

    public init(
        id: UUID,
        moduleID: String,
        moduleVersion: String,
        kind: String,
        observedFrom: Date,
        observedTo: Date,
        ingestedAt: Date,
        epistemicRole: EpistemicRole,
        provenance: Provenance,
        privacyClass: PrivacyClass,
        payload: PayloadReference,
        derivedFrom: [UUID],
        supersedes: UUID?,
        contentDigest: String
    ) {
        self.id = id
        self.moduleID = moduleID
        self.moduleVersion = moduleVersion
        self.kind = kind
        self.observedFrom = observedFrom
        self.observedTo = observedTo
        self.ingestedAt = ingestedAt
        self.epistemicRole = epistemicRole
        self.provenance = provenance
        self.privacyClass = privacyClass
        self.payload = payload
        self.derivedFrom = derivedFrom
        self.supersedes = supersedes
        self.contentDigest = contentDigest
    }
}

public struct UserCorrection: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let evidenceID: UUID
    public let supersedes: UUID
    public let createdAt: Date
    public let reason: String

    public init(id: UUID, evidenceID: UUID, supersedes: UUID, createdAt: Date, reason: String) {
        self.id = id
        self.evidenceID = evidenceID
        self.supersedes = supersedes
        self.createdAt = createdAt
        self.reason = reason
    }
}

public struct AnalysisArtifact: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let toolID: String
    public let toolVersion: String
    public let scope: DateInterval
    public let inputEvidenceIDs: [UUID]
    public let parametersDigest: String
    public let resultURI: String
    public let resultMediaType: String
    public let createdAt: Date
    public let contentDigest: String

    public init(
        id: UUID,
        toolID: String,
        toolVersion: String,
        scope: DateInterval,
        inputEvidenceIDs: [UUID],
        parametersDigest: String,
        resultURI: String,
        resultMediaType: String,
        createdAt: Date,
        contentDigest: String
    ) {
        self.id = id
        self.toolID = toolID
        self.toolVersion = toolVersion
        self.scope = scope
        self.inputEvidenceIDs = inputEvidenceIDs
        self.parametersDigest = parametersDigest
        self.resultURI = resultURI
        self.resultMediaType = resultMediaType
        self.createdAt = createdAt
        self.contentDigest = contentDigest
    }
}

public enum MemoryKind: String, Codable, Hashable, Sendable {
    case profile
    case currentState
    case session
    case daily
    case weekly
    case monthly
    case movementProfile
    case hypothesis
    case goal
    case preference
    case constraint
    case plan
    case experiment
}

public enum MemoryDependency: Codable, Hashable, Sendable {
    case evidence(UUID)
    case artifact(UUID)
}

public enum VerificationStatus: String, Codable, Hashable, Sendable {
    case verified
    case needsReview
    case rejected
    case stale
}

public struct MemoryDocument: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let kind: MemoryKind
    public let scope: DateInterval
    public let revision: Int
    public let createdAt: Date
    public let supersedes: UUID?
    public let basedOn: [MemoryDependency]
    public let modelID: String
    public let providerID: String
    public let promptVersion: String
    public let inputDigest: String
    public let verificationStatus: VerificationStatus
    public let markdown: String

    public init(
        id: UUID,
        kind: MemoryKind,
        scope: DateInterval,
        revision: Int,
        createdAt: Date,
        supersedes: UUID?,
        basedOn: [MemoryDependency],
        modelID: String,
        providerID: String,
        promptVersion: String,
        inputDigest: String,
        verificationStatus: VerificationStatus,
        markdown: String
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.revision = revision
        self.createdAt = createdAt
        self.supersedes = supersedes
        self.basedOn = basedOn
        self.modelID = modelID
        self.providerID = providerID
        self.promptVersion = promptVersion
        self.inputDigest = inputDigest
        self.verificationStatus = verificationStatus
        self.markdown = markdown
    }
}
