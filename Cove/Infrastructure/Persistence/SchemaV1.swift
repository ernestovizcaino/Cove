import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [ConversationRecord.self, MessageRecord.self, ConnectionRecord.self] }

    @Model final class ConversationRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var selectedConnectionID: UUID?
        var selectedModelID: String
        var systemPrompt: String
        var draft: String
        @Relationship(deleteRule: .cascade, inverse: \MessageRecord.conversation)
        var messages: [MessageRecord] = []
        init(_ value: Conversation) {
            id = value.id; title = value.title; createdAt = value.createdAt; updatedAt = value.updatedAt
            selectedConnectionID = value.selectedConnectionID; selectedModelID = value.selectedModelID
            systemPrompt = value.systemPrompt; draft = value.draft
        }
    }
    @Model final class MessageRecord {
        @Attribute(.unique) var id: UUID
        var sequence: Int
        var payload: Data
        var conversation: ConversationRecord?
        init(id: UUID, sequence: Int, payload: Data) {
            self.id = id; self.sequence = sequence; self.payload = payload
        }
    }
    @Model final class ConnectionRecord {
        @Attribute(.unique) var id: UUID
        var payload: Data
        init(id: UUID, payload: Data) { self.id = id; self.payload = payload }
    }
}
enum StoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
