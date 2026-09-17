import Foundation

/// A display/provider preset is deliberately separate from the wire protocol.
/// New OpenAI-compatible services do not require new persistence enum cases.
enum ProviderCategory: String, CaseIterable, Identifiable, Sendable {
    case api = "API", local = "Local"
    var id: String { rawValue }
}

enum CatalogAvailability: Sendable { case discover, manual }

struct ProviderPreset: Identifiable, Sendable {
    let id: String
    let title: String
    let category: ProviderCategory?
    let kind: ProviderKind
    let endpoint: String
    let symbol: String
    let requiresKey: Bool
    var catalog: CatalogAvailability = .discover
    let help: String
    let documentationURL: String

    func newConnection() -> ProviderConnection {
        ProviderConnection(kind: kind, name: title, endpoint: endpoint,
                           modelIDs: [], defaultModelID: "", presetID: id,
                           gatewayID: id == "cloudflare" ? "default" : nil)
    }
}

enum ProviderCatalog {
    static let custom = ProviderPreset(
        id: "custom", title: "Custom provider", category: nil, kind: .compatible,
        endpoint: "", symbol: "server.rack", requiresKey: false,
        help: "Use an OpenAI Chat Completions-compatible API base, usually ending in /v1. A key is optional for local servers. Other protocols are not interchangeable.",
        documentationURL: "https://swift-ai-sdk.dev/docs/providers/openai-compatible"
    )

