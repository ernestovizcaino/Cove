import Foundation
import Testing
@testable import Cove

private struct FixtureGenerator: GenerationClient {
    var fail = false
    var slow = false
    func stream(_ request: GenerationRequest, apiKey: String?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.text("Hello"))
                    try await Task.sleep(for: .milliseconds(slow ? 5000 : 35))
                    if fail { throw ChatError.incompleteStream }
                    continuation.yield(.text(" world"))
                    continuation.yield(.finished(reason: "stop", usage: .init(input: 2, output: 2)))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
@MainActor @Suite struct ChatStoreTests {
    private func makeStore(_ generator: FixtureGenerator = .init()) throws -> ChatStore {
        let repository = try ChatRepository(inMemory: true)
        var connection = ProviderConnection.localOllama
        connection.id = UUID()
        try repository.saveConnection(connection)
        let preferences = UserDefaults(suiteName: "CoveTests.\(UUID().uuidString)")!
        return try ChatStore(repository: repository, generator: generator, preferences: preferences)
    }
    private func waitForIdle(_ store: ChatStore) async throws {
        for _ in 0..<300 {
            if !store.isGenerating { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Generation did not finish within 3 seconds")
        store.stop()
    }
    @Test func sendsAndPersistsResponse() async throws {
        let store = try makeStore()
        store.draft = "Hello there"
        store.requestSend()
        try await waitForIdle(store)
        #expect(store.messages.count == 2)
        #expect(store.messages.last?.text == "Hello world")
        #expect(store.messages.last?.status == .completed)
        #expect(store.draft.isEmpty)
    }
    @Test func preservesPartialResponseOnFailure() async throws {
        let store = try makeStore(.init(fail: true))
        store.draft = "Hello"
        store.requestSend()
        try await waitForIdle(store)
        #expect(store.messages.last?.text == "Hello")
        #expect(store.messages.last?.status == .failed)
    }
    @Test func cancellationDoesNotLeaveBusyState() async throws {
        let store = try makeStore(.init(slow: true))
        store.draft = "Hello"
        store.requestSend()
        try await Task.sleep(for: .milliseconds(60))
        store.stop()
        try await waitForIdle(store)
        #expect(store.messages.last?.status == .cancelled)
        #expect(!store.isGenerating)
    }
    @Test func changingChatsDoesNotMisrouteResponse() async throws {
        let store = try makeStore()
        store.draft = "Hello"
        store.requestSend()
        let original = try #require(store.selectedID)
        store.newChat()
        try await waitForIdle(store)
        #expect(store.selectedID == nil)
        store.open(original)
        #expect(store.messages.last?.text == "Hello world")
    }
    @Test func togglesAndPersistsFavoriteModels() async throws {
        let store = try makeStore()
        let connID = UUID()
        let modelID = "llama3.2"
        #expect(!store.isFavorite(connectionID: connID, modelID: modelID))
        store.toggleFavorite(connectionID: connID, modelID: modelID)
        #expect(store.isFavorite(connectionID: connID, modelID: modelID))
        store.toggleFavorite(connectionID: connID, modelID: modelID)
        #expect(!store.isFavorite(connectionID: connID, modelID: modelID))
    }
}

