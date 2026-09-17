import Foundation
import SwiftData

@MainActor final class ChatRepository {
    let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, migrationPlan: StoreMigrationPlan.self, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func summaries() throws -> [ConversationSummary] {
        let descriptor = FetchDescriptor<SchemaV1.ConversationRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try context.fetch(descriptor).map {
            ConversationSummary(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
        }
    }
    private func record(_ id: UUID) throws -> SchemaV1.ConversationRecord? {
        var descriptor = FetchDescriptor<SchemaV1.ConversationRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
    func load(_ id: UUID) throws -> Conversation? {
        guard let record = try record(id) else { return nil }
        return Conversation(id: record.id, title: record.title, createdAt: record.createdAt,
            updatedAt: record.updatedAt, selectedConnectionID: record.selectedConnectionID,
            selectedModelID: record.selectedModelID, systemPrompt: record.systemPrompt,
            draft: record.draft,
            messages: try record.messages.sorted { $0.sequence < $1.sequence }.map {
                try decoder.decode(ChatMessage.self, from: $0.payload)
            })
    }
    func save(_ value: Conversation) throws {
        do {
            let record: SchemaV1.ConversationRecord
            if let existing = try self.record(value.id) { record = existing }
            else { record = SchemaV1.ConversationRecord(value); context.insert(record) }
            record.title = value.title; record.updatedAt = value.updatedAt
            record.selectedConnectionID = value.selectedConnectionID; record.selectedModelID = value.selectedModelID
            record.systemPrompt = value.systemPrompt; record.draft = value.draft
            let existing = Dictionary(uniqueKeysWithValues: record.messages.map { ($0.id, $0) })
            var updated: [SchemaV1.MessageRecord] = []
            for message in value.messages {
                let payload = try encoder.encode(message)
                if let stored = existing[message.id] {
                    if stored.payload != payload { stored.payload = payload }
                    updated.append(stored)
                } else {
                    let stored = SchemaV1.MessageRecord(id: message.id, sequence: message.sequence, payload: payload)
                    context.insert(stored)
                    stored.conversation = record
                    updated.append(stored)
                }
            }
            let ids = Set(value.messages.map(\.id))
            for old in existing.values where !ids.contains(old.id) { context.delete(old) }
            record.messages = updated
            try context.save()
        } catch { context.rollback(); throw error }
    }
    func delete(_ id: UUID) throws {
        guard let record = try record(id) else { return }
        context.delete(record)
        do { try context.save() } catch { context.rollback(); throw error }
    }
    func recoverInterrupted() throws {
        for summary in try summaries() {
            guard var conversation = try load(summary.id) else { continue }
            var changed = false
            for index in conversation.messages.indices where conversation.messages[index].status == .streaming {
                conversation.messages[index].status = .interrupted
                changed = true
            }
            if changed { try save(conversation) }
        }
    }
    func connections() throws -> [ProviderConnection] {
        try context.fetch(FetchDescriptor<SchemaV1.ConnectionRecord>())
            .map { try decoder.decode(ProviderConnection.self, from: $0.payload) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func saveConnection(_ value: ProviderConnection) throws {
        let id = value.id
        let descriptor = FetchDescriptor<SchemaV1.ConnectionRecord>(predicate: #Predicate { $0.id == id })
        do {
            let payload = try encoder.encode(value)
            if let record = try context.fetch(descriptor).first { record.payload = payload }
            else { context.insert(SchemaV1.ConnectionRecord(id: id, payload: payload)) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
    func deleteConnection(_ id: UUID) throws {
        let descriptor = FetchDescriptor<SchemaV1.ConnectionRecord>(predicate: #Predicate { $0.id == id })
        do {
            for record in try context.fetch(descriptor) { context.delete(record) }
            try context.save()
        } catch { context.rollback(); throw error }
    }
}
