import AppKit
import SwiftUI

@MainActor final class AppRuntime {
    let store: ChatStore?
    let startupError: String?
    init() {
        do {
            store = try ChatStore(repository: ChatRepository())
            startupError = nil
        } catch {
            store = nil
            startupError = "The local history could not be opened. No data was deleted.\n\n\(error.localizedDescription)"
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: ChatStore?
    func applicationWillTerminate(_ notification: Notification) { store?.prepareToQuit() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Info.plist marks the app as an agent, so the default is menu bar only.
        let wantsDock = UserDefaults.standard.bool(forKey: "showInDock")
        NSApp.setActivationPolicy(wantsDock ? .regular : .accessory)
        NSApp.activate(ignoringOtherApps: true)
        HotKeyCenter.onFire = { WindowPresenter.shared.toggle() }
        HotKeyCenter.shared.start()
    }

    /// Clicking the Dock icon after the window was hidden brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { WindowPresenter.shared.show() }
        return true
    }
}

@main @MainActor struct CoveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var runtime = AppRuntime()
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @Environment(\.openWindow) private var openWindow
    private var scheme: ColorScheme? { appearance == "light" ? .light : (appearance == "dark" ? .dark : nil) }

    var body: some Scene {
        Window("Cove", id: "main") {
            Group {
                if let store = runtime.store {
                    ChatRootView(store: store)
                        .onAppear {
                            delegate.store = store
                            WindowPresenter.shared.onShow = { store.focusRequest += 1 }
                        }
                } else {
                    ContentUnavailableView {
                        Label("History unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(runtime.startupError ?? "Unable to open local history.")
                    } actions: {
                        Button("Quit") { NSApp.terminate(nil) }
                    }
                    .padding(30)
                }
            }
            .preferredColorScheme(scheme)
            .frame(minWidth: 400, minHeight: 420)
        }
        .defaultSize(width: 540, height: 640)
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { runtime.store?.newChat() }.keyboardShortcut("n")
                Button("All Chats") { runtime.store?.showHistory = true }.keyboardShortcut("k")
            }
            CommandMenu("Chat") {
                Button("Stop Generating") { runtime.store?.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(runtime.store?.isGenerating != true)
                Divider()
                Button("Export as Markdown…") { runtime.store?.exportCurrent() }
                    .disabled(runtime.store?.current == nil)
                Button("Export as JSON…") { runtime.store?.exportCurrent(asJSON: true) }
                    .disabled(runtime.store?.current == nil)
            }
        }
        Settings {
            if let store = runtime.store {
                ConnectionsView(store: store).preferredColorScheme(scheme)
            }
        }
        MenuBarExtra("Cove", systemImage: "bubble.left", isInserted: $showMenuBarIcon) {
            Button(WindowPresenter.shared.isShowing ? "Hide Cove" : "Open Cove") {
                WindowPresenter.shared.toggle()
            }
            Divider()
            Button("New Chat") {
                WindowPresenter.shared.show()
                runtime.store?.newChat()
            }
            Button("All Chats") {
                WindowPresenter.shared.show()
                runtime.store?.showHistory = true
            }
            SettingsLink { Text("Settings…") }
            Divider()
            Button("Quit Cove") { NSApp.terminate(nil) }
        }
    }
}
