import Foundation
import Testing
@testable import Cove

@MainActor @Suite struct ConnectPersistenceTests {
    @Test func savesProviderPresetAndGatewayWithoutSchemaReset() throws {
        let repository = try ChatRepository(inMemory: true)
        var connection = ProviderCatalog.preset(id: "cloudflare")!.newConnection()
        connection.gatewayID = "my-team"
        connection.defaultModelID = "provider/model"
        try repository.saveConnection(connection)
        #expect(try repository.connections().first == connection)
    }
    @Test func sameProviderCanHaveIndependentConnections() throws {
        let repository = try ChatRepository(inMemory: true)
        let first = ProviderCatalog.preset(id: "lmStudio")!.newConnection()
        var second = ProviderCatalog.preset(id: "lmStudio")!.newConnection()
        second.name = "Office Mac"
        second.endpoint = "http://192.168.1.8:1234/v1"
        try repository.saveConnection(first)
        try repository.saveConnection(second)
        let loaded = try repository.connections()
        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.id)).count == 2)
        #expect(loaded.allSatisfy { $0.provider.id == "lmStudio" })
    }
    @Test func addingConnectionDoesNotSelectItOrChangeStoredHistory() throws {
        let repository = try ChatRepository(inMemory: true)
        var existing = ProviderConnection.localOllama
        existing.id = UUID()
        try repository.saveConnection(existing)
        let suite = "ConnectTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = try ChatStore(repository: repository, preferences: preferences)
        let oldID = store.connection?.id
        #expect(oldID == existing.id)
        var connection = ProviderCatalog.preset(id: "lmStudio")!.newConnection()
        connection.defaultModelID = "another-model"
        try store.saveConnection(connection, newKey: "")
        #expect(store.connection?.id == oldID)
        store.select(connection: connection, modelID: connection.defaultModelID)
        #expect(store.connection?.id == connection.id)
    }
    /// A fresh install ships no connection, so the first one saved has to become
    /// usable; otherwise onboarding would end with nothing selected.
    @Test func freshInstallHasNoConnectionUntilTheFirstIsSaved() throws {
        let repository = try ChatRepository(inMemory: true)
        let suite = "ConnectTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = try ChatStore(repository: repository, preferences: preferences)
        #expect(store.connections.isEmpty)
        #expect(store.connection == nil)
        #expect(!store.canSend)
        var first = ProviderCatalog.preset(id: "lmStudio")!.newConnection()
        first.defaultModelID = "some-model"
        try store.saveConnection(first, newKey: "")
        #expect(store.connection?.id == first.id)
        #expect(store.modelID == "some-model")
    }
}
