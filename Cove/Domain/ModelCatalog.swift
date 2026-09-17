import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct CatalogCursor: Equatable, Hashable, Sendable {
    let parameter: String
    let value: String
}
struct ModelCatalogPage: Equatable, Sendable {
    let modelIDs: [String]
    let next: CatalogCursor?
    let hasMore: Bool
}
struct ModelCatalogResult: Equatable, Sendable {
    let modelIDs: [String]
    let isComplete: Bool
    let pages: Int
}

/// Pure request/response rules, shared by the real service and portable tests.
/// Pagination accepts tokens, never a remote next URL that could exfiltrate the key.
enum ModelCatalogProtocol {
    static func request(connection: ProviderConnection, apiKey: String?, cursor: CatalogCursor? = nil) throws -> URLRequest {
        try EndpointPolicy.validateEndpoint(connection)
        guard connection.provider.catalog == .discover else {
            throw ChatError.provider("This preset uses manual model IDs. Open the provider documentation to choose one.")
        }
        let key = (apiKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if connection.requiresKey && key.isEmpty { throw ChatError.missingKey }
        let base = try EndpointPolicy.baseURL(connection.endpoint)
        let path = connection.kind == .ollama ? "api/tags" : "models"
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        var query: [URLQueryItem] = []
        switch connection.kind {
        case .google: query.append(.init(name: "pageSize", value: "100"))
        case .anthropic: query.append(.init(name: "limit", value: "100"))
        default: break
        }
        if let cursor {
            let allowed: String? = connection.kind == .google ? "pageToken" : (connection.kind == .anthropic ? "after_id" : nil)
            guard cursor.parameter == allowed, !cursor.value.isEmpty else {
                throw ChatError.provider("The provider returned an unsupported catalog cursor.")
            }
            query.append(.init(name: cursor.parameter, value: cursor.value))
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw ChatError.invalidEndpoint }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if connection.kind == .anthropic { request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version") }
        if !key.isEmpty {
            switch connection.kind {
            case .anthropic: request.setValue(key, forHTTPHeaderField: "x-api-key")
            case .google: request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            default: request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }
        }
        for (name, value) in try connection.additionalHeaders() { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    static func page(from data: Data, kind: ProviderKind) throws -> ModelCatalogPage {
        struct Envelope: Decodable {
            struct Item: Decodable {
                struct Architecture: Decodable { var output_modalities: [String]? }
                var id: String?
                var name: String?
                var model: String?
                var supportedGenerationMethods: [String]?
                var architecture: Architecture?
            }
            var models: [Item]?
            var data: [Item]?
            var nextPageToken: String?
            var has_more: Bool?
            var last_id: String?
        }
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: data) }
        catch { throw ChatError.provider("The server did not return a supported model catalog. Enter a model ID manually or check the API base URL.") }
        guard let items = envelope.models ?? envelope.data else {
            throw ChatError.provider("The response is not a model catalog. Check the API base URL; no settings were changed.")
        }
        let ids = items.compactMap { item -> String? in
            if kind == .google, let methods = item.supportedGenerationMethods, !methods.contains("generateContent") { return nil }
            if let modalities = item.architecture?.output_modalities, !modalities.contains("text") { return nil }
            guard var value = item.id ?? item.name ?? item.model else { return nil }
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if kind == .google, value.hasPrefix("models/") { value = String(value.dropFirst(7)) }
            return value.isEmpty ? nil : value
        }
        var next: CatalogCursor?
        if kind == .google, let token = envelope.nextPageToken, !token.isEmpty {
            next = .init(parameter: "pageToken", value: token)
        } else if kind == .anthropic, envelope.has_more == true, let last = envelope.last_id, !last.isEmpty {
            next = .init(parameter: "after_id", value: last)
        }
        return .init(modelIDs: Array(Set(ids)).sorted(), next: next,
                     hasMore: next != nil || envelope.has_more == true || !(envelope.nextPageToken ?? "").isEmpty)
    }
}

/// IDs stay unambiguous when two connections offer the same model ID.
struct ModelChoice: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let connectionID: UUID
        let modelID: String
    }
    let connection: ProviderConnection
    let modelID: String
    var id: ID { .init(connectionID: connection.id, modelID: modelID) }

    static func matching(_ query: String, connections: [ProviderConnection],
                         selectedConnectionID: UUID?, selectedModelID: String) -> [Self] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return connections.flatMap { connection -> [Self] in
            let extras = connection.id == selectedConnectionID ? [selectedModelID] : []
            let ids = Set(connection.availableModels + extras).filter { !$0.isEmpty }.sorted()
            return ids.compactMap { modelID in
                let haystack = "\(connection.name) \(connection.provider.title) \(modelID) \(ProviderConnection.displayName(modelID))"
                guard words.allSatisfy({ haystack.localizedCaseInsensitiveContains($0) }) else { return nil }
                return Self(connection: connection, modelID: modelID)
            }
        }
    }
}
