import AppKit
import SwiftUI

/// Click, then press the combination. Escape cancels, Delete restores the default.
/// A key without a modifier is rejected rather than registered, because a global
/// hotkey with no modifier would swallow that key in every other application.
struct ShortcutRecorder: View {
    @State private var isRecording = false
    @State private var display: String = HotKeyCenter.shared.combo.display
    @State private var message: String?
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button { isRecording.toggle() } label: {
                    Text(isRecording ? "Press keys…" : display)
                        .font(.system(size: 12, weight: .medium, design: isRecording ? .default : .rounded))
                        .foregroundStyle(isRecording ? AnyShapeStyle(.secondary)
                                                    : AnyShapeStyle(.primary.opacity(0.9)))
                        .frame(minWidth: 96)
                        .frame(height: 24)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(.primary.opacity(isRecording ? 0.10 : (isHovered ? 0.08 : 0.05)))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(isRecording ? Color.accentColor.opacity(0.9)
                                                          : .primary.opacity(0.12),
                                              lineWidth: isRecording ? 1.5 : 0.5)
                        )
                }
                .buttonStyle(.plain)
                .onHover { isHovered = $0 }
                .background(KeyCaptureView(isRecording: $isRecording, onCapture: capture))

                Button("Reset") {
                    HotKeyCenter.shared.resetToDefault()
                    display = HotKeyCenter.shared.combo.display
                    message = nil
                    isRecording = false
                }
                .font(.system(size: 11))
                .disabled(isRecording)
            }
            if let message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 {  // Escape
            isRecording = false
            message = nil
            return
        }
        guard let combo = KeyCombo(event: event) else {
            message = "Add ⌘, ⌥, ⌃ or ⇧ — a global shortcut needs at least one modifier."
            return
        }
        if HotKeyCenter.shared.apply(combo) {
            display = combo.display
            message = nil
        } else {
            message = HotKeyCenter.shared.failureMessage
            display = HotKeyCenter.shared.combo.display
        }
        isRecording = false
    }
}

/// An NSView is the only reliable way to see ⌘-combinations before the menu bar
/// consumes them, which `performKeyEquivalent` allows and SwiftUI's key handling
/// does not.
private struct KeyCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (NSEvent) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onCapture = onCapture
        view.isRecording = isRecording
        if isRecording, view.window?.firstResponder !== view {
            view.window?.makeFirstResponder(view)
        }
    }

    final class CaptureView: NSView {
        var onCapture: ((NSEvent) -> Void)?
        var isRecording = false

        override var acceptsFirstResponder: Bool { isRecording }

        override func keyDown(with event: NSEvent) {
            guard isRecording else { return super.keyDown(with: event) }
            onCapture?(event)
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard isRecording else { return false }
            onCapture?(event)
            return true
        }
    }
}