    // No cloud model IDs are guessed or stored as a supposedly current catalog.
    // See docs/CONNECT.md for the primary sources and deliberately unsupported logins.
    static let all: [ProviderPreset] = [
        .init(id: "anthropic", title: "Anthropic", category: .api, kind: .anthropic,
              endpoint: "https://api.anthropic.com/v1", symbol: "asterisk", requiresKey: true,
              help: "Use a Claude Console API key. A Claude chat subscription is not an API key.",
              documentationURL: "https://platform.claude.com/docs/en/api/overview"),
        .init(id: "cloudflare", title: "Cloudflare AI Gateway", category: .api, kind: .compatible,
              endpoint: "https://api.cloudflare.com/client/v4/accounts/ACCOUNT_ID/ai/v1",
              symbol: "cloud", requiresKey: true, catalog: .manual,
              help: "Replace ACCOUNT_ID with your account ID. Use a Cloudflare API token with Account > Workers AI > Read permission. Enter a model ID from Cloudflare's catalog. This preset uses the current REST API, not the deprecated /compat endpoint.",
              documentationURL: "https://developers.cloudflare.com/ai-gateway/usage/rest-api/"),
        .init(id: "deepseek", title: "DeepSeek", category: .api, kind: .compatible,
              endpoint: "https://api.deepseek.com", symbol: "water.waves", requiresKey: true,
              help: "Connect with a DeepSeek API key. Discover the models available to your account or enter an ID manually.",
              documentationURL: "https://api-docs.deepseek.com/"),
        .init(id: "google", title: "Google", category: .api, kind: .google,
              endpoint: "https://generativelanguage.googleapis.com/v1beta", symbol: "sparkle", requiresKey: true,
              help: "Use a Gemini API key from Google AI Studio. Only models advertising generateContent are included in discovery.",
              documentationURL: "https://ai.google.dev/api/models"),
        .init(id: "kimi", title: "Kimi (Moonshot API)", category: .api, kind: .compatible,
              endpoint: "https://api.moonshot.ai/v1", symbol: "moon", requiresKey: true,
              help: "Use a Moonshot API key. This is the general Kimi API, not Kimi Code subscription sign-in.",
              documentationURL: "https://platform.kimi.ai/docs/overview"),
        .init(id: "openAI", title: "OpenAI", category: .api, kind: .openAI,
              endpoint: "https://api.openai.com/v1", symbol: "circle.hexagongrid", requiresKey: true,
              help: "Use an OpenAI API key and a model that supports Chat Completions. ChatGPT subscriptions and API usage are billed separately. Responses-only models are not supported by this adapter.",
              documentationURL: "https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create"),
        .init(id: "openRouter", title: "OpenRouter", category: .api, kind: .openRouter,
              endpoint: "https://openrouter.ai/api/v1", symbol: "arrow.triangle.branch", requiresKey: true,
              help: "Use an OpenRouter API key. The model catalog is not proof that a key, balance or selected model can generate a response.",
              documentationURL: "https://openrouter.ai/docs/api-reference/models/get-models"),
        .init(id: "vercel", title: "Vercel AI Gateway", category: .api, kind: .compatible,
              endpoint: "https://ai-gateway.vercel.sh/v1", symbol: "triangle.fill", requiresKey: true,
              help: "Use an AI Gateway API key. Keep the full provider/model identifier returned by the catalog.",
              documentationURL: "https://vercel.com/docs/ai-gateway/sdks-and-apis/openai-chat-completions"),
        .init(id: "xai", title: "xAI (Grok API)", category: .api, kind: .compatible,
              endpoint: "https://api.x.ai/v1", symbol: "sparkles", requiresKey: true,
              help: "Use an xAI API key, not a Grok website session or subscription token. Choose a chat-compatible model.",
              documentationURL: "https://docs.x.ai/developers/rest-api-reference/inference/chat"),
        .init(id: "zai", title: "Z.ai", category: .api, kind: .compatible,
              endpoint: "https://api.z.ai/api/paas/v4", symbol: "z.square", requiresKey: true, catalog: .manual,
              help: "Use a general Z.ai API key and enter a model ID from its documentation. This preset does not use a Coding Plan subscription endpoint.",
              documentationURL: "https://docs.z.ai/guides/overview/quick-start"),
        .init(id: "lmStudio", title: "LM Studio", category: .local, kind: .compatible,
              endpoint: "http://localhost:1234/v1", symbol: "desktopcomputer", requiresKey: false,
              help: "Start the LM Studio API server on the chosen computer. localhost means this Mac; for another computer use its LAN address. Keep /v1. Enter a token only if authentication is enabled on that server.",
              documentationURL: "https://lmstudio.ai/docs/developer/openai-compat"),
        .init(id: "ollama", title: "Ollama", category: .local, kind: .ollama,
              endpoint: "http://localhost:11434", symbol: "externaldrive.connected.to.line.below", requiresKey: false,
              help: "Enter the server address without /api or /v1. This can be another computer on your network; Ollama does not need to run on this Mac.",
              documentationURL: "https://docs.ollama.com/api/tags")
    ]

    static func preset(id: String) -> ProviderPreset? {
        id == custom.id ? custom : all.first { $0.id == id }
    }
    static func preset(for connection: ProviderConnection) -> ProviderPreset {
        if let id = connection.presetID, let value = preset(id: id), value.kind == connection.kind { return value }
        // Legacy records carry only the protocol. Do not infer a brand from a user label or hostname.
        return all.first { $0.kind == connection.kind && $0.kind != .compatible } ?? custom
    }
    static func presets(in category: ProviderCategory) -> [ProviderPreset] {
        all.filter { $0.category == category }
    }
}

extension ProviderConnection {
    var provider: ProviderPreset { ProviderCatalog.preset(for: self) }
    var requiresKey: Bool { provider.requiresKey || kind.requiresKey }

    /// Non-secret, narrowly scoped provider headers. Arbitrary auth headers are not persisted.
    func additionalHeaders() throws -> [String: String] {
        guard provider.id == "cloudflare" else { return [:] }
        let gateway = (gatewayID ?? "default").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gateway.isEmpty, gateway.count <= 64,
              gateway.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            throw ChatError.provider("Use a gateway ID containing only letters, numbers, hyphens or underscores.")
        }
        return ["cf-aig-gateway-id": gateway]
    }
}
