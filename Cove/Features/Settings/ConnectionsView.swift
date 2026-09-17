import AppKit
import SwiftUI

struct ConnectionsView: View {
    let store: ChatStore
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("windowMaterial") private var windowMaterial = "translucent"
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @AppStorage("showInDock") private var showInDock = false
    @State private var sheet: ConnectionSheet?
    @State private var deleting: ProviderConnection?
    @State private var deleteConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings").font(.system(size: 20, weight: .medium))
                Spacer()
                ConnectMenu(onSelect: { sheet = .editor($0.newConnection()) },
                            onSubscriptions: { sheet = .subscriptions })
                    .disabled(store.isGenerating)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Connections").font(.system(size: 12, weight: .medium))
                Text("Your accounts and servers. Each connection keeps its own key and model list.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if store.connections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "network").font(.system(size: 25)).foregroundStyle(.tertiary)
                    Text("Connect your first provider").font(.system(size: 14))
                    Text("Choose an API service, a local server, or a custom endpoint from Connect.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).frame(height: 240)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.connections) { connection in
                            HStack(spacing: 12) {
                                Image(systemName: connection.provider.symbol)
                                    .foregroundStyle(.secondary).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(connection.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                    Text("\(connection.provider.title) · \(ProviderConnection.displayName(connection.defaultModelID))")
                                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    Text(connection.endpoint).font(.system(size: 10)).foregroundStyle(.tertiary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                                Spacer(minLength: 4)
                                Button { sheet = .editor(connection) } label: { Image(systemName: "slider.horizontal.3") }
                                    .buttonStyle(.plain).help("Edit \(connection.name)")
                                    .accessibilityLabel("Edit \(connection.name)")
                                Menu {
                                    Button("Use default model") { store.select(connection: connection, modelID: connection.defaultModelID) }
                                    Button("Delete…", role: .destructive) { deleting = connection; deleteConfirmation = true }
                                } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                            }
                            .padding(13)
                            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                            .disabled(store.isGenerating)
                        }
                    }
                }.frame(height: 255)
            }
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.secondary) }
            Divider()
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }.pickerStyle(.segmented)
            Picker("Window", selection: $windowMaterial) {
                Text("Translucent").tag("translucent"); Text("Plain").tag("plain")
            }.pickerStyle(.segmented)
            Text("Translucent blurs whatever is behind the window. Plain uses a solid background, which stays readable over busy wallpapers and video.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(alignment: .firstTextBaseline) {
                Text("Show or hide Cove").font(.system(size: 12))
                Spacer()
                ShortcutRecorder()
            }
            Toggle("Show icon in the menu bar", isOn: $showMenuBarIcon)
                .font(.system(size: 12))
                .disabled(!showInDock)
            Toggle("Show in the Dock", isOn: $showInDock)
                .font(.system(size: 12))
                .onChange(of: showInDock) { _, wantsDock in
                    NSApp.setActivationPolicy(wantsDock ? .regular : .accessory)
                    // Without a Dock icon the menu bar item is the only way back
                    // to the app, so it cannot be switched off as well.
                    if !wantsDock { showMenuBarIcon = true }
                    if wantsDock { NSApp.activate(ignoringOtherApps: true) }
                }
            Text(showInDock
                 ? "The shortcut works while any app is in front. Hiding the window keeps your draft and any answer still being written."
                 : "Cove lives in the menu bar only: no Dock icon and no entry in ⌘Tab. The menu bar item stays on so the app can always be reached.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Keys stay in Keychain; history stays on this Mac. Connecting does not send any conversation. Your first message to an external endpoint requires approval.")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 505)
        .sheet(item: $sheet) { route in
            switch route {
            case .editor(let connection): ConnectionEditorView(store: store, connection: connection, activateOnSave: false)
            case .subscriptions: SubscriptionInfoView()
            }
        }
        .alert("Delete this connection?", isPresented: $deleteConfirmation) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                guard let connection = deleting else { return }
                do { try store.removeConnection(connection.id); errorMessage = nil }
                catch { errorMessage = error.localizedDescription }
                deleting = nil
            }
        } message: { Text("Its credentials will be removed. Existing conversations will remain, and will not switch to another provider automatically.") }
    }
}
