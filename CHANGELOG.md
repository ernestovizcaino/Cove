# Changelog

## Unreleased

Cove now runs as a menu bar app: no Dock icon and no ⌘Tab entry. `LSUIElement` starts it as an agent so the Dock icon never flashes at launch, and Settings has a **Show in the Dock** toggle that switches `NSApplication.activationPolicy` live. Turning the Dock icon off forces the menu bar item back on, so the app can never be left with no way to reach it.

Menu bar item and a configurable global shortcut. The menu bar icon opens or hides the window, starts a new chat, opens history or settings, and quits; it can be turned off in Settings. **⇧⌘C** shows or hides Cove from any app, and the combination is re-recordable in Settings. Hiding orders the window out instead of closing it, so the draft, scroll position and an in-flight generation all survive. Registration uses Carbon's `RegisterEventHotKey`, which needs no Accessibility permission and works inside the App Sandbox; a combination another app already owns is refused with a message instead of failing silently, and a modifier-less key is rejected outright.

App icon: an outlined speech bubble on a deep teal tile, drawn from source geometry rather than by hand. `Scripts/make-icon.swift` computes the mark from one centre, radius and stroke weight, renders every macOS size with `ImageRenderer`, and writes `AppIcon.appiconset` plus `docs/icon-1024.png`. Re-run it with `swift Scripts/make-icon.swift` after changing a colour or proportion.

Renamed the app to **Cove**: product, target, scheme, module, source folder, entitlements and documentation. The bundle identifier and the Keychain service prefix deliberately keep their former `app.nativechat.NativeChat` spelling — they are opaque lookup keys, and renaming them would move the App Sandbox container and orphan every stored API key. `KeychainStore` documents that. Added a description in the README and a `Credits.rtf` so **About Cove** explains what the app is.

Removed the hairline border drawn around the window; the rounded clip and the window shadow define the edge.

First-run onboarding: with no connection saved, the home screen shows one compact, dismissible card that opens the existing connection editor (Local server / API key / Custom). Nothing is seeded any more — the placeholder LAN address and personal model name were removed from the defaults, so Ollama now suggests `http://localhost:11434` and a fresh install starts with no provider until you save one. The first connection saved becomes the active one.

Composer moved to two rows: the message keeps the full width, with attach and the model selector on a control row underneath and send/dictate on its trailing edge, so a long model name no longer squeezes the editor.

Header: the chat title shows a chevron to signal that it opens the history. The top-right is down to new chat and the ⋯ menu; keeping the window on top and minimizing moved into that menu, and the pin icon appears in the header only while pinning is active.

Settings: a Window option for **Translucent** (behind-window vibrancy) or **Plain** (solid). Translucent is the default.

Tests: 71 portable and 14 macOS tests pass, and the Xcode project builds on macOS with Xcode 26.6 / Swift 6.3. Live provider generation is still untested.

## 0.2.0 — 2026-09-16

Added native Connect menus shared between the composer and Settings; 12 categorized presets plus custom compatible servers; a draft-based reusable connection editor; a searchable configured-model popover with connection-scoped identities; on-demand paginated catalog discovery; actual Cloudflare REST base/header configuration; explicit informational subscription documentation.

Changed the existing model menu to remove its 30-model cutoff. Added optional provider preset metadata without changing the persistence schema or dependency revisions. Endpoint edits invalidate pasted keys/model lists immediately; stale catalog requests cannot overwrite a new selection. HTTP redirects, cloud-send consent and endpoint-scoped Keychain remain enforced. Only explicit Save persists a draft.

Added 40 portable tests, bringing the total to 68. Added 3 macOS integration tests (unexecuted here), project-source validation and updated source/architecture documentation. No compiled .app is shipped. macOS build, UI and live provider validation remain pending.
