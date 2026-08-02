import Foundation

public enum ContextScope: String, Codable, Hashable, Sendable {
    case session
    case daily
    case weekly
    case monthly
}

public struct ModuleManifest: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let version: String
    public let displayName: String
    public let producedEvidenceKinds: [String]
    public let supportedContextScopes: [ContextScope]
    public let toolIDs: [String]
    public let privacyClass: PrivacyClass
    public let requiresUserConsent: Bool
    public let supportsLocalProcessing: Bool

    public init(
        id: String,
        version: String,
        displayName: String,
        producedEvidenceKinds: [String],
        supportedContextScopes: [ContextScope],
        toolIDs: [String],
        privacyClass: PrivacyClass,
        requiresUserConsent: Bool,
        supportsLocalProcessing: Bool
    ) {
        self.id = id
        self.version = version
        self.displayName = displayName
        self.producedEvidenceKinds = producedEvidenceKinds
        self.supportedContextScopes = supportedContextScopes
        self.toolIDs = toolIDs
        self.privacyClass = privacyClass
        self.requiresUserConsent = requiresUserConsent
        self.supportsLocalProcessing = supportsLocalProcessing
    }
}

public protocol AthleteModule: Sendable {
    var manifest: ModuleManifest { get }
}

public enum ModuleRegistryError: Error, Equatable, Sendable {
    case duplicateModuleID(String)
}

public struct ModuleRegistry: Sendable {
    private var modulesByID: [String: any AthleteModule] = [:]

    public init() {}

    public var manifests: [ModuleManifest] {
        modulesByID.values.map(\.manifest).sorted { $0.id < $1.id }
    }

    public mutating func register(_ module: some AthleteModule) throws {
        let id = module.manifest.id
        guard modulesByID[id] == nil else {
            throw ModuleRegistryError.duplicateModuleID(id)
        }
        modulesByID[id] = module
    }
}
