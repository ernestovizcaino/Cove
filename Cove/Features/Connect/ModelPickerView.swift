import SwiftUI

struct ModelPickerButton: View {
    let store: ChatStore
    @State private var isPresented = false
    @State private var isHovered = false

    private var isCurrentFavorite: Bool {
        guard let connection = store.connection else { return false }
        return store.isFavorite(connectionID: connection.id, modelID: store.modelID)
    }

    private var providerSymbol: String {
        store.connection?.provider.symbol ?? "sparkles"
    }

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 5) {
                if isCurrentFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: providerSymbol)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary.opacity(0.8))
                }

                Text(store.connection == nil ? "Choose model" : store.modelLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(isHovered ? 0.95 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .offset(y: 0.5)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(.primary.opacity(isHovered ? 0.08 : 0.04))
            )
            .overlay(
                Capsule()
                    .strokeBorder(.primary.opacity(isHovered ? 0.14 : 0.07), lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(height: 28)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Choose connection and model")
        .help("\(store.connection?.name ?? "Connect a provider") · \(store.modelID)")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            ModelPickerView(store: store) { choice in
                store.select(connection: choice.connection, modelID: choice.modelID)
                isPresented = false
            }
        }
    }
}

private struct ModelPickerView: View {
    struct Item: Identifiable {
        let id: String
        let choice: ModelChoice
        let isFavoriteSection: Bool
    }

    let store: ChatStore
    let onSelect: (ModelChoice) -> Void
    @State private var query = ""
    @State private var highlighted: String?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case search, list }

    private var choices: [ModelChoice] {
        ModelChoice.matching(query, connections: store.connections,
                             selectedConnectionID: store.connection?.id, selectedModelID: store.modelID)
    }
    private var favoriteChoices: [ModelChoice] {
        choices.filter { store.isFavorite(connectionID: $0.connection.id, modelID: $0.modelID) }
    }
    private var groups: [ProviderConnection] {
        let ids = Set(choices.map { $0.connection.id })
        return store.connections.filter { ids.contains($0.id) }
    }

    private var favoriteItems: [Item] {
        favoriteChoices.map {
            Item(id: "fav:\($0.connection.id.uuidString):\($0.modelID)", choice: $0, isFavoriteSection: true)
        }
    }

    private func providerItems(for connection: ProviderConnection) -> [Item] {
        choices.filter { $0.connection.id == connection.id }.map {
            Item(id: "prov:\($0.connection.id.uuidString):\($0.modelID)", choice: $0, isFavoriteSection: false)
        }
    }

    private var allItems: [Item] {
        var result: [Item] = []
        if !favoriteItems.isEmpty {
            result.append(contentsOf: favoriteItems)
        }
        for connection in groups {
            result.append(contentsOf: providerItems(for: connection))
        }
        return result
    }

    private var footerCountText: String {
        let total = choices.count
        let favs = favoriteChoices.count
        if favs > 0 {
            return "\(favs) favorite\(favs == 1 ? "" : "s") · \(total) model\(total == 1 ? "" : "s")"
        } else {
            return "\(total) model\(total == 1 ? "" : "s") available"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                TextField("Search connections or models…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focus, equals: .search)
                    .onSubmit { selectHighlighted() }
                    .onKeyPress(.downArrow) {
                        highlighted = allItems.first?.id
                        focus = .list
                        return .handled
                    }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear model search")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if choices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(.tertiary)
                    Text(store.connections.isEmpty ? "No connected providers" : "No matching models")
                        .font(.system(size: 13, weight: .medium))
                    Text(store.connections.isEmpty ? "Connect a provider from the menu (⋯) or Settings." : "Try another search, or add a model in Settings.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
            } else {
                List(selection: $highlighted) {
                    if !favoriteItems.isEmpty {
                        Section {
                            ForEach(favoriteItems) { item in
                                ModelRowView(
                                    item: item,
                                    isSelected: store.connection?.id == item.choice.connection.id && store.modelID == item.choice.modelID,
                                    isFavorite: true,
                                    onSelect: { onSelect(item.choice) },
                                    onToggleFavorite: { store.toggleFavorite(connectionID: item.choice.connection.id, modelID: item.choice.modelID) }
                                )
                            }
                        } header: {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.yellow)
                                Text("Favorites")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(groups) { connection in
                        let items = providerItems(for: connection)
                        if !items.isEmpty {
                            Section {
                                ForEach(items) { item in
                                    ModelRowView(
                                        item: item,
                                        isSelected: store.connection?.id == item.choice.connection.id && store.modelID == item.choice.modelID,
                                        isFavorite: store.isFavorite(connectionID: item.choice.connection.id, modelID: item.choice.modelID),
                                        onSelect: { onSelect(item.choice) },
                                        onToggleFavorite: { store.toggleFavorite(connectionID: item.choice.connection.id, modelID: item.choice.modelID) }
                                    )
                                }
                            } header: {
                                Label(connection.name, systemImage: connection.provider.symbol)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .focused($focus, equals: .list)
                .onKeyPress(.return) { selectHighlighted(); return .handled }
            }

            Divider()

            HStack {
                Text(footerCountText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Spacer()
                SettingsLink {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                        Text("Settings")
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("Open Connections Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 345, height: 410)
        .onAppear {
            if let connection = store.connection {
                if store.isFavorite(connectionID: connection.id, modelID: store.modelID) {
                    highlighted = "fav:\(connection.id.uuidString):\(store.modelID)"
                } else {
                    highlighted = "prov:\(connection.id.uuidString):\(store.modelID)"
                }
            } else {
                highlighted = allItems.first?.id
            }
            focus = .search
        }
        .onChange(of: query) { _, _ in highlighted = allItems.first?.id }
    }

    private func selectHighlighted() {
        if let highlighted, let item = allItems.first(where: { $0.id == highlighted }) {
            onSelect(item.choice)
            return
        }
        if let first = allItems.first {
            onSelect(first.choice)
        }
    }
}

private struct ModelRowView: View {
    let item: ModelPickerView.Item
    let isSelected: Bool
    let isFavorite: Bool
    let onSelect: () -> Void
    let onToggleFavorite: () -> Void
    @State private var isHovered = false

    var body: some View {
        let choice = item.choice

        HStack(spacing: 6) {
            Button {
                onSelect()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProviderConnection.displayName(choice.modelID))
                            .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                            .foregroundStyle(Color.primary.opacity(isSelected ? 1.0 : 0.88))
                            .lineLimit(1)
                        if item.isFavoriteSection {
                            HStack(spacing: 4) {
                                Text(choice.connection.name)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
                                if choice.modelID.contains("/") {
                                    Text(choice.modelID)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        } else if choice.modelID.contains("/") {
                            Text(choice.modelID)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tint)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                onToggleFavorite()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isFavorite ? Color.yellow : Color.secondary.opacity(isHovered ? 0.65 : 0.2))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "Remove from favorites" : "Mark as favorite")
            .help(isFavorite ? "Remove from favorites" : "Mark as favorite")
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(isHovered ? 0.04 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .tag(item.id)
        .accessibilityLabel("\(choice.connection.name), \(choice.modelID)")
        .help(choice.modelID)
        .contextMenu {
            Button {
                onToggleFavorite()
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Mark as Favorite",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
        }
    }
}

