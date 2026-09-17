import SwiftUI

/// First-run guidance for a fresh install, shown only while no connection exists.
///
/// Deliberately not a funnel: one compact card on the home screen that hands off
/// to the existing ConnectionEditorView instead of introducing a second form, and
/// disappears by itself once a connection is saved.
struct OnboardingCard: View {
    let onSelect: (ProviderPreset) -> Void
    let onSubscriptions: () -> Void
    let onDismiss: () -> Void
    @State private var isDismissHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect a model to start")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.9))
                    Text("Chats stay on this Mac. Point the app at a local server, or use an API key you already have.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(isDismissHovered ? 1 : 0.6))
                        .frame(width: 20, height: 20)
                        .background(.primary.opacity(isDismissHovered ? 0.08 : 0), in: Circle())
                }
                .buttonStyle(.plain)
                .onHover { isDismissHovered = $0 }
                .help("Hide this. Connect later from the ⋯ menu or Settings.")
                .accessibilityLabel("Hide setup card")
            }

            HStack(spacing: 6) {
                presetMenu("Local server", symbol: "desktopcomputer", category: .local)
                presetMenu("API key", symbol: "key", category: .api)
                CardButton(title: "Custom…", symbol: "slider.horizontal.3") {
                    onSelect(ProviderCatalog.custom)
                }
                Spacer(minLength: 0)
            }

            Text("Return sends · ⇧Return adds a line · ⌘N new chat · ⌘K all chats")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            Button("Why a subscription is not an API key", action: onSubscriptions)
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func presetMenu(_ title: String, symbol: String, category: ProviderCategory) -> some View {
        Menu {
            ForEach(ProviderCatalog.presets(in: category)) { preset in
                Button { onSelect(preset) } label: {
                    Label(preset.title, systemImage: preset.symbol)
                }
            }
        } label: {
            CardLabel(title: title, symbol: symbol, showsChevron: true)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

private struct CardButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            CardLabel(title: title, symbol: symbol, showsChevron: false)
        }
        .buttonStyle(.plain)
    }
}

private struct CardLabel: View {
    let title: String
    let symbol: String
    let showsChevron: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.primary.opacity(isHovered ? 0.95 : 0.78))
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .offset(y: 0.5)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(.primary.opacity(isHovered ? 0.09 : 0.05)))
        .overlay(Capsule().strokeBorder(.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.5))
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
    }
}
