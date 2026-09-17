import AppKit
import SwiftUI

/// Keep the native window (resizing, shadow, keyboard commands), but remove the
/// conventional title bar. The custom header is the draggable region.
struct WindowConfigurator: NSViewRepresentable {
    var floating: Bool
    func makeNSView(context: Context) -> WindowProbe { WindowProbe() }
    func updateNSView(_ view: WindowProbe, context: Context) {
        view.floating = floating
        view.configure()
    }
    @MainActor final class WindowProbe: NSView {
        var floating = false
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            guard let window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            WindowPresenter.shared.window = window
            window.level = floating ? .floating : .normal
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
    }
}

/// Behind-window vibrancy for the whole canvas. The window is already
/// non-opaque with a clear background, so this only supplies the material;
/// the rounded clip in ChatRootView keeps the corners.
struct WindowBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = .active
    }
}

extension Color {
    static var chatCanvas: Color { Color(nsColor: .textBackgroundColor) }
}
