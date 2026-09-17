import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

protocol ModelCatalogLoading: Sendable {
    func discover(connection: ProviderConnection, apiKey: String?) async throws -> ModelCatalogResult
}

struct ModelCatalogService: ModelCatalogLoading {
    /// A catalog is not proof of valid billing or a working generation. No chat is sent.
    /// Only documented Google/Anthropic token pagination is followed, on the SAME endpoint.
    func discover(connection: ProviderConnection, apiKey: String?) async throws -> ModelCatalogResult {
        let session = NetworkSession.make()
        defer { session.invalidateAndCancel() }
        var ids = Set<String>()
        var cursor: CatalogCursor?
        var seen = Set<CatalogCursor>()
        for pageIndex in 1...10 {
            try Task.checkCancellation()
            let request = try ModelCatalogProtocol.request(connection: connection, apiKey: apiKey, cursor: cursor)
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw ChatError.disconnected }
            guard (200..<300).contains(http.statusCode) else { throw ChatError.http(http.statusCode) }
            let page = try ModelCatalogProtocol.page(from: data, kind: connection.kind)
            ids.formUnion(page.modelIDs)
            guard page.hasMore else { return .init(modelIDs: ids.sorted(), isComplete: true, pages: pageIndex) }
            guard let next = page.next, seen.insert(next).inserted, pageIndex < 10 else {
                return .init(modelIDs: ids.sorted(), isComplete: false, pages: pageIndex)
            }
            cursor = next
        }
        return .init(modelIDs: ids.sorted(), isComplete: false, pages: 10)
    }
}
