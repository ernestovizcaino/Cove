import SwiftUI

/// A real macOS menu, not a hand-drawn menu or an embedded webpage.
/// Selection closes the menu before its owner presents the editor sheet.
struct ProviderMenuItems: View {
    let onSelect: (ProviderPreset) -> Void
    let onSubscriptions: () -> Void

    var body: some View {
        ForEach(ProviderCategory.allCases) { category in
            Section(category.rawValue) {
                ForEach(ProviderCatalog.presets(in: category)) { preset in
                    Button { onSelect(preset) } label: {
                        Label(preset.title, systemImage: preset.symbol)
                    }
                }
            }
        }
        Divider()
        Button { onSelect(ProviderCatalog.custom) } label: {
            Label("Add custom provider…", systemImage: "plus")
        }
        Button("About subscriptions…", action: onSubscriptions)
    }
}

struct ConnectMenu: View {
    let onSelect: (ProviderPreset) -> Void
    let onSubscriptions: () -> Void
    var body: some View {
        Menu {
            ProviderMenuItems(onSelect: onSelect, onSubscriptions: onSubscriptions)
        } label: {
            Label("Connect", systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Connect a provider")
    }
}

/// One sheet route prevents simultaneously presenting two sheets at the same anchor.
enum ConnectionSheet: Identifiable {
    case editor(ProviderConnection)
    case subscriptions
    var id: String {
        switch self {
        case .editor(let connection): "connection-\(connection.id.uuidString)"
        case .subscriptions: "subscriptions"
        }
    }
}

struct SubscriptionInfoView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Subscriptions are a different connection")
                .font(.system(size: 19, weight: .medium))
            Text("Cove currently connects API keys and local servers. It does not collect website cookies or subscription session tokens.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 15) {
                info("ChatGPT", detail: "ChatGPT subscriptions do not include general API usage. The OpenAI connection here uses an API key with separate billing.",
                     url: "https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus")
                info("Claude", detail: "This connection uses Claude API keys. Subscription sign-in must use Anthropic's own flow. An integration with unmodified Claude Code would be a separate feature, not a key for this connection.",
                     url: "https://code.claude.com/docs/en/legal-and-compliance")
                info("GitHub Copilot", detail: "An official SDK exists, using the Copilot CLI runtime and its authentication. That is a separate integration and is not implemented in this version.",
                     url: "https://docs.github.com/en/copilot/get-started/sdk-quickstart")
            }
            Text("Other sign-in methods will appear only after their official flow and runtime have actually been integrated and tested.")
                .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .font(.system(size: 12))
        .padding(24).frame(width: 430)
    }
    private func info(_ title: String, detail: String, url: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).fontWeight(.medium)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: url) { Link("Official documentation ↗", destination: url).font(.caption) }
        }
    }
}
