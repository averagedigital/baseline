import AthleteCore
import Foundation
import GRDB

public actor AthleteStore {
    private let database: DatabaseQueue

    public init(path: String) throws {
        database = try DatabaseQueue(path: path)
        try Self.migrator.migrate(database)
    }

    private init(database: DatabaseQueue) throws {
        self.database = database
        try Self.migrator.migrate(database)
    }

    public static func inMemory() throws -> AthleteStore {
        try AthleteStore(database: DatabaseQueue())
    }

    public func appendEvidence(_ envelope: EvidenceEnvelope) throws {
        let payload = try JSONEncoder().encode(envelope)
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO evidence_events
                        (id, module_id, kind, observed_from, observed_to, ingested_at, supersedes, content_digest, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    envelope.id.uuidString,
                    envelope.moduleID,
                    envelope.kind,
                    envelope.observedFrom,
                    envelope.observedTo,
                    envelope.ingestedAt,
                    envelope.supersedes?.uuidString,
                    envelope.contentDigest,
                    payload,
                ]
            )
            for sourceID in envelope.derivedFrom {
                try db.execute(
                    sql: "INSERT INTO evidence_derivations (evidence_id, source_evidence_id) VALUES (?, ?)",
                    arguments: [envelope.id.uuidString, sourceID.uuidString]
                )
            }
        }
    }

    public func evidence(id: UUID) throws -> EvidenceEnvelope? {
        try database.read { db in
            guard let data = try Data.fetchOne(
                db,
                sql: "SELECT payload FROM evidence_events WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try JSONDecoder().decode(EvidenceEnvelope.self, from: data)
        }
    }

    public func saveMemory(_ document: MemoryDocument) throws {
        let payload = try JSONEncoder().encode(document)
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO memory_documents
                        (id, kind, revision, verification_status, input_digest, markdown, payload)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    document.id.uuidString,
                    document.kind.rawValue,
                    document.revision,
                    document.verificationStatus.rawValue,
                    document.inputDigest,
                    document.markdown,
                    payload,
                ]
            )
            for dependency in document.basedOn {
                let values: (String?, String?) = switch dependency {
                case let .evidence(id): (id.uuidString, nil)
                case let .artifact(id): (nil, id.uuidString)
                }
                try db.execute(
                    sql: """
                        INSERT INTO memory_dependencies (document_id, evidence_id, artifact_id)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [document.id.uuidString, values.0, values.1]
                )
            }
            try db.execute(
                sql: "INSERT INTO memory_search (document_id, body) VALUES (?, ?)",
                arguments: [document.id.uuidString, document.markdown]
            )
        }
    }

    public func memory(id: UUID) throws -> MemoryDocument? {
        try database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT payload, verification_status FROM memory_documents WHERE id = ?",
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            let data: Data = row["payload"]
            let statusValue: String = row["verification_status"]
            let document = try JSONDecoder().decode(MemoryDocument.self, from: data)
            guard let status = VerificationStatus(rawValue: statusValue) else {
                throw AthleteStoreError.invalidVerificationStatus(statusValue)
            }
            return document.withVerificationStatus(status)
        }
    }

    public func markMemoryStale(dependingOn evidenceID: UUID) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE memory_documents
                    SET verification_status = ?
                    WHERE id IN (
                        SELECT document_id FROM memory_dependencies WHERE evidence_id = ?
                    )
                    """,
                arguments: [VerificationStatus.stale.rawValue, evidenceID.uuidString]
            )
        }
    }

    public func schemaObjects() throws -> Set<String> {
        try database.read { db in
            Set(try String.fetchAll(
                db,
                sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%'"
            ))
        }
    }
}

public enum AthleteStoreError: Error, Equatable, Sendable {
    case invalidVerificationStatus(String)
}

private extension MemoryDocument {
    func withVerificationStatus(_ status: VerificationStatus) -> MemoryDocument {
        MemoryDocument(
            id: id,
            kind: kind,
            scope: scope,
            revision: revision,
            createdAt: createdAt,
            supersedes: supersedes,
            basedOn: basedOn,
            modelID: modelID,
            providerID: providerID,
            promptVersion: promptVersion,
            inputDigest: inputDigest,
            verificationStatus: status,
            markdown: markdown
        )
    }
}
