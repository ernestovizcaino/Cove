import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable final class ChatStore {
    struct Run: Equatable { var id: UUID; var conversationID: UUID; var messageID: UUID }
    struct PendingAttachment: Identifiable, Equatable {
        var id = UUID()
        var name: String
        var isImage: Bool
        var data: Data
        var mimeType: String
    }
    private struct SendPlan {
        var conversation: Conversation
        var text: String
        var userParts: [MessagePart]
        var request: GenerationRequest
        var droppedTurns: Int
    }

    var summaries: [ConversationSummary] = []
    var connections: [ProviderConnection] = []
    var selectedID: UUID?
    var activeRun: Run?
    var errorMessage: String?
    var contextNotice: String?
    var storageProblem = false
    var showHistory = false
    var showRemoteConfirmation = false
    var focusRequest = 0
    var pendingAttachment: PendingAttachment?
    var favoriteModelKeys: Set<String> = []

    private var loaded: [UUID: Conversation] = [:]
    private var newDraft = ""
    private var newConnectionID: UUID?
    private var newModelID = ""
    @ObservationIgnored private let repository: ChatRepository
    @ObservationIgnored private let credentials = KeychainStore()
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let generator: any GenerationClient
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var draftSaveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPlan: SendPlan?

    init(repository: ChatRepository, generator: any GenerationClient = RoutedGenerationClient(), preferences: UserDefaults = .standard) throws {
        self.repository = repository
        self.preferences = preferences
        self.generator = generator
        try repository.recoverInterrupted()
        // No connection is seeded: a fresh install has no provider until the
        // onboarding card or Settings saves a real one.
        connections = try repository.connections()
        summaries = try repository.summaries()
        if let saved = preferences.string(forKey: "defaultConnection"),
           let id = UUID(uuidString: saved), connections.contains(where: { $0.id == id }) {
            newConnectionID = id
        } else { newConnectionID = connections.first?.id }
        newModelID = connections.first(where: { $0.id == newConnectionID })?.defaultModelID ?? ""
        newDraft = preferences.string(forKey: "newChatDraft") ?? ""
        favoriteModelKeys = Set(preferences.stringArray(forKey: "favoriteModels") ?? [])
    }

    func isFavorite(connectionID: UUID, modelID: String) -> Bool {
        favoriteModelKeys.contains("\(connectionID.uuidString)/\(modelID)")
    }
    func toggleFavorite(connectionID: UUID, modelID: String) {
        let key = "\(connectionID.uuidString)/\(modelID)"
        if favoriteModelKeys.contains(key) {
            favoriteModelKeys.remove(key)
        } else {
            favoriteModelKeys.insert(key)
        }
        preferences.set(Array(favoriteModelKeys), forKey: "favoriteModels")
    }

    var current: Conversation? { selectedID.flatMap { loaded[$0] } }
    var messages: [ChatMessage] { current?.messages ?? [] }
    var title: String { current?.title ?? "New chat" }
    var isGenerating: Bool { activeRun != nil }
    var isGeneratingHere: Bool { activeRun?.conversationID == selectedID && activeRun != nil }
    var connection: ProviderConnection? {
        let id = current?.selectedConnectionID ?? (selectedID == nil ? newConnectionID : nil)
        return connections.first { $0.id == id }
    }
    var modelID: String { current?.selectedModelID ?? newModelID }
    var modelLabel: String { modelID.isEmpty ? "Choose model" : ProviderConnection.displayName(modelID) }
    var canAttach: Bool { connection != nil && !isGenerating }
    var modelSupportsVision: Bool { ModelCapabilities.supportsVision(connection: connection, modelID: modelID) }
    var canSend: Bool {
        !isGenerating && !storageProblem && connection != nil &&
        (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingAttachment != nil)
    }
    var draft: String {
        get { current?.draft ?? newDraft }
        set {
            if let id = selectedID, loaded[id] != nil { loaded[id]?.draft = newValue }
            else { newDraft = newValue }
            scheduleDraftSave()
        }
    }
    var consentDescription: String {
        guard let plan = pendingPlan else { return "" }
        let endpoint = plan.request.connection.endpoint
        return "The selected text history and your message will be sent to \(endpoint), using \(plan.request.modelID). Reasoning blocks are not forwarded. This approval applies to future chats using this connection and endpoint."
    }

    func select(connection: ProviderConnection, modelID: String) {
        if let id = selectedID {
            loaded[id]?.selectedConnectionID = connection.id
            loaded[id]?.selectedModelID = modelID
            persist(id)
        } else {
            newConnectionID = connection.id; newModelID = modelID
        }
        preferences.set(connection.id.uuidString, forKey: "defaultConnection")
        focusRequest += 1
    }

    func newChat() {
        saveDrafts()
        pendingAttachment = nil
        // Preserve an unsubmitted home-screen draft as a local conversation.
        if selectedID == nil, !newDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let saved = Conversation(title: Conversation.title(for: newDraft), selectedConnectionID: newConnectionID,
                                     selectedModelID: newModelID, draft: newDraft)
            do {
                try repository.save(saved)
                loaded[saved.id] = saved
                summaries = try repository.summaries()
            } catch { storageFailure(); return }
        }
        selectedID = nil; newDraft = ""
        preferences.set("", forKey: "newChatDraft")
        contextNotice = nil; errorMessage = nil; focusRequest += 1
    }

    func open(_ id: UUID) {
        saveDrafts()
        pendingAttachment = nil
        do {
            if loaded[id] == nil { loaded[id] = try repository.load(id) }
            guard loaded[id] != nil else { return }
            selectedID = id; showHistory = false
            contextNotice = nil; errorMessage = nil; focusRequest += 1
        } catch { storageFailure() }
    }

    func requestSend() {
        guard canSend, let connection else { return }
        do {
            try EndpointPolicy.validate(connection)
            var text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            var userParts: [MessagePart] = []
            var requestImages: [String] = []

            if let attachment = pendingAttachment {
                if attachment.isImage {
                    userParts.append(.image(data: attachment.data, mimeType: attachment.mimeType))
                    requestImages.append(attachment.data.base64EncodedString())
                    if text.isEmpty { text = "Describe this image." }
                } else if let contentString = String(data: attachment.data, encoding: .utf8) {
                    let snippet = "\n\n[Attached file: \(attachment.name)]\n```\n\(contentString)\n```"
                    text += snippet
                }
            }
            if !text.isEmpty {
                userParts.insert(.text(text), at: 0)
            }

            let conversation = current ?? Conversation(selectedConnectionID: connection.id, selectedModelID: modelID)
            let context = try ContextBuilder.build(history: conversation.messages, prompt: text, system: conversation.systemPrompt)
            var promptMessages = context.messages
            if !requestImages.isEmpty, let lastIndex = promptMessages.indices.last {
                promptMessages[lastIndex].images = requestImages
            }

            let plan = SendPlan(conversation: conversation, text: text, userParts: userParts,
                request: .init(id: UUID(), connection: connection, modelID: modelID, messages: promptMessages),
                droppedTurns: context.droppedTurns)
            pendingAttachment = nil
            let approved = Set(preferences.stringArray(forKey: "approvedEndpoints") ?? [])
            if !EndpointPolicy.isLocal(connection.endpoint), !approved.contains(try EndpointPolicy.consentKey(for: connection)) {
                pendingPlan = plan; showRemoteConfirmation = true
            } else { start(plan) }
        } catch { errorMessage = error.localizedDescription }
    }

    func approveRemoteSend() {
        guard let plan = pendingPlan else { return }
        do {
            var approved = Set(preferences.stringArray(forKey: "approvedEndpoints") ?? [])
            approved.insert(try EndpointPolicy.consentKey(for: plan.request.connection))
            preferences.set(Array(approved), forKey: "approvedEndpoints")
            pendingPlan = nil; showRemoteConfirmation = false
            start(plan)
        } catch { errorMessage = error.localizedDescription }
    }
    func cancelRemoteSend() { pendingPlan = nil; showRemoteConfirmation = false }

    private func start(_ plan: SendPlan) {
        guard !isGenerating else { return }
        do {
            let key = try credentials.read(plan.request.connection)
            if plan.request.connection.requiresKey && (key ?? "").isEmpty { throw ChatError.missingKey }
            var conversation = plan.conversation
            let next = (conversation.messages.map(\.sequence).max() ?? -1) + 1
            conversation.messages.append(.init(sequence: next, role: .user, parts: plan.userParts))
            let assistant = ChatMessage(sequence: next + 1, role: .assistant, status: .streaming,
                connectionID: plan.request.connection.id, providerName: plan.request.connection.name,
                modelID: plan.request.modelID, generationID: plan.request.id)
            conversation.messages.append(assistant)
            conversation.draft = ""; conversation.updatedAt = Date()
            if plan.conversation.messages.isEmpty { conversation.title = Conversation.title(for: plan.text) }
            // Never start a network request unless the user message was saved successfully.
            do { try repository.save(conversation) } catch { storageFailure(); return }
            loaded[conversation.id] = conversation; selectedID = conversation.id
            newDraft = ""; preferences.set("", forKey: "newChatDraft")
            summaries = try repository.summaries()
            errorMessage = nil
            contextNotice = plan.droppedTurns > 0 ? "Only the newest complete turns were sent. The full history is still saved locally." : nil
            let run = Run(id: plan.request.id, conversationID: conversation.id, messageID: assistant.id)
            activeRun = run
            pump(plan.request, key: key, run: run)
        } catch { errorMessage = error.localizedDescription }
    }

    private func pump(_ request: GenerationRequest, key: String?, run: Run) {
        let generator = generator
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            var text = ""; var reasoning = ""
            var lastFlush = Date.distantPast; var lastSave = Date()
            var finishReason: String?; var usage: TokenUsage?
            @MainActor func flush() {
                guard self.activeRun?.id == run.id else { return }
                self.mutateResponse(run) { $0.append(text: text, reasoning: reasoning) }
                text = ""; reasoning = ""; lastFlush = Date()
            }
            do {
                for try await event in generator.stream(request, apiKey: key) {
                    try Task.checkCancellation()
                    guard self.activeRun?.id == run.id else { return }
                    switch event {
                    case .text(let delta): text += delta
                    case .reasoning(let delta): reasoning += delta
                    case .finished(let reason, let count): finishReason = reason; usage = count
                    }
                    if Date().timeIntervalSince(lastFlush) >= 0.05 { flush() }
                    if Date().timeIntervalSince(lastSave) >= 1 {
                        flush(); self.persist(run.conversationID); lastSave = Date()
                    }
                }
                try Task.checkCancellation()
                flush()
                guard let finishReason else { throw ChatError.incompleteStream }
                self.mutateResponse(run) { message in
                    message.finishReason = finishReason; message.usage = usage
                    message.status = (finishReason == "error" || message.text.isEmpty) ? .failed : .completed
                    if message.text.isEmpty {
                        message.errorMessage = "No final text was returned. A reasoning model may need a higher output limit in Connections."
                    } else if finishReason == "error" {
                        message.errorMessage = "The provider reported an error. The partial answer was kept."
                    }
                }
            } catch {
                flush()
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                self.mutateResponse(run) {
                    $0.status = cancelled ? .cancelled : .failed
                    $0.errorMessage = cancelled ? nil : NetworkSession.readableError(error)
                }
            }
            guard self.activeRun?.id == run.id else { return }
            self.loaded[run.conversationID]?.updatedAt = Date()
            self.persist(run.conversationID)
            self.activeRun = nil; self.task = nil
            do { self.summaries = try self.repository.summaries() } catch { self.storageFailure() }

            if let conv = self.loaded[run.conversationID],
               conv.messages.filter({ $0.role == .user }).count == 1,
               let assistantMsg = conv.messages.first(where: { $0.id == run.messageID }),
               assistantMsg.status == .completed,
               let userMsg = conv.messages.first(where: { $0.role == .user }) {
                self.generateTitle(for: run.conversationID, request: request, key: key, prompt: userMsg.text, answer: assistantMsg.text)
            }
        }
    }

    private func generateTitle(for conversationID: UUID, request: GenerationRequest, key: String?, prompt: String, answer: String) {
        let titleRequest = GenerationRequest(
            id: UUID(),
            connection: request.connection,
            modelID: request.modelID,
            messages: [
                PromptMessage(role: "system", content: "You generate concise conversation titles. Return ONLY a 3 to 5 word title summarizing the user question and answer. Do not use quotes, punctuation, Markdown, or prefixes."),
                PromptMessage(role: "user", content: "Question: \(prompt.prefix(300))\nAnswer: \(answer.prefix(300))")
            ]
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var rawTitle = ""
                for try await event in self.generator.stream(titleRequest, apiKey: key) {
                    if case .text(let delta) = event { rawTitle += delta }
                }
                let cleaned = Conversation.cleanModelTitle(rawTitle)
                if !cleaned.isEmpty, var currentConv = self.loaded[conversationID] {
                    currentConv.title = cleaned
                    self.loaded[conversationID] = currentConv
                    self.persist(conversationID)
                    self.summaries = try self.repository.summaries()
                }
            } catch {
                // Silently retain fallback prompt title
            }
        }
    }

    func attachFileOrImage() {
        guard canAttach else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.resolvesAliases = true

        let imageTypes: [UTType] = [.png, .jpeg, .webP, .gif]
        let textTypes: [UTType] = [.plainText, .sourceCode, .json, .commaSeparatedText, .yaml, .xml, .html]
        panel.allowedContentTypes = modelSupportsVision ? (imageTypes + textTypes) : textTypes

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            self.handlePickedFile(url: url)
        }
    }

    private func handlePickedFile(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let ext = url.pathExtension.lowercased()
            let filename = url.lastPathComponent
            let isImage = ["png", "jpg", "jpeg", "webp", "gif"].contains(ext)

            if isImage && !modelSupportsVision {
                errorMessage = "The model '\(modelLabel)' does not support image input. Select a vision model (e.g. GPT-4o, Claude 3.5 Sonnet, Gemini, or LLaVA in Ollama) or attach a text/code file."
                return
            }

            let mimeType: String
            switch ext {
            case "png": mimeType = "image/png"
            case "jpg", "jpeg": mimeType = "image/jpeg"
            case "webp": mimeType = "image/webp"
            case "gif": mimeType = "image/gif"
            case "json": mimeType = "application/json"
            case "swift": mimeType = "text/x-swift"
            case "py": mimeType = "text/x-python"
            default: mimeType = "text/plain"
            }

            pendingAttachment = PendingAttachment(name: filename, isImage: isImage, data: data, mimeType: mimeType)
            errorMessage = nil
        } catch {
            errorMessage = "Could not read attached file: \(error.localizedDescription)"
        }
    }

    func removeAttachment() {
        pendingAttachment = nil
    }

    private func mutateResponse(_ run: Run, _ edit: (inout ChatMessage) -> Void) {
        guard var conversation = loaded[run.conversationID],
              let index = conversation.messages.firstIndex(where: { $0.id == run.messageID && $0.generationID == run.id }) else { return }
        edit(&conversation.messages[index])
        loaded[run.conversationID] = conversation
    }
    func stop() { task?.cancel() }
    func showGeneratingChat() { if let run = activeRun { open(run.conversationID) } }

    private func persist(_ id: UUID) {
        guard let value = loaded[id] else { return }
        do { try repository.save(value) } catch { storageFailure() }
    }
    private func storageFailure() {
        storageProblem = true
        errorMessage = "History could not be saved. Keep this window open and retry saving, or export your chat."
    }
    func retrySaving() {
        do {
            for value in loaded.values { try repository.save(value) }
            summaries = try repository.summaries()
            storageProblem = false; errorMessage = nil
        } catch { storageFailure() }
    }
    private func scheduleDraftSave() {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.saveDrafts()
        }
    }
    func saveDrafts() {
        preferences.set(newDraft, forKey: "newChatDraft")
        for id in loaded.keys { persist(id) }
    }
    func prepareToQuit() {
        draftSaveTask?.cancel(); task?.cancel()
        if let run = activeRun { mutateResponse(run) { $0.status = .interrupted } }
        saveDrafts()
    }
    func rename(_ id: UUID, to title: String) {
        do {
            guard var value = try loaded[id] ?? repository.load(id) else { return }
            let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }
            value.title = String(clean.prefix(150))
            try repository.save(value); loaded[id] = value
            summaries = try repository.summaries()
        } catch { storageFailure() }
    }
    func delete(_ id: UUID) {
        guard activeRun?.conversationID != id else { return }
        do {
            try repository.delete(id); loaded[id] = nil
            if selectedID == id { selectedID = nil }
            summaries = try repository.summaries()
        } catch { storageFailure() }
    }
    func saveConnection(_ connection: ProviderConnection, newKey: String) throws {
        var value = connection
        value.endpoint = try EndpointPolicy.baseURL(value.endpoint).absoluteString
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.defaultModelID = value.defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { throw ChatError.provider("Give the connection a name.") }
        try EndpointPolicy.validate(value)
        value.modelIDs = value.availableModels
        let cleanKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.requiresKey && cleanKey.isEmpty {
            let existingKey = try credentials.read(value)
            if (existingKey ?? "").isEmpty { throw ChatError.missingKey }
        }
        if !cleanKey.isEmpty { try credentials.save(cleanKey, for: value) }
        try repository.saveConnection(value)
        connections = try repository.connections()
        if newConnectionID == nil { newConnectionID = value.id; newModelID = value.defaultModelID }
    }
    func removeConnection(_ id: UUID) throws {
        guard !isGenerating else { return }
        try credentials.deleteAll(for: id)
        try repository.deleteConnection(id)
        connections = try repository.connections()
        // Deliberately do not switch an affected chat to a different provider.
    }
    func key(for connection: ProviderConnection) throws -> String? { try credentials.read(connection) }
    func exportCurrent(asJSON: Bool = false) {
        guard let current else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = asJSON ? [.json] : [.plainText]
        panel.canCreateDirectories = true
        let name = current.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(name).\(asJSON ? "json" : "md")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            if asJSON {
                struct Export: Encodable { var schemaVersion = 1; var conversation: Conversation }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                data = try encoder.encode(Export(conversation: current))
            } else {
                var markdown = "# \(current.title)\n\n"
                for message in current.messages {
                    markdown += "## \(message.role == .user ? "You" : (message.modelID ?? "Assistant"))\n\n"
                    if message.status != .completed { markdown += "*Status: \(message.status.rawValue)*\n\n" }
                    markdown += message.text + "\n\n"
                }
                data = Data(markdown.utf8)
            }
            try data.write(to: url, options: .atomic)
        } catch { errorMessage = "The export could not be saved. Try another location." }
    }
}
