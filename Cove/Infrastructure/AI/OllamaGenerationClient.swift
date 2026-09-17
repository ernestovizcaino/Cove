import Foundation

/// Native NDJSON keeps Ollama's `thinking` field separate from visible content.
struct OllamaGenerationClient: GenerationClient {
    func stream(_ request: GenerationRequest, apiKey: String?) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let session = NetworkSession.make()
                defer { session.invalidateAndCancel() }
                do {
                    let base = try EndpointPolicy.baseURL(request.connection.endpoint)
                    var http = URLRequest(url: base.appendingPathComponent("api/chat"))
                    http.httpMethod = "POST"
                    http.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    http.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
                    if let apiKey, !apiKey.isEmpty { http.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
                    struct Body: Encodable {
                        struct Options: Encodable { var num_predict: Int }
                        var model: String
                        var messages: [PromptMessage]
                        var stream = true
                        var options: Options
                    }
                    http.httpBody = try JSONEncoder().encode(Body(
                        model: request.modelID, messages: request.messages,
                        options: .init(num_predict: request.connection.maxOutputTokens)
                    ))
                    let (bytes, response) = try await session.bytes(for: http)
                    guard let response = response as? HTTPURLResponse else { throw ChatError.disconnected }
                    guard (200..<300).contains(response.statusCode) else { throw ChatError.http(response.statusCode) }
                    var finished = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        let events = try OllamaFrame.events(from: line)
                        for event in events {
                            continuation.yield(event)
                            if case .finished = event { finished = true }
                        }
                        if finished { break }
                    }
                    try Task.checkCancellation()
                    guard finished else { throw ChatError.incompleteStream }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
