import AthleteCore
import CryptoKit
import Foundation

public enum UserNarrativeClaimKind: String, Codable, Equatable, Sendable {
    case exercise
    case loadKilograms
    case repetitions
    case rpe
}

public struct UserNarrativeClaim: Codable, Equatable, Sendable {
    public let kind: UserNarrativeClaimKind
    public let value: String
}

public struct UserNarrative: Codable, Equatable, Sendable {
    public let text: String
    public let sessionEvidenceID: UUID
    public let claims: [UserNarrativeClaim]
    public let clarificationQuestion: String?
    public let extractionVersion: String

    public func envelope(id: UUID = UUID(), ingestedAt: Date = Date()) throws -> EvidenceEnvelope {
        let payload = try JSONEncoder().encode(self)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return EvidenceEnvelope(
            id: id,
            moduleID: "org.baseline.user-narrative",
            moduleVersion: extractionVersion,
            kind: "user.narrative.v1",
            observedFrom: ingestedAt,
            observedTo: ingestedAt,
            ingestedAt: ingestedAt,
            epistemicRole: .userReported,
            provenance: Provenance(
                sourceID: "chat-input",
                producerID: "user-narrative",
                producerVersion: extractionVersion,
                method: "explicit-value-extraction"
            ),
            privacyClass: .sensitiveLocal,
            payload: PayloadReference(
                mediaType: "application/json",
                schemaID: "user.narrative",
                schemaVersion: "1",
                storageURI: "baseline://evidence/\(id.uuidString)"
            ),
            derivedFrom: [sessionEvidenceID],
            supersedes: nil,
            contentDigest: "sha256:\(digest)"
        )
    }
}

public struct SessionRPEEvidence: Codable, Equatable, Sendable {
    public let sessionEvidenceID: UUID
    public let rpe: Double
    public let note: String?
    public init(sessionEvidenceID: UUID, rpe: Double, note: String?) {
        self.sessionEvidenceID = sessionEvidenceID; self.rpe = min(max(rpe, 1), 10); self.note = note
    }
    public func envelope(id: UUID = UUID(), ingestedAt: Date = Date()) throws -> EvidenceEnvelope {
        let payload = try JSONEncoder().encode(self)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return EvidenceEnvelope(id: id, moduleID: "org.baseline.user-narrative", moduleVersion: "session-rpe-v1", kind: "user.narrative.v1", observedFrom: ingestedAt, observedTo: ingestedAt, ingestedAt: ingestedAt, epistemicRole: .userReported, provenance: Provenance(sourceID: "rpe-feedback", producerID: "session-rpe", producerVersion: "session-rpe-v1", method: "explicit-rpe-input"), privacyClass: .sensitiveLocal, payload: PayloadReference(mediaType: "application/json", schemaID: "session.rpe", schemaVersion: "1", storageURI: "baseline://evidence/\(id.uuidString)"), derivedFrom: [sessionEvidenceID], supersedes: nil, contentDigest: "sha256:\(digest)")
    }
}

public enum UserNarrativeError: Error, Equatable, Sendable {
    case emptyText
}

public struct UserNarrativeBuilder: Sendable {
    public let extractionVersion: String

    public init(extractionVersion: String = "user-narrative-v1") {
        self.extractionVersion = extractionVersion
    }

    public func make(text: String, sessionEvidenceID: UUID) throws -> UserNarrative {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw UserNarrativeError.emptyText }
        let lowered = value.lowercased()
        guard let exercise = exercise(in: lowered), let load = kilograms(in: lowered), let reps = repetitions(in: lowered) else {
            return UserNarrative(
                text: value,
                sessionEvidenceID: sessionEvidenceID,
                claims: [],
                clarificationQuestion: "К какому упражнению и весу относились \(value)?",
                extractionVersion: extractionVersion
            )
        }
        var claims = [
            UserNarrativeClaim(kind: .exercise, value: exercise),
            UserNarrativeClaim(kind: .loadKilograms, value: load),
            UserNarrativeClaim(kind: .repetitions, value: reps),
        ]
        if let rpe = number(after: "rpe", in: lowered) {
            claims.append(UserNarrativeClaim(kind: .rpe, value: rpe))
        }
        return UserNarrative(
            text: value,
            sessionEvidenceID: sessionEvidenceID,
            claims: claims,
            clarificationQuestion: nil,
            extractionVersion: extractionVersion
        )
    }

    private func exercise(in text: String) -> String? {
        ["присед", "жим", "тяга"].first(where: text.contains)
    }

    private func kilograms(in text: String) -> String? {
        number(before: "кг", in: text)
    }

    private func repetitions(in text: String) -> String? {
        number(after: "на", in: text)
    }

    private func number(before marker: String, in text: String) -> String? {
        let parts = text.components(separatedBy: marker)
        guard let value = parts.first?.split(whereSeparator: { !$0.isNumber }).last else { return nil }
        return String(value)
    }

    private func number(after marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        return text[range.upperBound...].split(whereSeparator: { !$0.isNumber }).first.map(String.init)
    }
}
