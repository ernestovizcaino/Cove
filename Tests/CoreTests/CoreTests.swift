import Foundation
import Testing
@testable import CoveCore

@Test func localOllamaDefaultsToThisMac() {
    let connection = ProviderConnection.localOllama
    #expect(connection.endpoint == "http://localhost:11434")
    #expect(connection.endpoint == ProviderKind.ollama.defaultEndpoint)
    #expect(connection.defaultModelID == "llama3.2")
}
@Test func endpointCanonicalization() throws {
    #expect(try EndpointPolicy.baseURL(" https://example.com/v1/// ").absoluteString == "https://example.com/v1")
}
@Test func allowsLocalLAN() throws {
    for endpoint in ["http://192.168.1.50:11434", "http://127.0.0.1:11434", "http://localhost:11434", "http://10.0.0.2", "http://[::1]:11434"] {
        _ = try EndpointPolicy.baseURL(endpoint)
    }
}
@Test func rejectsUnencryptedPublicEndpoint() {
    #expect(throws: ChatError.insecureEndpoint) { try EndpointPolicy.baseURL("http://example.com/v1") }
    #expect(throws: ChatError.insecureEndpoint) { try EndpointPolicy.baseURL("http://172.32.0.1") }
}
@Test func rejectsCredentialsAndQueryInURL() {
    for endpoint in ["https://user:secret@example.com", "https://example.com?key=secret", "file:///tmp/file", "https://example.com#token"] {
        #expect(throws: ChatError.invalidEndpoint) { try EndpointPolicy.baseURL(endpoint) }
    }
}
@Test func rejectsOperationURLs() {
    for endpoint in ["https://example.com/api/chat", "https://example.com/v1/chat/completions", "https://example.com/v1/messages"] {
        #expect(throws: ChatError.invalidEndpoint) { try EndpointPolicy.baseURL(endpoint) }
    }
}
@Test func rejectsOllamaV1URL() {
    var connection = ProviderConnection.localOllama
    connection.endpoint += "/v1"
    #expect(throws: ChatError.invalidEndpoint) { try EndpointPolicy.validate(connection) }
}
@Test func privateAddressBoundaries() {
    #expect(EndpointPolicy.isLocalHost("172.16.0.1"))
    #expect(EndpointPolicy.isLocalHost("172.31.255.255"))
    #expect(!EndpointPolicy.isLocalHost("172.15.0.1"))
    #expect(!EndpointPolicy.isLocalHost("192.168.example.com"))
    #expect(!EndpointPolicy.isLocalHost("10.0.0.999"))
    #expect(!EndpointPolicy.isLocalHost("fc.example.com"))
}
@Test func cloudOllamaStillNeedsDisclosure() {
    #expect(!EndpointPolicy.isLocal("https://ollama.example.com"))
}
@Test func endpointChangesRequireNewConsent() throws {
    var connection = ProviderConnection.localOllama
    let first = try EndpointPolicy.consentKey(for: connection)
    connection.endpoint = "https://models.example.com"
    #expect(try EndpointPolicy.consentKey(for: connection) != first)
}
@Test func catalogDeduplicatesAndKeepsManualModel() {
    var connection = ProviderConnection.localOllama
    connection.modelIDs = ["a", "a", "", "b"]
    #expect(connection.availableModels == ["a", "b", connection.defaultModelID])
}
@Test func emptyContextSendsOnlyNewPrompt() throws {
    #expect(try ContextBuilder.build(history: [], prompt: "Hello").messages == [.init(role: "user", content: "Hello")])
}
private func turn(_ index: Int, question: String = "Question", answer: String = "Answer", status: MessageStatus = .completed) -> [ChatMessage] {
    [.init(sequence: index, role: .user, parts: [.text(question)]),
     .init(sequence: index + 1, role: .assistant, parts: [.reasoning("private reasoning"), .text(answer)], status: status)]
}
@Test func contextIsSortedAndDoesNotForwardReasoning() throws {
    let context = try ContextBuilder.build(history: Array(turn(0).reversed()), prompt: "Next", system: "Instructions")
    #expect(context.messages.map(\.role) == ["system", "user", "assistant", "user"])
    #expect(!context.messages.map(\.content).joined().contains("private reasoning"))
}
@Test func failedAndInterruptedTurnsAreNotReplayed() throws {
    for state: MessageStatus in [.failed, .cancelled, .interrupted, .streaming] {
        let context = try ContextBuilder.build(history: turn(0, status: state), prompt: "Retry")
        #expect(context.messages == [.init(role: "user", content: "Retry")])
    }
}
@Test func contextKeepsRecentWholeTurns() throws {
    let history = turn(0, question: "old", answer: "old") + turn(2, question: "new", answer: "new")
    let result = try ContextBuilder.build(history: history, prompt: "X", characterBudget: 265)
    #expect(result.droppedTurns == 1)
    #expect(result.messages.map(\.content) == ["new", "new", "X"])
}
@Test func oversizedPromptIsNotSilentlyTruncated() {
    #expect(throws: ChatError.oversizedPrompt) { try ContextBuilder.build(history: [], prompt: String(repeating: "x", count: 600), characterBudget: 500) }
}
@Test func emptyAssistantIsNotReplayed() throws {
    #expect(try ContextBuilder.build(history: turn(0, answer: ""), prompt: "New").messages.count == 1)
}
@Test func ignoresUnansweredUserMessage() throws {
    let history = [ChatMessage(sequence: 0, role: .user, parts: [.text("Lost request")])]
    #expect(try ContextBuilder.build(history: history, prompt: "New").messages.count == 1)
}
@Test func preservesUnicodeInNativeStream() throws {
    let events = try OllamaFrame.events(from: #"{"message":{"content":"¡Hola! 🐱 café"},"done":false}"#)
    #expect(events == [.text("¡Hola! 🐱 café")])
}
@Test func reasoningAndContentStaySeparate() throws {
    let events = try OllamaFrame.events(from: #"{"message":{"content":"Answer","thinking":"Reason"},"done":false}"#)
    #expect(events == [.reasoning("Reason"), .text("Answer")])
}
@Test func completionIncludesUsage() throws {
    let events = try OllamaFrame.events(from: #"{"done":true,"done_reason":"length","prompt_eval_count":32,"eval_count":80}"#)
    #expect(events == [.finished(reason: "length", usage: .init(input: 32, output: 80))])
}
@Test func missingUsageIsUnknownNotZero() throws {
    let events = try OllamaFrame.events(from: #"{"done":true}"#)
    #expect(events == [.finished(reason: "stop", usage: .init(input: nil, output: nil))])
}
@Test func blankStreamLineIsIgnored() throws {
    #expect(try OllamaFrame.events(from: " \r\n").isEmpty)
}
@Test func malformedStreamFails() {
    #expect(throws: (any Error).self) { try OllamaFrame.events(from: "not JSON") }
}
@Test func providerErrorsDoNotEchoSecrets() throws {
    do {
        _ = try OllamaFrame.events(from: #"{"error":"secret-api-key-in-remote-body"}"#)
        Issue.record("Expected the frame to fail")
    } catch {
        #expect(!error.localizedDescription.contains("secret-api-key"))
    }
}
@Test func messageDeltasPreserveContent() throws {
    var message = ChatMessage(sequence: 0, role: .assistant)
    message.append(text: "Hi", reasoning: "Let me")
    message.append(text: " there", reasoning: " think")
    #expect(message.text == "Hi there")
    #expect(message.reasoning == "Let me think")
    #expect(message.parts.count == 2)
}
@Test func historyRoundTripPreservesModelAndParts() throws {
    let original = Conversation(title: "Unicode ✨", messages: turn(0))
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(Conversation.self, from: data) == original)
}
@Test func titleCollapsesWhitespaceWithoutBreakingUnicode() {
    #expect(Conversation.title(for: " Hello\n   there 🦋 ") == "Hello there 🦋")
    #expect(Conversation.title(for: String(repeating: "🦋", count: 100)).count == 65)
    #expect(Conversation.title(for: "\n\t ") == "New chat")
}
@Test func cleanModelTitleCleansPrefixesAndPunctuation() {
    #expect(Conversation.cleanModelTitle("Title: \"Chocolate Cake Recipe.\"") == "Chocolate Cake Recipe")
    #expect(Conversation.cleanModelTitle("**How to Build a Swift App**") == "How to Build a Swift App")
    #expect(Conversation.cleanModelTitle("Topic: Exploring Mars!") == "Exploring Mars")
    #expect(Conversation.cleanModelTitle("  \n  ") == "")
}
@Test func messageImagePartsEncodeAndDecode() throws {
    let raw = Data([0x89, 0x50, 0x4E, 0x47])
    let msg = ChatMessage(sequence: 0, role: .user, parts: [.text("Look"), .image(data: raw, mimeType: "image/png")])
    #expect(msg.images == [raw])
    let encoded = try JSONEncoder().encode(msg)
    let decoded = try JSONDecoder().decode(ChatMessage.self, from: encoded)
    #expect(decoded == msg)
    #expect(decoded.images == [raw])
}
@Test func modelCapabilitiesVisionDetection() {
    let openAI = ProviderConnection(kind: .openAI, name: "OpenAI", endpoint: "https://api.openai.com/v1", modelIDs: [], defaultModelID: "gpt-4o")
    #expect(ModelCapabilities.supportsVision(connection: openAI, modelID: "gpt-4o"))
    #expect(ModelCapabilities.supportsVision(connection: openAI, modelID: "chatgpt-4o-latest"))
    #expect(!ModelCapabilities.supportsVision(connection: openAI, modelID: "gpt-3.5-turbo"))

    let ollama = ProviderConnection(kind: .ollama, name: "Ollama", endpoint: "http://localhost:11434", modelIDs: [], defaultModelID: "llava:latest")
    #expect(ModelCapabilities.supportsVision(connection: ollama, modelID: "llava:latest"))
    #expect(ModelCapabilities.supportsVision(connection: ollama, modelID: "llama3.2-vision:latest"))
    #expect(!ModelCapabilities.supportsVision(connection: ollama, modelID: "llama3:latest"))
}
