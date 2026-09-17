import Foundation
import Testing
@testable import CoveCore

private struct ImmediateCatalog: ModelCatalogLoading {
    let result: ModelCatalogResult
    func discover(connection: ProviderConnection, apiKey: String?) async throws -> ModelCatalogResult { result }
}
private actor DeferredCatalog: ModelCatalogLoading {
    var count = 0
    private var waiters: [Int: CheckedContinuation<ModelCatalogResult, Error>] = [:]
    func discover(connection: ProviderConnection, apiKey: String?) async throws -> ModelCatalogResult {
        count += 1
        let index = count
        return try await withCheckedThrowingContinuation { continuation in waiters[index] = continuation }
    }
    // Intentionally ignore task cancellation to verify the controller rejects stale completions.
    func resolve(_ index: Int, models: [String]) {
        waiters.removeValue(forKey: index)?.resume(returning: .init(modelIDs: models, isComplete: true, pages: 1))
    }
}

@MainActor private func settle(_ condition: @MainActor () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("Timed out waiting for connection state")
}
private func waitForRequests(_ loader: DeferredCatalog, _ count: Int) async throws {
    for _ in 0..<200 {
        if await loader.count >= count { return }
        try await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("Timed out waiting for fake catalog request")
}

@MainActor @Suite struct ConnectionEditorTests {
    @Test func discoveredModelsPopulateOnlyTheDraft() async throws {
        let original = ProviderCatalog.preset(id: "ollama")!.newConnection()
        let editor = ConnectionEditorStore(connection: original, isNew: true,
            catalog: ImmediateCatalog(result: .init(modelIDs: ["qwen", "other"], isComplete: true, pages: 1)), readKey: { _ in nil })
        editor.discoverModels()
        try await settle { !editor.isDiscovering }
        #expect(editor.connection.modelIDs == ["qwen", "other"])
        #expect(editor.connection.defaultModelID == "qwen")
        #expect(original.modelIDs.isEmpty)
        #expect(editor.isDirty)
        #expect(editor.status?.contains("does not verify") == true)
    }
    @Test func discoveryKeepsAnExplicitModelSelection() async throws {
        var connection = ProviderCatalog.preset(id: "ollama")!.newConnection()
        connection.defaultModelID = "manual-model"
        let editor = ConnectionEditorStore(connection: connection, isNew: true,
            catalog: ImmediateCatalog(result: .init(modelIDs: ["other"], isComplete: true, pages: 1)), readKey: { _ in nil })
        editor.discoverModels()
        try await settle { !editor.isDiscovering }
        #expect(editor.connection.defaultModelID == "manual-model")
    }
    @Test func changingEndpointClearsPastedKeyAndModelsImmediately() {
        let editor = ConnectionEditorStore(connection: .localOllama, isNew: false, readKey: { _ in nil })
        editor.setAPIKey("typed-secret")
        editor.setEndpoint("http://192.168.101.99:11434")
        #expect(editor.apiKey.isEmpty)
        #expect(editor.connection.modelIDs.isEmpty)
        #expect(editor.connection.defaultModelID.isEmpty)
        #expect(!editor.canSave)
    }
    @Test func incompleteCatalogIsNotLabeledComplete() async throws {
        let editor = ConnectionEditorStore(connection: .localOllama, isNew: false,
            catalog: ImmediateCatalog(result: .init(modelIDs: ["example"], isComplete: false, pages: 10)), readKey: { _ in nil })
        editor.discoverModels()
        try await settle { !editor.isDiscovering }
        #expect(editor.status?.contains("partial catalog") == true)
    }
    @Test func missingKeyFailsBeforeMakingACatalogRequest() async {
        let loader = DeferredCatalog()
        let editor = ConnectionEditorStore(connection: .blank(.anthropic), isNew: true, catalog: loader, readKey: { _ in nil })
        editor.discoverModels()
        #expect(!editor.isDiscovering)
        #expect(editor.statusIsError)
        #expect(await loader.count == 0)
    }
    @Test func endpointChangeDiscardsAnOldResultEvenIfLoaderIgnoresCancel() async throws {
        let loader = DeferredCatalog()
        let editor = ConnectionEditorStore(connection: .localOllama, isNew: false, catalog: loader, readKey: { _ in nil })
        editor.discoverModels()
        try await waitForRequests(loader, 1)
        editor.setEndpoint("http://192.168.101.55:11434")
        await loader.resolve(1, models: ["wrong-server-model"])
        try await Task.sleep(for: .milliseconds(10))
        #expect(editor.connection.modelIDs.isEmpty)
        #expect(!editor.isDiscovering)
    }
    @Test func oldRequestCannotOverwriteNewDiscovery() async throws {
        let loader = DeferredCatalog()
        let editor = ConnectionEditorStore(connection: .localOllama, isNew: false, catalog: loader, readKey: { _ in nil })
        editor.discoverModels()
        try await waitForRequests(loader, 1)
        editor.discoverModels()
        try await waitForRequests(loader, 2)
        await loader.resolve(2, models: ["latest"])
        try await settle { !editor.isDiscovering }
        await loader.resolve(1, models: ["stale"])
        try await Task.sleep(for: .milliseconds(10))
        #expect(editor.connection.modelIDs == ["latest"])
    }
    @Test func closingEditorCancelsAndDiscardsPastedKey() async throws {
        let loader = DeferredCatalog()
        let editor = ConnectionEditorStore(connection: .localOllama, isNew: false, catalog: loader, readKey: { _ in nil })
        editor.setAPIKey("secret-not-persisted")
        editor.discoverModels()
        try await waitForRequests(loader, 1)
        editor.tearDown()
        await loader.resolve(1, models: ["ignored"])
        try await Task.sleep(for: .milliseconds(10))
        #expect(editor.apiKey.isEmpty)
        #expect(editor.connection.modelIDs == editor.original.modelIDs)
        #expect(!editor.isDiscovering)
    }
    @Test func credentialEditInvalidatesInFlightCatalog() async throws {
        let loader = DeferredCatalog()
        let editor = ConnectionEditorStore(connection: .localOllama, isNew: false, catalog: loader, readKey: { _ in nil })
        editor.discoverModels()
        try await waitForRequests(loader, 1)
        editor.setAPIKey("new-key")
        await loader.resolve(1, models: ["old-account-model"])
        try await Task.sleep(for: .milliseconds(10))
        #expect(editor.connection.modelIDs == editor.original.modelIDs)
    }
}
