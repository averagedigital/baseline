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
    public let attachments: [ChatAttachment]
    public let citations: [ChatCitation]

    public init(
        id: UUID = UUID(),
        threadID: UUID,
        role: Role,
        text: String,
        createdAt: Date = Date(),
        attachments: [ChatAttachment] = [],
        citations: [ChatCitation] = []
    ) {
        self.id = id
        self.threadID = threadID
        self.role = role
        self.text = text
        self.createdAt = createdAt
        self.attachments = attachments
        self.citations = citations
    }
}

public struct ChatCitation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let messageID: UUID
    public let title: String?
    public let url: URL
    public let createdAt: Date

    public init(id: UUID = UUID(), messageID: UUID, title: String?, url: URL, createdAt: Date = Date()) {
        self.id = id; self.messageID = messageID; self.title = title; self.url = url; self.createdAt = createdAt
    }
}

public struct ChatAttachment: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case image }
    public let id: UUID
    public let messageID: UUID
    public let kind: Kind
    public let localPath: String
    public let transportPath: String?
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let byteSize: Int
    public let createdAt: Date

    public init(id: UUID = UUID(), messageID: UUID, kind: Kind = .image, localPath: String, transportPath: String? = nil, mimeType: String, width: Int, height: Int, byteSize: Int, createdAt: Date = Date()) {
        self.id = id; self.messageID = messageID; self.kind = kind; self.localPath = localPath
        self.transportPath = transportPath; self.mimeType = mimeType; self.width = width
        self.height = height; self.byteSize = byteSize; self.createdAt = createdAt
    }
}

public struct ProviderCapabilities: Codable, Equatable, Sendable {
    public var supportsVision: Bool
    public var supportsFunctionCalling: Bool
    public var supportsWebSearch: Bool
    public var supportsReasoning: Bool
    public var supportsReasoningSummary: Bool
    public static let textOnly = Self(supportsVision: false, supportsFunctionCalling: false, supportsWebSearch: false, supportsReasoning: false, supportsReasoningSummary: false)
    public static let openAI = Self(supportsVision: true, supportsFunctionCalling: true, supportsWebSearch: true, supportsReasoning: true, supportsReasoningSummary: true)
    public init(supportsVision: Bool, supportsFunctionCalling: Bool, supportsWebSearch: Bool, supportsReasoning: Bool, supportsReasoningSummary: Bool) {
        self.supportsVision = supportsVision; self.supportsFunctionCalling = supportsFunctionCalling
        self.supportsWebSearch = supportsWebSearch; self.supportsReasoning = supportsReasoning
        self.supportsReasoningSummary = supportsReasoningSummary
    }
}

public enum ProviderReasoningEffort: String, Codable, Equatable, Sendable, CaseIterable { case off, low, medium, high, xhigh, max }

public struct ProviderConfiguration: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: String
    public var model: String
    public var isSelected: Bool
    public var capabilities: ProviderCapabilities
    public var webSearchEnabled: Bool
    public var reasoningEffort: ProviderReasoningEffort

    public init(id: UUID = UUID(), name: String, baseURL: String, model: String, isSelected: Bool = false, capabilities: ProviderCapabilities = .textOnly, webSearchEnabled: Bool = false, reasoningEffort: ProviderReasoningEffort = .off) {
        self.id = id; self.name = name; self.baseURL = baseURL; self.model = model; self.isSelected = isSelected
        self.capabilities = capabilities
        self.webSearchEnabled = capabilities.supportsWebSearch && webSearchEnabled
        self.reasoningEffort = capabilities.supportsReasoning ? reasoningEffort : .off
    }

    private enum CodingKeys: String, CodingKey { case id, name, baseURL, model, isSelected, capabilities, webSearchEnabled, reasoningEffort }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id); name = try values.decode(String.self, forKey: .name)
        baseURL = try values.decode(String.self, forKey: .baseURL); model = try values.decode(String.self, forKey: .model)
        isSelected = try values.decodeIfPresent(Bool.self, forKey: .isSelected) ?? false
        capabilities = try values.decodeIfPresent(ProviderCapabilities.self, forKey: .capabilities) ?? .textOnly
        let decodedWebSearch = try values.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false
        let decodedReasoning = try values.decodeIfPresent(ProviderReasoningEffort.self, forKey: .reasoningEffort) ?? .off
        webSearchEnabled = capabilities.supportsWebSearch && decodedWebSearch
        reasoningEffort = capabilities.supportsReasoning ? decodedReasoning : .off
    }
}

extension AthleteStore {
    public func saveProviderConfiguration(_ configuration: ProviderConfiguration) throws {
        try database.write { db in
            if configuration.isSelected { try Self.clearSelectedProvider(in: db) }
            try Self.writeProvider(configuration, in: db)
        }
    }

