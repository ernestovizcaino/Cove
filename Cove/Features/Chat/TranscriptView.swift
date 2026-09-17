import SwiftUI

struct TranscriptView: View {
    let messages: [ChatMessage]
    let conversationID: UUID?
    @State private var followsBottom = true
    @State private var nearBottom = true
    @State private var userScrolling = false
    private var revision: String {
        let last = messages.last
        return "\(messages.count)-\(last?.text.count ?? 0)-\(last?.reasoning.count ?? 0)-\(last?.status.rawValue ?? "")"
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 23) {
                    ForEach(messages) { MessageView(message: $0).id($0.id) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 23).padding(.top, 14).padding(.bottom, 12)
                .frame(maxWidth: 780).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 75
            } action: { _, value in
                nearBottom = value
                if userScrolling { followsBottom = value }
            }
            .onScrollPhaseChange { _, phase in
                userScrolling = phase == .interacting || phase == .decelerating
                if phase == .idle { followsBottom = nearBottom }
            }
            .onChange(of: revision) { _, _ in
                if followsBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: conversationID) { _, _ in
                followsBottom = true; proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .overlay(alignment: .bottom) {
                if !followsBottom {
                    Button {
                        followsBottom = true
                        withAnimation(.easeOut(duration: 0.16)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down").font(.system(size: 12))
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.primary.opacity(0.08)))
                    }.buttonStyle(.plain).padding(.bottom, 6).help("Back to latest message")
                }
            }
        }
    }
}
