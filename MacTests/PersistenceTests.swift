import Foundation
import Testing
@testable import Cove

@MainActor @Suite struct PersistenceTests {
    @Test func savesAndRestoresOrderedMessages() throws {
        let repository = try ChatRepository(inMemory: true)
        let chat = Conversation(title: "Round trip", messages: [
            .init(sequence: 2, role: .assistant, parts: [.text("second")]),
            .init(sequence: 1, role: .user, parts: [.text("first")])
        ])
        try repository.save(chat)
        #expect(try repository.load(chat.id)?.messages.map(\.sequence) == [1, 2])
    }
    @Test func recoversAnInterruptedGeneration() throws {
        let repository = try ChatRepository(inMemory: true)
        let chat = Conversation(messages: [.init(sequence: 0, role: .assistant, parts: [.text("partial")], status: .streaming)])
        try repository.save(chat)
        try repository.recoverInterrupted()
        let loaded = try repository.load(chat.id)
        #expect(loaded?.messages.first?.status == .interrupted)
        #expect(loaded?.messages.first?.text == "partial")
    }
    @Test func checkpointUpdatesDoNotDuplicateMessages() throws {
        let repository = try ChatRepository(inMemory: true)
        var chat = Conversation(messages: [.init(sequence: 0, role: .assistant)])
        for _ in 0..<10 {
            chat.messages[0].append(text: "a", reasoning: "")
            try repository.save(chat)
        }
        #expect(try repository.load(chat.id)?.messages.count == 1)
        #expect(try repository.load(chat.id)?.messages.first?.text == String(repeating: "a", count: 10))
    }
    @Test func deletingAConnectionDoesNotDeleteHistory() throws {
        let repository = try ChatRepository(inMemory: true)
        let connection = ProviderConnection.localOllama
        let chat = Conversation(selectedConnectionID: connection.id)
        try repository.saveConnection(connection)
        try repository.save(chat)
        try repository.deleteConnection(connection.id)
        #expect(try repository.connections().isEmpty)
        #expect(try repository.load(chat.id) != nil)
    }
    @Test func deletesConversation() throws {
        let repository = try ChatRepository(inMemory: true)
        let chat = Conversation(messages: [.init(sequence: 0, role: .user, parts: [.text("Remove me")])])
        try repository.save(chat)
        try repository.delete(chat.id)
        #expect(try repository.load(chat.id) == nil)
        #expect(try repository.summaries().isEmpty)
    }
}
