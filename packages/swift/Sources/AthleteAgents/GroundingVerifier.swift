import AthleteCore
import Foundation

public enum GroundingIssue: Equatable, Sendable {
    case missingEvidence(UUID)
    case missingArtifact(UUID)
    case staleArtifact(UUID)
    case exactNumberWithoutArtifact(line: Int)
}

public struct GroundingReport: Equatable, Sendable {
    public let status: VerificationStatus
    public let issues: [GroundingIssue]

    public init(status: VerificationStatus, issues: [GroundingIssue]) {
        self.status = status
        self.issues = issues
    }
}

public struct GroundingVerifier: Sendable {
    public init() {}

    public func verify(
        document: MemoryDocument,
        evidenceIDs: Set<UUID>,
        artifactIDs: Set<UUID>,
        staleArtifactIDs: Set<UUID>
    ) -> GroundingReport {
        var issues: [GroundingIssue] = []

        for (index, line) in document.markdown.components(separatedBy: .newlines).enumerated() {
            let references = Self.references(in: line)
            for reference in references {
                switch reference.kind {
                case "ev" where !evidenceIDs.contains(reference.id):
                    issues.append(.missingEvidence(reference.id))
                case "calc" where !artifactIDs.contains(reference.id):
                    issues.append(.missingArtifact(reference.id))
                case "calc" where staleArtifactIDs.contains(reference.id):
                    issues.append(.staleArtifact(reference.id))
                default:
                    break
                }
            }

            let textWithoutReferences = references.reduce(line) { text, reference in
                text.replacingOccurrences(of: "[\(reference.kind):\(reference.id.uuidString)]", with: "")
            }
            let containsNumber = textWithoutReferences.contains(where: \.isNumber)
            let containsArtifactReference = references.contains { $0.kind == "calc" }
            if containsNumber && !containsArtifactReference {
                issues.append(.exactNumberWithoutArtifact(line: index + 1))
            }
        }

        let status: VerificationStatus
        if issues.isEmpty {
            status = .verified
        } else if issues.allSatisfy({
            if case .staleArtifact = $0 { return true }
            return false
        }) {
            status = .stale
        } else {
            status = .rejected
        }
        return GroundingReport(status: status, issues: issues)
    }

    private static func references(in text: String) -> [(kind: String, id: UUID)] {
        var references: [(kind: String, id: UUID)] = []
        for kind in ["ev", "calc"] {
            var remainder = text[...]
            let prefix = "[\(kind):"
            while let start = remainder.range(of: prefix) {
                let valueStart = start.upperBound
                guard let end = remainder[valueStart...].firstIndex(of: "]") else { break }
                if let id = UUID(uuidString: String(remainder[valueStart..<end])) {
                    references.append((kind, id))
                }
                remainder = remainder[remainder.index(after: end)...]
            }
        }
        return references
    }
}
