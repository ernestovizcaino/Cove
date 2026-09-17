import Foundation

/// Decoded independently of URLSession so stream edge cases can be unit tested.
struct OllamaFrame: Decodable, Sendable {
    struct ResponseMessage: Decodable, Sendable {
        var content: String?
        var thinking: String?
    }
    var message: ResponseMessage?
    var done: Bool?
    var done_reason: String?
    var prompt_eval_count: Int?
    var eval_count: Int?
    var error: String?

    static func events(from line: String) throws -> [GenerationEvent] {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let frame = try JSONDecoder().decode(Self.self, from: Data(line.utf8))
        if frame.error != nil {
            // Do not echo arbitrary server bodies (they may contain prompts or secrets).
            throw ChatError.provider("Ollama rejected the request. Verify the installed model and check the PC's Ollama logs.")
        }
        var events: [GenerationEvent] = []
        if let value = frame.message?.thinking, !value.isEmpty { events.append(.reasoning(value)) }
        if let value = frame.message?.content, !value.isEmpty { events.append(.text(value)) }
        if frame.done == true {
            events.append(.finished(reason: frame.done_reason ?? "stop",
                                    usage: .init(input: frame.prompt_eval_count, output: frame.eval_count)))
        }
        return events
    }
}
