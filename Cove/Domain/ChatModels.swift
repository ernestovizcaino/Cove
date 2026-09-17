import Foundation

enum MessageRole: String, Codable, Sendable { case user, assistant }
enum MessageStatus: String, Codable, Sendable {
    case streaming, completed, cancelled, failed, interrupted
}

enum MessagePart: Codable, Equatable, Sendable {
    case text(String)
    case reasoning(String)
    case image(data: Data, mimeType: String)
}

struct TokenUsage: Codable, Equatable, Sendable {
    var input: Int?
    var output: Int?
}

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var sequence: Int
    var role: MessageRole
    var parts: [MessagePart] = []
    var createdAt = Date()
    var status: MessageStatus = .completed
    var connectionID: UUID?
    var providerName: String?
    var modelID: String?
    var generationID: UUID?
    var usage: TokenUsage?
    var finishReason: String?
    var errorMessage: String?

    var text: String {
        parts.compactMap { if case let .text(value) = $0 { value } else { nil } }.joined()
    }
    var reasoning: String {
        parts.compactMap { if case let .reasoning(value) = $0 { value } else { nil } }.joined()
    }
    var images: [Data] {
        parts.compactMap { if case let .image(data, _) = $0 { data } else { nil } }
    }
    mutating func append(text: String, reasoning: String) {
        appendPart(text, reasoning: false)
        appendPart(reasoning, reasoning: true)
    }
    private mutating func appendPart(_ delta: String, reasoning: Bool) {
        guard !delta.isEmpty else { return }
        let index = parts.firstIndex { part in
            switch (part, reasoning) {
            case (.text, false), (.reasoning, true): true
            default: false
            }
        }
        if let index {
            switch parts[index] {
            case .text(let value): parts[index] = .text(value + delta)
            case .reasoning(let value): parts[index] = .reasoning(value + delta)
            case .image: break
            }
        } else {
            parts.append(reasoning ? .reasoning(delta) : .text(delta))
        }
    }
}

struct Conversation: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title = "New chat"
    var createdAt = Date()
    var updatedAt = Date()
    var selectedConnectionID: UUID?
    var selectedModelID = ""
    var systemPrompt = ""
    var draft = ""
    var messages: [ChatMessage] = []

    static func title(for text: String) -> String {
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? "New chat" : String(cleaned.prefix(65))
    }

    static func cleanModelTitle(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["title:", "topic:", "subject:"] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let quotes = CharacterSet(charactersIn: "\"'`*“”«»#")
        text = text.trimmingCharacters(in: quotes).trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, [".", "!", "?", ":", ";"].contains(last) {
            text = String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !cleaned.isEmpty else { return "" }
        return String(cleaned.prefix(60))
    }
}

struct ConversationSummary: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var updatedAt: Date
}

enum ProviderKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case ollama, openRouter, openAI, anthropic, google, compatible
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ollama: "Ollama"
        case .openRouter: "OpenRouter"
        case .openAI: "OpenAI (Chat Completions)"
        case .anthropic: "Anthropic"
        case .google: "Google Gemini"
        case .compatible: "OpenAI-compatible"
        }
    }
    var defaultEndpoint: String {
        switch self {
        case .ollama: "http://localhost:11434"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .openAI: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com/v1"
        case .google: "https://generativelanguage.googleapis.com/v1beta"
        case .compatible: "http://localhost:1234/v1"
        }
    }
    var requiresKey: Bool { self != .ollama && self != .compatible }
}

struct ProviderConnection: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: ProviderKind
    var name: String
    var endpoint: String
    var modelIDs: [String]
    var defaultModelID: String
    var maxOutputTokens = 4096
    // Optional fields keep previously saved V1 JSON connection records readable.
    var presetID: String? = nil
    var gatewayID: String? = nil

    /// A neutral local starting point. Nothing is seeded on first launch; the
    /// home-screen onboarding card asks for a real provider instead of shipping
    /// someone else's server address.
    static let localOllama = ProviderConnection(
        kind: .ollama, name: "Ollama", endpoint: ProviderKind.ollama.defaultEndpoint,
        modelIDs: ["llama3.2"], defaultModelID: "llama3.2"
    )
    static func blank(_ kind: ProviderKind) -> Self {
        Self(kind: kind, name: kind.title, endpoint: kind.defaultEndpoint,
             modelIDs: [], defaultModelID: "")
    }
    var availableModels: [String] {
        Array(Set((modelIDs + [defaultModelID]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).filter { !$0.isEmpty }.sorted()
    }
    static func displayName(_ modelID: String) -> String {
        modelID.split(separator: "/").last.map(String.init) ?? modelID
    }
}

struct PromptMessage: Codable, Equatable, Sendable {
    var role: String
    var content: String
    var images: [String]? = nil
}

enum ModelCapabilities {
    static func supportsVision(connection: ProviderConnection?, modelID: String) -> Bool {
        guard let connection else { return false }
        let lower = modelID.lowercased()
        switch connection.kind {
        case .openAI:
            return lower.contains("gpt-4o") || lower.contains("gpt-4-turbo") || lower.contains("vision") || lower.contains("o1") || lower.contains("o3")
        case .anthropic:
            return lower.contains("claude-3") || lower.contains("claude-4")
        case .google:
            return lower.contains("gemini")
        case .ollama:
            return lower.contains("vision") || lower.contains("llava") || lower.contains("minicpm") || lower.contains("bakllava")
        case .openRouter, .compatible:
            return lower.contains("vision") || lower.contains("vl") || lower.contains("4o") || lower.contains("gemini") || lower.contains("claude-3")
        }
    }
}
struct GenerationRequest: Sendable {
    var id: UUID
    var connection: ProviderConnection
    var modelID: String
    var messages: [PromptMessage]
}
enum GenerationEvent: Equatable, Sendable {
    case text(String)
    case reasoning(String)
    case finished(reason: String, usage: TokenUsage)
}
protocol GenerationClient: Sendable {
    func stream(_ request: GenerationRequest, apiKey: String?) -> AsyncThrowingStream<GenerationEvent, Error>
}

enum ChatError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case insecureEndpoint
    case missingModel
    case missingKey
    case oversizedPrompt
    case disconnected
    case http(Int)
    case incompleteStream
    case provider(String)
    case storage(String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter a valid base URL, without credentials, query parameters, or a chat path."
        case .insecureEndpoint: "Use HTTPS for public servers. HTTP is only allowed for local/private addresses."
        case .missingModel: "Choose a model in Connections first."
        case .missingKey: "Add an API key for this endpoint in Connections."
        case .oversizedPrompt: "This message is too large for the starter's context budget. Shorten it or start a new chat."
        case .disconnected: "Cannot reach the server. Check the address, local-network permission, and that your PC is awake."
        case .http(401), .http(403): "The server rejected access. Check the API key and permissions."
        case .http(404): "The model or endpoint was not found. Check Connections."
        case .http(429): "The provider is rate limiting requests or has no available quota. Try again later."
        case .http(let code): "The server returned HTTP \(code). Check the model and connection settings."
        case .incompleteStream: "The connection ended before the response finished. Your partial response was kept."
        case .provider(let message): message
        case .storage(let message): message
        }
    }
}
