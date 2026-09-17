import AI
import Foundation

/// Only this adapter imports the SDK. No SDK types are persisted or exposed to views.
struct SDKGenerationClient: GenerationClient {
    func stream(_ request: GenerationRequest, apiKey: String?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = NetworkSession.make()
                defer { session.invalidateAndCancel() }
                do {
                    try EndpointPolicy.validateEndpoint(request.connection)
                    let endpoint = try EndpointPolicy.baseURL(request.connection.endpoint)
                    let key = apiKey ?? "" // Never read a different connection's environment key.
                    let headers = try request.connection.additionalHeaders()
                    let model: any LanguageModel
                    switch request.connection.kind {
                    case .anthropic:
                        model = AnthropicModel(request.modelID, apiKey: key, baseURL: endpoint, urlSession: session)
                    case .google:
                        model = GoogleModel(request.modelID, apiKey: key, baseURL: endpoint, urlSession: session)
                    case .openAI:
                        model = OpenAIChatModel(request.modelID, apiKey: key, baseURL: endpoint, urlSession: session)
                    case .openRouter, .compatible:
                        let provider = OpenAICompatibleProvider(
                            name: request.connection.provider.id, baseURL: endpoint,
                            apiKey: key, headers: headers, urlSession: session
                        )
                        model = provider(request.modelID)
                    case .ollama:
                        throw ChatError.provider("Ollama uses the native transport, not the cloud adapter.")
                    }
                    let messages: [AI.Message] = request.messages.map { prompt in
                        if let images = prompt.images, !images.isEmpty {
                            let contents = images.compactMap { Data(base64Encoded: $0).map { ImageContent(data: $0) } }
                            if !contents.isEmpty {
                                return .user(prompt.content, images: contents)
                            }
                        }
                        switch prompt.role {
                        case "system": return .system(prompt.content)
                        case "assistant": return .assistant(prompt.content)
                        default: return .user(prompt.content)
                        }
                    }
                    let result = streamText(
                        model: model, messages: messages,
                        maxOutputTokens: request.connection.maxOutputTokens,
                        maxSteps: 1, maxRetries: 0, telemetry: .disabled
                    )
                    var finished = false
                    for try await part in result.fullStream {
                        try Task.checkCancellation()
                        switch part {
                        case .textDelta(let delta): continuation.yield(.text(delta))
                        case .reasoningDelta(let delta): continuation.yield(.reasoning(delta))
                        case .finish(let reason, let usage):
                            finished = true
                            continuation.yield(.finished(reason: reason.rawValue,
                                usage: .init(input: usage.inputTokens, output: usage.outputTokens)))
                        default: break // No tools are configured or executed by this app.
                        }
                    }
                    try Task.checkCancellation()
                    guard finished else { throw ChatError.incompleteStream }
                    continuation.finish()
                } catch {
                    if let aiError = error as? AIError, case .http(let code, _) = aiError {
                        continuation.finish(throwing: ChatError.http(code))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

struct RoutedGenerationClient: GenerationClient {
    func stream(_ request: GenerationRequest, apiKey: String?) -> AsyncThrowingStream<GenerationEvent, Error> {
        if request.connection.kind == .ollama {
            OllamaGenerationClient().stream(request, apiKey: apiKey)
        } else {
            SDKGenerationClient().stream(request, apiKey: apiKey)
        }
    }
}
