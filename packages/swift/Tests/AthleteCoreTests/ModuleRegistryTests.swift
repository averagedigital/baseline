import Foundation
import Testing
@testable import AthleteCore

private struct TestModule: AthleteModule {
    let manifest: ModuleManifest
}

@Test("Registry не принимает два модуля с одним ID")
func duplicateModuleIsRejected() throws {
    let manifest = ModuleManifest(
        id: "org.baseline.test",
        version: "1.0.0",
        displayName: "Тест",
        producedEvidenceKinds: ["test.v1"],
        supportedContextScopes: [.session],
        toolIDs: [],
        privacyClass: .sensitiveLocal,
        requiresUserConsent: false,
        supportsLocalProcessing: true
    )
    var registry = ModuleRegistry()
    try registry.register(TestModule(manifest: manifest))

    #expect(throws: ModuleRegistryError.duplicateModuleID(manifest.id)) {
        try registry.register(TestModule(manifest: manifest))
    }
}

@Test("Registry возвращает manifests в стабильном порядке")
func manifestsAreSorted() throws {
    var registry = ModuleRegistry()
    for id in ["org.baseline.z", "org.baseline.a"] {
        try registry.register(TestModule(manifest: ModuleManifest(
            id: id,
            version: "1.0.0",
            displayName: id,
            producedEvidenceKinds: [],
            supportedContextScopes: [.weekly],
            toolIDs: [],
            privacyClass: .sensitiveLocal,
            requiresUserConsent: false,
            supportsLocalProcessing: true
        )))
    }

    #expect(registry.manifests.map(\.id) == ["org.baseline.a", "org.baseline.z"])
}
