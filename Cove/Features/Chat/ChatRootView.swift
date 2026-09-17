import AppKit
import SwiftUI

struct ChatRootView: View {
    @Bindable var store: ChatStore
    @AppStorage("keepOnTop") private var keepOnTop = false
    @AppStorage("windowMaterial") private var windowMaterial = "translucent"
    @AppStorage("didDismissOnboarding") private var didDismissOnboarding = false
    @State private var connectionSheet: ConnectionSheet?
    @State private var isTitleHovered = false

    private var showsOnboarding: Bool { store.connections.isEmpty && !didDismissOnboarding }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.current == nil || store.messages.isEmpty {
                HomeView(store: store, showsOnboarding: showsOnboarding,
                         onSelectProvider: { connectionSheet = .editor($0.newConnection()) },
                         onSubscriptions: { connectionSheet = .subscriptions },
                         onDismissOnboarding: { didDismissOnboarding = true })
            } else {
                TranscriptView(messages: store.messages, conversationID: store.selectedID)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = store.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if store.storageProblem { Button("Retry save") { store.retrySaving() }.font(.caption) }
                    else { Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                }
                .foregroundStyle(.secondary)
                .padding(10)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 14)
            }
            if let notice = store.contextNotice {
                Text(notice).font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.top, 5)
            }
            if store.isGenerating && !store.isGeneratingHere {
                Button { store.showGeneratingChat() } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("A response is running in another chat").font(.system(size: 11))
                        Image(systemName: "arrow.up.right").font(.system(size: 9))
                    }
                }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.top, 8)
            }
            ComposerView(store: store).padding(10)
        }
        .background {
            if windowMaterial == "translucent" {
                WindowBackdrop()
            } else {
                Color.chatCanvas
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowConfigurator(floating: keepOnTop))
        .sheet(isPresented: $store.showHistory) { HistoryView(store: store) }
        .sheet(item: $connectionSheet) { route in
            switch route {
            case .editor(let connection): ConnectionEditorView(store: store, connection: connection, activateOnSave: true)
            case .subscriptions: SubscriptionInfoView()
            }
        }
        .alert("Send to an external provider?", isPresented: $store.showRemoteConfirmation) {
            Button("Cancel", role: .cancel) { store.cancelRemoteSend() }
            Button("Allow this connection") { store.approveRemoteSend() }
        } message: { Text(store.consentDescription) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { store.showHistory = true } label: {
                HStack(spacing: 4) {
                    Text(store.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(.primary.opacity(isTitleHovered ? 1 : 0.85))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(isTitleHovered ? 0.9 : 0.55))
                        .offset(y: 0.5)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isTitleHovered = $0 }
            .help("All chats · ⌘K")
            .accessibilityLabel("All chats")

            Spacer(minLength: 8)

            // Pinning is a mode, so it stays visible only while it is on.
            if keepOnTop {
                Button { keepOnTop = false } label: {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11.5))
                        .frame(width: 22, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(.primary.opacity(0.8))
                .help("Unpin window")
            }

            Button { store.newChat() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12.5, weight: .regular))
                    .frame(width: 24, height: 28)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("New chat · ⌘N")

            Menu {
                Menu("Connect provider…") {
                    ProviderMenuItems(onSelect: { connectionSheet = .editor($0.newConnection()) },
                                      onSubscriptions: { connectionSheet = .subscriptions })
                }
                Button("All chats") { store.showHistory = true }
                SettingsLink { Text("Settings…") }
                Divider()
                Toggle("Keep window on top", isOn: $keepOnTop)
                Button("Minimize") { NSApp.keyWindow?.miniaturize(nil) }
                Divider()
                Button("Export Markdown…") { store.exportCurrent() }.disabled(store.current == nil)
                Button("Export JSON…") { store.exportCurrent(asJSON: true) }.disabled(store.current == nil)
                Divider()
                Button("Close window") { NSApp.keyWindow?.performClose(nil) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 20, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
            .help("More · window, connections, export")
        }
        .padding(.leading, 20).padding(.trailing, 15)
        .frame(height: 49)
    }
}

private struct HomeView: View {
    let store: ChatStore
    let showsOnboarding: Bool
    let onSelectProvider: (ProviderPreset) -> Void
    let onSubscriptions: () -> Void
    let onDismissOnboarding: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 36)
            if showsOnboarding {
                OnboardingCard(onSelect: onSelectProvider,
                               onSubscriptions: onSubscriptions,
                               onDismiss: onDismissOnboarding)
                    .padding(.bottom, 18)
            }
            Text("Recent chats")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            if store.summaries.isEmpty {
                Text("Your conversations will appear here.")
                    .font(.system(size: 13)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 17)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(store.summaries.prefix(3))) { chat in
                        HomeChatRow(chat: chat) {
                            store.open(chat.id)
                        }
                    }
                }
                Button {
                    store.showHistory = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See all chats")
                        Image(systemName: "arrow.right").font(.system(size: 9.5))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

private struct HomeChatRow: View {
    let chat: ConversationSummary
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button { onOpen() } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(chat.title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(relativeDate(chat.updatedAt))
                    .foregroundStyle(.tertiary)
                    .font(.system(size: 11.5))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1 : 0)
            }
            .foregroundStyle(.primary.opacity(isHovered ? 0.95 : 0.72))
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.primary.opacity(isHovered ? 0.045 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func relativeDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
