import Foundation
#if os(macOS)
import Observation
#endif

// Observation drives SwiftUI on macOS. The same controller runs headless in Linux tests.
#if os(macOS)
@Observable
#endif
@MainActor final class ConnectionEditorStore {
    var connection: ProviderConnection
    var apiKey = ""
    var status: String?
    var statusIsError = false
    var isDiscovering = false
    let original: ProviderConnection
    let isNew: Bool

    private let catalog: any ModelCatalogLoading
    private let readKey: (ProviderConnection) throws -> String?
    private var task: Task<Void, Never>?
    private var lookupID: UUID?

    init(connection: ProviderConnection, isNew: Bool, catalog: any ModelCatalogLoading = ModelCatalogService(),
         readKey: @escaping (ProviderConnection) throws -> String?) {
        self.connection = connection; self.original = connection; self.isNew = isNew
        self.catalog = catalog; self.readKey = readKey
    }
    var isDirty: Bool { connection != original || !apiKey.isEmpty }
    var canSave: Bool {
        !isDiscovering && !connection.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && (try? EndpointPolicy.validate(connection)) != nil
    }
    func setEndpoint(_ value: String) {
        guard value != connection.endpoint else { return }
        connection.endpoint = value
        endpointChanged()
    }
    func setAPIKey(_ value: String) {
        guard value != apiKey else { return }
        apiKey = value
        credentialChanged()
    }
    func endpointChanged() {
        cancelDiscovery()
        // Never send a pasted key to a different endpoint, even in an unsaved draft.
        apiKey = ""; connection.modelIDs = []; connection.defaultModelID = ""
        status = "Endpoint changed. Choose its model again and enter its key if needed."
        statusIsError = false
    }
    func credentialChanged() {
        cancelDiscovery()
        status = nil; statusIsError = false
    }
    func discoverModels() {
        cancelDiscovery()
        let snapshot = connection
        let key: String?
        do {
            let supplied = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            key = supplied.isEmpty ? try readKey(snapshot) : supplied
            _ = try ModelCatalogProtocol.request(connection: snapshot, apiKey: key)
        } catch { report(error); return }
        let id = UUID(); lookupID = id; isDiscovering = true
        status = nil; statusIsError = false
        let loader = catalog
        task = Task { @MainActor [weak self] in
            do {
                let result = try await loader.discover(connection: snapshot, apiKey: key)
                try Task.checkCancellation()
                guard let self, self.lookupID == id else { return }
                self.connection.modelIDs = result.modelIDs
                if self.connection.defaultModelID.isEmpty {
                    self.connection.defaultModelID = result.modelIDs.first ?? ""
                }
                let count = result.modelIDs.count
                self.status = count == 0
                    ? "Catalog reached, but no text models were listed. Enter a model ID manually. No chat was sent."
                    : "Found \(count) models\(result.isComplete ? "" : " (partial catalog)"). No chat was sent; this does not verify generation or billing. Save to keep this list."
                self.finishLookup(id)
            } catch {
                guard let self, self.lookupID == id else { return }
                if !(error is CancellationError) && !Task.isCancelled { self.report(error) }
                self.finishLookup(id)
            }
        }
    }
    func cancelDiscovery() {
        lookupID = nil; task?.cancel(); task = nil; isDiscovering = false
    }
    private func finishLookup(_ id: UUID) {
        guard lookupID == id else { return }
        lookupID = nil; task = nil; isDiscovering = false
    }
    func report(_ error: Error) {
        statusIsError = true
        status = NetworkSession.readableError(error)
    }
    func tearDown() { cancelDiscovery(); apiKey = "" }
}
