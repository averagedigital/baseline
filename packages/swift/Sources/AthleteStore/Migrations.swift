import GRDB
import Foundation

extension AthleteStore {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "module_manifests") { table in
                table.column("id", .text).primaryKey()
                table.column("version", .text).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "evidence_events") { table in
                table.column("id", .text).primaryKey()
                table.column("module_id", .text).notNull().indexed()
                table.column("kind", .text).notNull().indexed()
                table.column("observed_from", .datetime).notNull().indexed()
                table.column("observed_to", .datetime).notNull()
                table.column("ingested_at", .datetime).notNull()
                table.column("supersedes", .text).references("evidence_events", onDelete: .restrict)
                table.column("content_digest", .text).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "evidence_derivations") { table in
                table.column("evidence_id", .text).notNull()
                    .references("evidence_events", onDelete: .cascade)
                table.column("source_evidence_id", .text).notNull()
                    .references("evidence_events", onDelete: .restrict)
                table.primaryKey(["evidence_id", "source_evidence_id"])
            }
            try db.create(table: "analysis_artifacts") { table in
                table.column("id", .text).primaryKey()
                table.column("created_at", .datetime).notNull().indexed()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "memory_documents") { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull().indexed()
                table.column("revision", .integer).notNull()
                table.column("verification_status", .text).notNull().indexed()
                table.column("input_digest", .text).notNull()
                table.column("markdown", .text).notNull()
                table.column("payload", .blob).notNull()
            }
            try db.create(table: "memory_claim_index") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("document_id", .text).notNull()
                    .references("memory_documents", onDelete: .cascade)
                table.column("claim_text", .text).notNull()
                table.column("claim_type", .text).notNull()
                table.column("status", .text).notNull()
            }
            try db.create(table: "memory_dependencies") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("document_id", .text).notNull().indexed()
                    .references("memory_documents", onDelete: .cascade)
                table.column("evidence_id", .text).indexed()
                    .references("evidence_events", onDelete: .restrict)
                table.column("artifact_id", .text).indexed()
                    .references("analysis_artifacts", onDelete: .restrict)
            }
            try db.execute(sql: "CREATE VIRTUAL TABLE memory_search USING fts5(document_id UNINDEXED, body)")
            try Self.createPayloadTable("analysis_jobs", in: db)
            try Self.createPayloadTable("agent_runs", in: db)
            try Self.createPayloadTable("user_corrections", in: db)
            try Self.createPayloadTable("goals", in: db)
            try Self.createPayloadTable("plan_events", in: db)
            try Self.createPayloadTable("experiment_events", in: db)
            try Self.createPayloadTable("consent_grants", in: db)
            try Self.createPayloadTable("provider_configurations", in: db)
        }
        migrator.registerMigration("v2_chat_history") { db in
            try db.create(table: "chat_threads") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull().indexed()
            }
            try db.create(table: "chat_messages") { table in
                table.column("id", .text).primaryKey()
                table.column("thread_id", .text).notNull().indexed()
                    .references("chat_threads", onDelete: .cascade)
                table.column("role", .text).notNull()
                table.column("text", .text).notNull()
                table.column("created_at", .datetime).notNull().indexed()
            }
        }
        migrator.registerMigration("v3_evidence_payloads") { db in
            try db.create(table: "evidence_payloads") { table in
                table.column("evidence_id", .text).primaryKey()
                    .references("evidence_events", onDelete: .cascade)
                table.column("payload", .blob).notNull()
            }
        }
        migrator.registerMigration("v4_on_device_models") { db in
            try db.create(table: "personalization_state", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .blob).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "recommendation_exposures", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .blob).notNull()
                table.column("rewarded", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "feedback_events", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull()
                table.column("payload", .blob).notNull()
                table.column("created_at", .datetime).notNull()
            }
            try db.create(table: "food_observations", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .blob).notNull()
                table.column("captured_at", .datetime).notNull()
            }
            try db.create(table: "coach_threads", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("payload", .blob).notNull()
                table.column("updated_at", .datetime).notNull()
            }
            try db.create(table: "coach_messages", ifNotExists: true) { table in
                table.column("id", .text).primaryKey()
                table.column("thread_id", .text).notNull().indexed()
                table.column("payload", .blob).notNull()
                table.column("created_at", .datetime).notNull()
            }
        }
        migrator.registerMigration("v5_persist_local_model_metadata") { db in
            try db.alter(table: "recommendation_exposures") { table in
                table.add(column: "created_at", .datetime).notNull().defaults(to: Date())
                table.add(column: "rewarded_at", .datetime)
                table.add(column: "reward", .double)
            }
            try db.alter(table: "food_observations") { table in
                table.add(column: "dismissed", .boolean).notNull().defaults(to: false)
            }
        }
        return migrator
    }

    private static func createPayloadTable(_ name: String, in db: Database) throws {
        try db.create(table: name) { table in
            table.column("id", .text).primaryKey()
            table.column("payload", .blob).notNull()
        }
    }
}
