import AppKit
import SwiftUI

/// A native NSTextView: Return sends, Shift/Option-Return inserts a newline,
/// and Return never sends while an input method is composing marked text.
struct NativeComposer: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var focusRequest: Int
    var onSend: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        let editor = Editor(frame: .zero)
        editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 14); editor.textColor = .labelColor
        editor.insertionPointColor = .labelColor
        editor.isEditable = true; editor.isSelectable = true
        editor.isVerticallyResizable = true; editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainerInset = NSSize(width: 0, height: 6)
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.delegate = context.coordinator
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        context.coordinator.parent = self
        editor.onSend = onSend
        if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            editor.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
        context.coordinator.measure(editor)
        if context.coordinator.lastFocus != focusRequest {
            context.coordinator.lastFocus = focusRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window?.isKeyWindow == true else { return }
                editor.window?.makeFirstResponder(editor)
            }
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeComposer
        var lastFocus: Int?
        init(_ parent: NativeComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? Editor else { return }
            parent.text = editor.string
            measure(editor)
        }
        func measure(_ editor: NSTextView) {
            guard let manager = editor.layoutManager, let container = editor.textContainer else { return }
            manager.ensureLayout(for: container)
            let measured = min(130, max(30, ceil(manager.usedRect(for: container).height) + 12))
            if abs(parent.height - measured) > 0.5 {
                DispatchQueue.main.async { [weak self] in self?.parent.height = measured }
            }
        }
    }
    @MainActor final class Editor: NSTextView {
        var onSend: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            let newline = event.keyCode == 36 || event.keyCode == 76
            let multiline = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option)
            if newline && !multiline && !hasMarkedText() { onSend?(); return }
            super.keyDown(with: event)
        }
    }
}
