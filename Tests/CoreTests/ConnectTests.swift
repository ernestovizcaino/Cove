import Foundation
import Testing
@testable import CoveCore

@Test func providerCatalogHasUniqueStableIDs() {
    #expect(ProviderCatalog.all.count == 12)
    #expect(Set(ProviderCatalog.all.map(\.id)).count == ProviderCatalog.all.count)
}
@Test func providerCategoriesSeparateLocalFromAPIs() {
    #expect(Set(ProviderCatalog.presets(in: .local).map(\.id)) == ["ollama", "lmStudio"])
    #expect(ProviderCatalog.presets(in: .api).allSatisfy { $0.requiresKey })
    #expect(ProviderCatalog.custom.category == nil)
}
@Test func presetsProduceIndependentConnections() {
    let preset = ProviderCatalog.preset(id: "anthropic")!
    let first = preset.newConnection(), second = preset.newConnection()
    #expect(first.id != second.id)
    #expect(first.provider.id == "anthropic")
    #expect(first.defaultModelID.isEmpty)
}
@Test func cloudModelNamesAreNotHardcoded() {
    for preset in ProviderCatalog.presets(in: .api) {
        #expect(preset.newConnection().modelIDs.isEmpty)
        #expect(preset.newConnection().defaultModelID.isEmpty)
    }
}
@Test func lmStudioReusesCompatibleTransportNotOllamaProtocol() throws {
    let connection = ProviderCatalog.preset(id: "lmStudio")!.newConnection()
    #expect(connection.kind == .compatible)
    #expect(connection.endpoint == "http://localhost:1234/v1")
    #expect(!connection.requiresKey)
    #expect(try ModelCatalogProtocol.request(connection: connection, apiKey: nil).url?.path == "/v1/models")
}
@Test func apiPresetRequiresKeyEvenWithCompatibleTransport() {
    let connection = ProviderCatalog.preset(id: "deepseek")!.newConnection()
    #expect(connection.kind == .compatible)
    #expect(connection.requiresKey)
    #expect(throws: ChatError.missingKey) { try ModelCatalogProtocol.request(connection: connection, apiKey: nil) }
}
@Test func customConnectionAcceptsAnOptionalKey() throws {
    var connection = ProviderCatalog.custom.newConnection()
    connection.endpoint = "http://localhost:8080/v1"
    _ = try ModelCatalogProtocol.request(connection: connection, apiKey: nil)
    #expect(!connection.requiresKey)
}
@Test func presetsNeverPretendWebsiteSubscriptionsAreAPIs() {
    #expect(!ProviderCatalog.all.contains { ["chatgpt", "claudeSubscription", "copilot", "kimiCode"].contains($0.id) })
}
@Test func oldConnectionPayloadDecodesWithoutNewFields() throws {
    let payload = Data(#"{"id":"11111111-1111-1111-1111-111111111111","kind":"ollama","name":"My existing PC","endpoint":"http://192.168.1.50:11434","modelIDs":["my-model"],"defaultModelID":"my-model","maxOutputTokens":4096}"#.utf8)
    let connection = try JSONDecoder().decode(ProviderConnection.self, from: payload)
    #expect(connection.presetID == nil)
    #expect(connection.gatewayID == nil)
    #expect(connection.provider.id == "ollama")
    #expect(connection.defaultModelID == "my-model")
}
@Test func connectionRoundTripPreservesPreset() throws {
    var connection = ProviderCatalog.preset(id: "cloudflare")!.newConnection()
    connection.gatewayID = "my-gateway"
    let data = try JSONEncoder().encode(connection)
    #expect(try JSONDecoder().decode(ProviderConnection.self, from: data) == connection)
}
@Test func unknownPresetRetainsProtocolAndDoesNotCrash() {
    var connection = ProviderConnection.blank(.anthropic)
    connection.presetID = "added-in-a-newer-app"
    #expect(connection.provider.kind == .anthropic)
    #expect(connection.requiresKey)
}
@Test func mismatchedPresetCannotOverrideWireProtocol() {
    var connection = ProviderConnection.blank(.anthropic)
    connection.presetID = "lmStudio"
    #expect(connection.provider.id == "anthropic")
    #expect(connection.requiresKey)
}
@Test func cloudflareUsesCurrentRESTEndpointAndManualModelIDs() throws {
    var connection = ProviderCatalog.preset(id: "cloudflare")!.newConnection()
    #expect(connection.provider.catalog == .manual)
    #expect(throws: (any Error).self) { try EndpointPolicy.validateEndpoint(connection) }
    connection.endpoint = "https://api.cloudflare.com/client/v4/accounts/" + String(repeating: "a", count: 32) + "/ai/v1"
    try EndpointPolicy.validateEndpoint(connection)
    #expect(try connection.additionalHeaders() == ["cf-aig-gateway-id": "default"])
    #expect(throws: (any Error).self) { try ModelCatalogProtocol.request(connection: connection, apiKey: "test") }
}
@Test func cloudflareHeadersRejectInjection() {
    var connection = ProviderCatalog.preset(id: "cloudflare")!.newConnection()
    connection.gatewayID = "default\r\nAuthorization: secret"
    #expect(throws: (any Error).self) { try connection.additionalHeaders() }
}
@Test func cloudflarePresetDoesNotSendHeadersToAnotherHost() {
    var connection = ProviderCatalog.preset(id: "cloudflare")!.newConnection()
    connection.endpoint = "https://other.example/client/v4/accounts/" + String(repeating: "a", count: 32) + "/ai/v1"
    #expect(throws: (any Error).self) { try EndpointPolicy.validateEndpoint(connection) }
}
@Test func providerLabelDoesNotDetermineNetworkPrivacy() {
    var connection = ProviderCatalog.preset(id: "lmStudio")!.newConnection()
    connection.endpoint = "https://my-cloud.example/v1"
    #expect(!EndpointPolicy.isLocal(connection.endpoint))
    #expect(connection.provider.category == .local)
}
@Test func baseURLsStayDistinctForLANProtocols() throws {
    let ollama = ProviderConnection.localOllama
    #expect(try ModelCatalogProtocol.request(connection: ollama, apiKey: nil).url?.path == "/api/tags")
    let lm = ProviderCatalog.preset(id: "lmStudio")!.newConnection()
    #expect(try ModelCatalogProtocol.request(connection: lm, apiKey: nil).url?.path == "/v1/models")
}
@Test func credentialHeadersMatchProviderProtocols() throws {
    let anthropic = try ModelCatalogProtocol.request(connection: .blank(.anthropic), apiKey: "test-secret")
    #expect(anthropic.value(forHTTPHeaderField: "x-api-key") == "test-secret")
    #expect(anthropic.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
    #expect(anthropic.value(forHTTPHeaderField: "Authorization") == nil)
    let google = try ModelCatalogProtocol.request(connection: .blank(.google), apiKey: "test-secret")
    #expect(google.value(forHTTPHeaderField: "x-goog-api-key") == "test-secret")
    #expect(google.url?.query?.contains("test-secret") != true)
    let compatible = try ModelCatalogProtocol.request(connection: .blank(.openRouter), apiKey: "test-secret")
    #expect(compatible.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret")
}
@Test func catalogRequestDoesNotRequireModelYet() throws {
    let request = try ModelCatalogProtocol.request(connection: .blank(.anthropic), apiKey: "key")
    #expect(request.httpMethod == "GET")
    #expect(request.httpBody == nil)
}
@Test func googleCursorIsEncodedOnTheSameEndpoint() throws {
    let connection = ProviderConnection.blank(.google)
    let cursor = CatalogCursor(parameter: "pageToken", value: "https://evil.example/a?steal=1&key=2")
    let request = try ModelCatalogProtocol.request(connection: connection, apiKey: "secret", cursor: cursor)
    #expect(request.url?.host == "generativelanguage.googleapis.com")
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
    #expect(items?.first(where: { $0.name == "pageToken" })?.value == cursor.value)
}
@Test func unsupportedPaginationIsRejected() {
    #expect(throws: (any Error).self) {
        try ModelCatalogProtocol.request(connection: .blank(.openRouter), apiKey: "key",
            cursor: .init(parameter: "next_url", value: "https://evil.example"))
    }
}
@Test func malformedCatalogDoesNotMasqueradeAsEmptySuccess() {
    for value in ["<html>login</html>", #"{"error":"secret value"}"#, #"{}"#] {
        #expect(throws: (any Error).self) { try ModelCatalogProtocol.page(from: Data(value.utf8), kind: .compatible) }
    }
}
@Test func catalogAllowsGenuinelyEmptyList() throws {
    let result = try ModelCatalogProtocol.page(from: Data(#"{"data":[]}"#.utf8), kind: .openAI)
    #expect(result.modelIDs.isEmpty)
    #expect(!result.hasMore)
}
@Test func catalogDeduplicatesAndTrimsIDs() throws {
    let result = try ModelCatalogProtocol.page(from: Data(#"{"data":[{"id":" a "},{"id":"a"},{"id":""},{"id":"b"}]}"#.utf8), kind: .compatible)
    #expect(result.modelIDs == ["a", "b"])
}
@Test func googleDiscoveryFiltersNonGeneratingModelsAndFollowsToken() throws {
    let json = #"{"models":[{"name":"models/chat","supportedGenerationMethods":["generateContent"]},{"name":"models/embed","supportedGenerationMethods":["embedContent"]}],"nextPageToken":"next-token"}"#
    let page = try ModelCatalogProtocol.page(from: Data(json.utf8), kind: .google)
    #expect(page.modelIDs == ["chat"])
    #expect(page.next == .init(parameter: "pageToken", value: "next-token"))
    #expect(page.hasMore)
}
@Test func anthropicDiscoveryUsesDocumentedCursor() throws {
    let page = try ModelCatalogProtocol.page(from: Data(#"{"data":[{"id":"claude-example"}],"has_more":true,"last_id":"claude-example"}"#.utf8), kind: .anthropic)
    #expect(page.next == .init(parameter: "after_id", value: "claude-example"))
    let request = try ModelCatalogProtocol.request(connection: .blank(.anthropic), apiKey: "key", cursor: page.next)
    #expect(request.url?.query?.contains("after_id=claude-example") == true)
}
@Test func incompleteCatalogWithoutACursorRemainsMarkedPartial() throws {
    let page = try ModelCatalogProtocol.page(from: Data(#"{"data":[],"has_more":true}"#.utf8), kind: .compatible)
    #expect(page.hasMore)
    #expect(page.next == nil)
}
@Test func openRouterDiscoveryFiltersExplicitNonTextModels() throws {
    let json = #"{"data":[{"id":"a/chat","architecture":{"output_modalities":["text"]}},{"id":"a/image","architecture":{"output_modalities":["image"]}},{"id":"a/unknown"}]}"#
    let page = try ModelCatalogProtocol.page(from: Data(json.utf8), kind: .openRouter)
    #expect(page.modelIDs == ["a/chat", "a/unknown"])
}
@Test func twoServersWithSameModelHaveDifferentSelectionIDs() {
    var first = ProviderConnection.localOllama
    var second = first; second.id = UUID(); second.name = "Another PC"
    first.modelIDs = ["qwen"]; first.defaultModelID = "qwen"
    second.modelIDs = ["qwen"]; second.defaultModelID = "qwen"
    let choices = ModelChoice.matching("qwen", connections: [first, second], selectedConnectionID: nil, selectedModelID: "")
    #expect(choices.count == 2)
    #expect(Set(choices.map(\.id)).count == 2)
}
@Test func modelSearchIncludesConnectionAndProviderWithoutThirtyModelLimit() {
    var connection = ProviderConnection.localOllama
    connection.name = "Office Windows"
    connection.modelIDs = (0..<120).map { "model-\($0)" }
    connection.defaultModelID = "model-0"
    #expect(ModelChoice.matching("", connections: [connection], selectedConnectionID: nil, selectedModelID: "").count == 120)
    #expect(ModelChoice.matching("office Ollama 119", connections: [connection], selectedConnectionID: nil, selectedModelID: "").map(\.modelID) == ["model-119"])
}
@Test func modelPickerRetainsManuallySelectedModels() {
    let connection = ProviderConnection.localOllama
    let choices = ModelChoice.matching("manual", connections: [connection], selectedConnectionID: connection.id, selectedModelID: "manual/id")
    #expect(choices.map(\.modelID) == ["manual/id"])
}
