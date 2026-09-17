import Foundation

struct BuiltContext: Equatable, Sendable {
    var messages: [PromptMessage]
    var droppedTurns: Int
}

enum ContextBuilder {
    /// A conservative CHARACTER budget, deliberately not presented as token counting.
    /// Only whole, successfully completed turns cross provider boundaries.
    static func build(history: [ChatMessage], prompt: String, system: String = "",
                      characterBudget: Int = 32_000) throws -> BuiltContext {
        let overhead = 64
        var budget = characterBudget - prompt.count - system.count - overhead * 2
        guard budget >= 0 else { throw ChatError.oversizedPrompt }
        var turns: [[PromptMessage]] = []
        var pending: ChatMessage?
        for message in history.sorted(by: { $0.sequence < $1.sequence }) {
            if message.role == .user { pending = message; continue }
            if let user = pending, message.status == .completed, !message.text.isEmpty {
                turns.append([.init(role: "user", content: user.text),
                              .init(role: "assistant", content: message.text)])
            }
            pending = nil
        }
        var kept: [[PromptMessage]] = []
        for turn in turns.reversed() {
            let cost = turn.reduce(0) { $0 + $1.content.count + overhead }
            guard cost <= budget else { break }
            kept.append(turn)
            budget -= cost
        }
        var output: [PromptMessage] = []
        if !system.isEmpty { output.append(.init(role: "system", content: system)) }
        output += kept.reversed().flatMap { $0 }
        output.append(.init(role: "user", content: prompt))
        return BuiltContext(messages: output, droppedTurns: turns.count - kept.count)
    }
}
