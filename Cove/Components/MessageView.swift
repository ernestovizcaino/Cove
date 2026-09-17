import AppKit
import SwiftUI
import Textual

struct MessageView: View {
    let message: ChatMessage
    @State private var hovered = false
    @State private var reasoningExpanded = false
    @State private var isCopied = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            if message.role == .user {
                HStack {
                    Spacer(minLength: 48)
                    VStack(alignment: .trailing, spacing: 6) {
                        ForEach(Array(message.images.enumerated()), id: \.offset) { _, imageData in
                            if let nsImage = NSImage(data: imageData) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxWidth: 220, maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        if !message.text.isEmpty {
                            Text(message.text).font(.system(size: 14)).textSelection(.enabled)
                                .padding(.horizontal, 13).padding(.vertical, 9)
                                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            } else {
                if !message.reasoning.isEmpty {
                    DisclosureGroup(isExpanded: $reasoningExpanded) {
                        Text(message.reasoning).font(.system(size: 12)).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(.top, 4)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "brain")
                                .font(.system(size: 11))
                            Text(message.status == .streaming ? "Thinking…" : "Reasoning")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }.tint(.secondary)
                }
                if message.text.isEmpty && message.status == .streaming {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.mini)
                        Text(message.reasoning.isEmpty ? "Connecting…" : "Thinking…")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                } else if message.status == .streaming {
                    // Avoid reparsing an unfinished Markdown document for every stream batch.
                    Text(message.text).font(.system(size: 14)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    StructuredText(markdown: message.text)
                        .font(.system(size: 14))
                        .textual.imageAttachmentLoader(NoRemoteAttachments())
                        .textual.emojiAttachmentLoader(NoRemoteAttachments())
                        .environment(\.openURL, OpenURLAction { url in
                            guard ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") else { return .discarded }
                            return .systemAction
                        })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error = message.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else if message.status == .cancelled || message.status == .interrupted {
                    Text(message.status == .cancelled ? "Stopped" : "Interrupted when the app closed")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                } else if message.finishReason == "length" {
                    Text("Output limit reached. Increase it in Connections for longer answers.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Text(message.modelID.map(ProviderConnection.displayName) ?? "Assistant")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.text, forType: .string)
                        isCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.5))
                            isCopied = false
                        }
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(isCopied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(isCopied ? "Copied!" : "Copy response")
                    .accessibilityLabel("Copy response")
                    .opacity(hovered || isCopied ? 1 : 0.3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        .onHover { hovered = $0 }
    }
}

private struct NoRemoteAttachments: AttachmentLoader {
    func attachment(for url: URL, text: String, environment: ColorEnvironmentValues) async throws -> AnyAttachment {
        throw URLError(.resourceUnavailable)
    }
}
