import SwiftUI

struct HistoryView: View {
    let store: ChatStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var renaming: UUID?
    @State private var name = ""
    @State private var showRename = false
    @State private var showDelete = false
    @State private var deleting: UUID?
    @State private var isNewHovered = false
    @State private var isCloseHovered = false

    private var filtered: [ConversationSummary] {
        store.summaries.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var sections: [HistorySection] {
        groupSummaries(filtered)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            searchBar

            if store.summaries.isEmpty {
                emptyHistoryView
            } else if filtered.isEmpty {
                emptySearchView
            } else {
                chatList
            }

            footerBar
        }
        .frame(width: 480, height: 500)
        .background(Color.chatCanvas)
        .alert("Rename chat", isPresented: $showRename) {
            TextField("Title", text: $name)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                if let id = renaming { store.rename(id, to: name) }
                renaming = nil
            }
        }
        .alert("Delete this chat?", isPresented: $showDelete) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let id = deleting { store.delete(id) }
                deleting = nil
            }
        } message: {
            Text("This removes the local conversation and its messages. It cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 7) {
                Text("All Chats")
                    .font(.system(size: 15, weight: .semibold))

                Text("\(store.summaries.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06), in: Capsule())
            }

            Spacer()

            Button {
                store.newChat()
                dismiss()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("New chat")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(.primary.opacity(isNewHovered ? 0.08 : 0.04), in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.primary.opacity(isNewHovered ? 0.12 : 0.06), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .onHover { isNewHovered = $0 }
            .keyboardShortcut("n", modifiers: .command)
            .help("New chat · ⌘N")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.primary.opacity(isCloseHovered ? 0.10 : 0.05), in: Circle())
            }
            .buttonStyle(.plain)
            .onHover { isCloseHovered = $0 }
            .keyboardShortcut(.cancelAction)
            .help("Close · Esc")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Search chats…", text: $query)
                .font(.system(size: 12.5))
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - Chat List

    private var chatList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.8))
                            .padding(.horizontal, 8)
                            .padding(.top, 4)

                        ForEach(section.items) { chat in
                            ChatHistoryRowView(
                                chat: chat,
                                isCurrent: store.selectedID == chat.id,
                                isGenerating: store.activeRun?.conversationID == chat.id,
                                onOpen: {
                                    store.open(chat.id)
                                    dismiss()
                                },
                                onRename: {
                                    renaming = chat.id
                                    name = chat.title
                                    showRename = true
                                },
                                onDelete: {
                                    deleting = chat.id
                                    showDelete = true
                                }
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Empty States

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text("No conversations yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))

            Text("Messages and topics will be organized here as you chat.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                store.newChat()
                dismiss()
            } label: {
                Text("Start a new chat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)

            Text("No matching chats")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))

            Text("No conversations match “\(query)”")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("Clear search") {
                query = ""
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.link)
            .padding(.top, 2)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Text(filtered.count == 1 ? "1 chat" : "\(filtered.count) chats")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            HStack(spacing: 8) {
                Text("↵ Open").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Text("⌘N New").font(.system(size: 10.5)).foregroundStyle(.tertiary)
                Text("Esc Close").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.primary.opacity(0.02))
        .overlay(Divider(), alignment: .top)
    }
}

// MARK: - Sections & Grouping

private struct HistorySection: Identifiable {
    let title: String
    let items: [ConversationSummary]
    var id: String { title }
}

private func groupSummaries(_ summaries: [ConversationSummary]) -> [HistorySection] {
    let calendar = Calendar.current
    let now = Date()

    var today: [ConversationSummary] = []
    var yesterday: [ConversationSummary] = []
    var prev7: [ConversationSummary] = []
    var prev30: [ConversationSummary] = []
    var older: [ConversationSummary] = []

    let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
    let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now

    for item in summaries {
        if calendar.isDateInToday(item.updatedAt) {
            today.append(item)
        } else if calendar.isDateInYesterday(item.updatedAt) {
            yesterday.append(item)
        } else if item.updatedAt >= sevenDaysAgo {
            prev7.append(item)
        } else if item.updatedAt >= thirtyDaysAgo {
            prev30.append(item)
        } else {
            older.append(item)
        }
    }

    var sections: [HistorySection] = []
    if !today.isEmpty { sections.append(HistorySection(title: "Today", items: today)) }
    if !yesterday.isEmpty { sections.append(HistorySection(title: "Yesterday", items: yesterday)) }
    if !prev7.isEmpty { sections.append(HistorySection(title: "Previous 7 Days", items: prev7)) }
    if !prev30.isEmpty { sections.append(HistorySection(title: "Previous 30 Days", items: prev30)) }
    if !older.isEmpty { sections.append(HistorySection(title: "Older", items: older)) }
    return sections
}

private func formatTimestamp(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return date.formatted(date: .omitted, time: .shortened)
    } else if calendar.isDateInYesterday(date) {
        return "Yesterday"
    } else {
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Row View

private struct ChatHistoryRowView: View {
    let chat: ConversationSummary
    let isCurrent: Bool
    let isGenerating: Bool
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Group {
                    if isGenerating {
                        ProgressView().controlSize(.mini)
                            .frame(width: 16, height: 16)
                    } else if isCurrent {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary.opacity(0.75))
                            .frame(width: 16, height: 16)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.title)
                        .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 6) {
                        Text(formatTimestamp(chat.updatedAt))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.8))

                        if isCurrent {
                            Text("Current")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                    }
                }

                Spacer(minLength: 8)

                if isHovered {
                    HStack(spacing: 4) {
                        Button {
                            onRename()
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Rename chat")

                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.red.opacity(0.85))
                                .frame(width: 22, height: 22)
                                .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)
                        .help("Delete chat")
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? .primary.opacity(0.06) : (isCurrent ? .primary.opacity(0.035) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Rename…") { onRename() }
            Button("Delete…", role: .destructive) { onDelete() }
                .disabled(isGenerating)
        }
    }
}