    public func providerConfigurations() throws -> [ProviderConfiguration] {
        try database.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM provider_configurations ORDER BY id")
                .map { try JSONDecoder().decode(ProviderConfiguration.self, from: $0) }
        }
    }

    public func selectProvider(id: UUID) throws {
        try database.write { db in
            let configurations = try Self.readProviders(in: db)
            guard configurations.contains(where: { $0.id == id }) else { throw AthleteStoreError.invalidIdentifier(id.uuidString) }
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
            ).map { row in
                let messageID: String = row["id"]
                return try Self.decodeMessage(row, attachments: Self.attachments(for: messageID, in: db), citations: Self.citations(for: messageID, in: db))
            }
        }
    }

    public func chatThread(containingMessageID messageID: UUID) throws -> ChatThread? {
        try database.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT chat_threads.*,
                       (SELECT text FROM chat_messages WHERE thread_id = chat_threads.id ORDER BY created_at DESC, rowid DESC LIMIT 1) AS last_message,
                       (SELECT COUNT(*) FROM chat_messages WHERE thread_id = chat_threads.id) AS message_count
                FROM chat_threads
                JOIN chat_messages ON chat_messages.thread_id = chat_threads.id
                WHERE chat_messages.id = ?
                LIMIT 1
                """, arguments: [messageID.uuidString]) else { return nil }
            return try Self.decodeThread(row)
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
            for attachment in message.attachments {
                guard attachment.messageID == message.id, attachment.width > 0, attachment.height > 0, attachment.byteSize >= 0 else {
                    throw AthleteStoreError.invalidAttachment
                }
                try db.execute(sql: """
                    INSERT INTO chat_attachments
                        (id, message_id, kind, local_path, transport_path, mime_type, width, height, byte_size, created_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [attachment.id.uuidString, message.id.uuidString, attachment.kind.rawValue, attachment.localPath, attachment.transportPath, attachment.mimeType, attachment.width, attachment.height, attachment.byteSize, attachment.createdAt])
            }
            for citation in message.citations {
                guard citation.messageID == message.id else { throw AthleteStoreError.invalidAttachment }
                try db.execute(sql: "INSERT INTO chat_citations (id, message_id, title, url, created_at) VALUES (?, ?, ?, ?, ?)", arguments: [citation.id.uuidString, message.id.uuidString, citation.title, citation.url.absoluteString, citation.createdAt])
            }
            try db.execute(
                sql: "UPDATE chat_threads SET updated_at = ? WHERE id = ?",
                arguments: [message.createdAt, message.threadID.uuidString]
            )
        }
    }

    public func deleteChat(id: UUID) throws {
        let paths = try database.write { db -> [String] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT local_path, transport_path FROM chat_attachments
                JOIN chat_messages ON chat_messages.id = chat_attachments.message_id
                WHERE chat_messages.thread_id = ?
                """, arguments: [id.uuidString])
            try db.execute(sql: "DELETE FROM chat_threads WHERE id = ?", arguments: [id.uuidString])
            return rows.flatMap { row -> [String] in
                let local: String = row["local_path"]
                let transport: String? = row["transport_path"]
                return [local] + (transport.map { [$0] } ?? [])
            }
        }
        for path in Set(paths) where FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
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

    private static func decodeMessage(_ row: Row, attachments: [ChatAttachment], citations: [ChatCitation]) throws -> ChatHistoryMessage {
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
            createdAt: row["created_at"],
            attachments: attachments,
            citations: citations
        )
    }

    private static func citations(for messageID: String, in db: Database) throws -> [ChatCitation] {
        try Row.fetchAll(db, sql: "SELECT * FROM chat_citations WHERE message_id = ? ORDER BY created_at, rowid", arguments: [messageID]).map { row in
            let idValue: String = row["id"]
            let urlValue: String = row["url"]
            guard let id = UUID(uuidString: idValue), let ownerID = UUID(uuidString: messageID), let url = URL(string: urlValue) else {
                throw AthleteStoreError.invalidIdentifier(idValue)
            }
            return ChatCitation(id: id, messageID: ownerID, title: row["title"], url: url, createdAt: row["created_at"])
        }
    }

    private static func attachments(for messageID: String, in db: Database) throws -> [ChatAttachment] {
        try Row.fetchAll(db, sql: "SELECT * FROM chat_attachments WHERE message_id = ? ORDER BY created_at, rowid", arguments: [messageID]).map { row in
            let idValue: String = row["id"]
            guard let id = UUID(uuidString: idValue), let messageID = UUID(uuidString: messageID),
                  let kind = ChatAttachment.Kind(rawValue: row["kind"]) else { throw AthleteStoreError.invalidIdentifier(idValue) }
            return ChatAttachment(id: id, messageID: messageID, kind: kind, localPath: row["local_path"], transportPath: row["transport_path"], mimeType: row["mime_type"], width: row["width"], height: row["height"], byteSize: row["byte_size"], createdAt: row["created_at"])
        }
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
            sql: "INSERT INTO provider_configurations (id, payload) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET payload = excluded.payload",
            arguments: [configuration.id.uuidString, try JSONEncoder().encode(configuration)]
        )
    }

}
