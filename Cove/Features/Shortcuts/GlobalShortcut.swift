import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A user-chosen global hotkey, kept in the form the Carbon hotkey API needs plus
/// the symbols to show in the UI. Carbon's `RegisterEventHotKey` is used instead of
/// a global event monitor because it needs no Accessibility permission and works
/// inside the App Sandbox.
struct KeyCombo: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let fallback = KeyCombo(keyCode: UInt32(kVK_ANSI_C),
                                   modifiers: UInt32(cmdKey | shiftKey),
                                   display: "⇧⌘C")

    /// Keys whose `charactersIgnoringModifiers` is a control character or blank.
    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_Escape: "⎋", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ForwardDelete: "⌦",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12"
    ]

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    /// Returns nil for a combination that must not become a global hotkey: without
    /// a modifier the key would be swallowed in every other app.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        var label = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); label += "⌘" }
        guard carbon != 0 else { return nil }

        let code = Int(event.keyCode)
        let name: String
        if let named = Self.namedKeys[code] {
            name = named
        } else if let characters = event.charactersIgnoringModifiers?.uppercased(),
                  let first = characters.first, first.isLetter || first.isNumber || first.isPunctuation {
            name = String(first)
        } else {
            return nil
        }
        self.keyCode = UInt32(event.keyCode)
        self.modifiers = carbon
        self.display = label + name
    }
}

/// Owns the single registered hotkey. Re-registering replaces the previous one, so
/// a rejected combination never leaves two hotkeys live.
@MainActor final class HotKeyCenter {
    static let shared = HotKeyCenter()

    /// Set by the app scene; the C callback cannot capture context.
    static var onFire: (@MainActor () -> Void)?

    private(set) var combo: KeyCombo = .fallback
    private(set) var failureMessage: String?

    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let storageKey = "windowShortcut"

    private init() {}

    var storedCombo: KeyCombo {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(KeyCombo.self, from: data) else { return .fallback }
        return decoded
    }

    func start() {
        installHandlerIfNeeded()
        apply(storedCombo, persist: false)
    }

    /// - Returns: true when the system accepted the combination. A false result
    ///   means another application already owns it; the previous hotkey is restored.
    @discardableResult
    func apply(_ combo: KeyCombo, persist: Bool = true) -> Bool {
        let previous = self.combo
        unregister()

        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x434F_5645), id: 1)  // 'COVE'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, identifier,
                                         GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else {
            failureMessage = "\(combo.display) is already used by another app. Pick a different one."
            if previous != combo { _ = apply(previous, persist: false) }
            return false
        }
        hotKey = reference
        self.combo = combo
        failureMessage = nil
        if persist, let data = try? JSONEncoder().encode(combo) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        return true
    }

    func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        _ = apply(.fallback, persist: false)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            Task { @MainActor in HotKeyCenter.onFire?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

/// Shows and hides the single chat window without closing it, so drafts, scroll
/// position and an in-flight generation survive a hide.
@MainActor final class WindowPresenter {
    static let shared = WindowPresenter()
    weak var window: NSWindow?
    /// Asks SwiftUI to re-create the scene when the window was closed outright.
    var reopen: (() -> Void)?
    var onShow: (() -> Void)?

    private init() {}

    var isShowing: Bool { window?.isVisible == true }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
        } else {
            reopen?()
        }
        onShow?()
    }

    func hide() {
        window?.orderOut(nil)
    }

    /// Hides only when the window is both visible and in front; otherwise a hotkey
    /// press while another app is focused would hide the window instead of raising it.
    func toggle() {
        if isShowing && NSApp.isActive {
            hide()
        } else {
            show()
        }
    }
}
