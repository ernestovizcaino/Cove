import SwiftUI

struct ConnectionEditorView: View {
    let store: ChatStore
    let activateOnSave: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var editor: ConnectionEditorStore
    @State private var modelSearch = ""
    @State private var advanced = false
    @State private var discardConfirmation = false
    @State private var completedSave = false

    init(store: ChatStore, connection: ProviderConnection, activateOnSave: Bool) {
        self.store = store; self.activateOnSave = activateOnSave
        _editor = State(initialValue: ConnectionEditorStore(connection: connection,
            isNew: !store.connections.contains(where: { $0.id == connection.id }),
            readKey: { try store.key(for: $0) }))
    }
    private var provider: ProviderPreset { editor.connection.provider }
    private var alwaysShowEndpoint: Bool { provider.category == .local || provider.id == "custom" || provider.id == "cloudflare" }
    private var visibleModels: [String] {
        editor.connection.modelIDs.filter { modelSearch.isEmpty || $0.localizedCaseInsensitiveContains(modelSearch) }.sorted()
    }

    var body: some View {
        @Bindable var editor = editor
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: provider.symbol).font(.system(size: 20)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(editor.isNew ? "Connect \(provider.title)" : editor.connection.name)
                        .font(.system(size: 18, weight: .medium)).lineLimit(1)
                    Text(editor.isNew ? "Choose a name, endpoint and model." : "Edit connection · \(provider.title)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    field("Connection name") { TextField("Personal, Work, Windows PC…", text: $editor.connection.name) }
                    if alwaysShowEndpoint { endpointField }
                    if provider.kind != .ollama {
                        field(provider.id == "cloudflare" ? "Cloudflare API token" : (editor.connection.requiresKey ? "API key" : "API key (optional)")) {
                            SecureField(editor.isNew ? "Paste your key" : "Leave blank to keep this endpoint’s saved key", text: Binding(get: { editor.apiKey }, set: { editor.setAPIKey($0) }))
                        }
                        Text("Stored in macOS Keychain, never in chat history. A changed URL does not reuse a key saved for a different endpoint.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if provider.id == "cloudflare" {
                        field("Gateway ID") {
                            TextField("default", text: Binding(get: { editor.connection.gatewayID ?? "default" },
                                                              set: { editor.connection.gatewayID = $0 }))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Model ID").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            Spacer()
                            if provider.catalog == .discover {
                                if editor.isDiscovering {
                                    ProgressView().controlSize(.mini)
                                    Button("Cancel") { editor.cancelDiscovery() }.font(.caption)
                                } else {
                                    Button("Discover models") { editor.discoverModels() }
                                        .font(.caption).disabled(store.isGenerating)
                                }
                            }
                        }
                        TextField("Enter or discover a model", text: $editor.connection.defaultModelID)
                        if !editor.connection.modelIDs.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                TextField("Filter models…", text: $modelSearch).textFieldStyle(.plain)
                            }.font(.system(size: 11)).padding(7).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 2) {
                                    ForEach(visibleModels, id: \.self) { model in
                                        Button { editor.connection.defaultModelID = model } label: {
                                            HStack {
                                                Text(model).lineLimit(1).truncationMode(.middle)
                                                Spacer(minLength: 2)
                                                if editor.connection.defaultModelID == model { Image(systemName: "checkmark") }
                                            }
                                            .font(.system(size: 11)).foregroundStyle(.primary)
                                            .padding(.vertical, 6).padding(.horizontal, 7)
                                            .background(editor.connection.defaultModelID == model ? Color.primary.opacity(0.07) : .clear,
                                                        in: RoundedRectangle(cornerRadius: 5))
                                            .contentShape(Rectangle())
                                        }.buttonStyle(.plain).help(model)
                                    }
                                    if visibleModels.isEmpty { Text("No matches. You can still enter an ID above.").font(.caption).foregroundStyle(.secondary) }
                                }
                            }.frame(height: 105)
                        }
                    }
                    if let status = editor.status {
                        Label(status, systemImage: editor.statusIsError ? "exclamationmark.circle" : "info.circle")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    DisclosureGroup("Advanced", isExpanded: $advanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            if !alwaysShowEndpoint { endpointField }
                            Stepper("Output limit: \(editor.connection.maxOutputTokens) tokens",
                                    value: $editor.connection.maxOutputTokens, in: 512...16384, step: 512)
                                .font(.system(size: 12))
                        }.padding(.top, 9)
                    }.font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(provider.help).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: provider.documentationURL) {
                        Link("Provider documentation ↗", destination: url).font(.caption)
                    }
                }.padding(22).textFieldStyle(.roundedBorder)
            }
            Divider()
            HStack {
                Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(activateOnSave ? "Save and use" : "Save connection") { save() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(.gray)
                    .disabled(!editor.canSave || store.isGenerating || completedSave)
            }.padding(18)
        }
        .frame(width: 450, height: 550)
        .interactiveDismissDisabled(editor.isDirty || editor.isDiscovering)
        .onChange(of: editor.connection.gatewayID) { _, _ in editor.cancelDiscovery() }
        .onDisappear { editor.tearDown() }
        .alert("Discard these connection changes?", isPresented: $discardConfirmation) {
            Button("Keep editing", role: .cancel) {}
            Button("Discard", role: .destructive) { editor.tearDown(); dismiss() }
        } message: { Text("Your saved connections and conversations will not change.") }
    }
    private var endpointField: some View {
        return field(provider.kind == .ollama ? "Server URL" : "API base URL") {
            TextField(provider.endpoint.isEmpty ? "https://your-server.example/v1" : provider.endpoint, text: Binding(get: { editor.connection.endpoint }, set: { editor.setEndpoint($0); modelSearch = "" }))
        }
    }
    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content().font(.system(size: 12))
        }
    }
    private func cancel() {
        editor.cancelDiscovery()
        if editor.isDirty { discardConfirmation = true } else { dismiss() }
    }
    private func save() {
        do {
            if !editor.isNew {
                guard let current = store.connections.first(where: { $0.id == editor.original.id }), current == editor.original else {
                    throw ChatError.provider("This connection changed or was removed in another window. Close this form and reopen it before saving.")
                }
            }
            try store.saveConnection(editor.connection, newKey: editor.apiKey)
            if activateOnSave, let saved = store.connections.first(where: { $0.id == editor.connection.id }) {
                store.select(connection: saved, modelID: saved.defaultModelID)
            }
            completedSave = true
            editor.tearDown(); dismiss()
        } catch { editor.report(error) }
    }
}
