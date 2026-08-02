import Foundation
import GRDB

public struct ChatThread: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var updatedAt: Date
    public var lastMessage: String?
    public var messageCount: Int

    public init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date,
        updatedAt: Date,
        lastMessage: String? = nil,
        messageCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastMessage = lastMessage
        self.messageCount = messageCount
    }
}

public struct ChatHistoryMessage: Codable, Equatable, Identifiable, Sendable {
    public enum Role: String, Codable, Equatable, Sendable {
        case user
        case assistant
    }

    public let id: UUID
    public let threadID: UUID
    public let role: Role
    public let text: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        role: Role,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public struct ProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var model: String
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        model: String,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.isSelected = isSelected
    }
}

extension AthleteStore {
    public func createChat(title: String, at date: Date = Date()) throws -> ChatThread {
        let thread = ChatThread(title: title, createdAt: date, updatedAt: date)
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO chat_threads (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)",
                arguments: [thread.id.uuidString, thread.title, thread.createdAt, thread.updatedAt]
            )
        }
        return thread
    }

    public func chatThreads() throws -> [ChatThread] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT chat_threads.*,
                           (
                               SELECT text
                               FROM chat_messages
                               WHERE thread_id = chat_threads.id
                               ORDER BY created_at DESC, rowid DESC
                               LIMIT 1
                           ) AS last_message,
                           (
                               SELECT COUNT(*)
                               FROM chat_messages
                               WHERE thread_id = chat_threads.id
                           ) AS message_count
                    FROM chat_threads
                    ORDER BY updated_at DESC
                    """
            ).map(Self.decodeThread)
        }
    }

    public func chatMessages(threadID: UUID) throws -> [ChatHistoryMessage] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM chat_messages WHERE thread_id = ? ORDER BY created_at ASC, rowid ASC",
                arguments: [threadID.uuidString]
            ).map(Self.decodeMessage)
        }
    }

    public func appendChatMessage(_ message: ChatHistoryMessage) throws {
        try database.write { db in
            try db.execute(
                sql: """
                    INSERT INTO chat_messages (id, thread_id, role, text, created_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    message.id.uuidString,
                    message.threadID.uuidString,
                    message.role.rawValue,
                    message.text,
                    message.createdAt,
                ]
            )
            try db.execute(
                sql: "UPDATE chat_threads SET updated_at = ? WHERE id = ?",
                arguments: [message.createdAt, message.threadID.uuidString]
            )
        }
    }

    public func deleteChat(id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM chat_threads WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func saveProviderConfiguration(_ configuration: ProviderConfiguration) throws {
        try database.write { db in
            if configuration.isSelected {
                try Self.clearSelectedProvider(in: db)
            }
            try Self.writeProvider(configuration, in: db)
        }
    }

    public func providerConfigurations() throws -> [ProviderConfiguration] {
        try database.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM provider_configurations ORDER BY id")
                .map { try JSONDecoder().decode(ProviderConfiguration.self, from: $0) }
        }
    }

    public func selectedProviderConfiguration() throws -> ProviderConfiguration? {
        try providerConfigurations().first(where: \.isSelected)
    }

    public func selectProvider(id: UUID) throws {
        try database.write { db in
            let configurations = try Self.readProviders(in: db)
            guard configurations.contains(where: { $0.id == id }) else {
                throw AthleteStoreError.providerNotFound(id)
            }
            for var configuration in configurations {
                configuration.isSelected = configuration.id == id
                try Self.writeProvider(configuration, in: db)
            }
        }
    }

    public func deleteProviderConfiguration(id: UUID) throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM provider_configurations WHERE id = ?", arguments: [id.uuidString])
        }
    }

    private static func decodeThread(_ row: Row) throws -> ChatThread {
        guard let id = UUID(uuidString: row["id"]) else {
            throw AthleteStoreError.invalidIdentifier(row["id"])
        }
        return ChatThread(
            id: id,
            title: row["title"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            lastMessage: row["last_message"],
            messageCount: row["message_count"]
        )
    }

    private static func decodeMessage(_ row: Row) throws -> ChatHistoryMessage {
        let idValue: String = row["id"]
        let threadIDValue: String = row["thread_id"]
        let roleValue: String = row["role"]
        guard let id = UUID(uuidString: idValue), let threadID = UUID(uuidString: threadIDValue) else {
            throw AthleteStoreError.invalidIdentifier(idValue)
        }
        guard let role = ChatHistoryMessage.Role(rawValue: roleValue) else {
            throw AthleteStoreError.invalidChatRole(roleValue)
        }
        return ChatHistoryMessage(
            id: id,
            threadID: threadID,
            role: role,
            text: row["text"],
            createdAt: row["created_at"]
        )
    }

    private static func readProviders(in db: Database) throws -> [ProviderConfiguration] {
        try Data.fetchAll(db, sql: "SELECT payload FROM provider_configurations")
            .map { try JSONDecoder().decode(ProviderConfiguration.self, from: $0) }
    }

    private static func clearSelectedProvider(in db: Database) throws {
        for var configuration in try readProviders(in: db) where configuration.isSelected {
            configuration.isSelected = false
            try writeProvider(configuration, in: db)
        }
    }

    private static func writeProvider(_ configuration: ProviderConfiguration, in db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO provider_configurations (id, payload) VALUES (?, ?)
                ON CONFLICT(id) DO UPDATE SET payload = excluded.payload
                """,
            arguments: [configuration.id.uuidString, try JSONEncoder().encode(configuration)]
        )
    }
}
