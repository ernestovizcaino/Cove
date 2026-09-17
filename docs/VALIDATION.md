# Validation record — Cove 0.2.0

Date: 2026-09-16. This record covers the Connect update to the earlier source ZIP.

## Completed here

- Linux x86_64; Swift 6.2.1.
- The 28 original portable tests passed before editing.
- The updated portable suite: **68 tests passed** (28 original + 31 Connect/catalog + 9 connection-editor lifecycle tests).
- The portable target compiles Domain, the actual catalog service/request builder and network session, and the editor's headless logic. It does not compile SwiftUI, AppKit, SwiftData, Security, or the external AI SDK.
- All 27 app Swift sources and the 3 macOS-test source files syntactically parsed with the Swift compiler.
- `plutil` accepted project.pbxproj, Info.plist and entitlements; scheme/workspace XML parsed.
- All app Swift source references exist and appear in the correct compile phase. All 3 macOS test files appear in the test target. The project object graph has no missing references.
- Version changed to 0.2.0 (build 2); bundle ID, SchemaV1 and direct package revisions are unchanged.

Raw output: `core-tests.log`. Structural checks: `project-validation.json`. These checks do not certify a successful macOS build.

## Not completed here

There is no Xcode or macOS SDK in this environment. The complete app has **not** been built, linked, signed, launched or visually reviewed on macOS. The updated sheet, menus, keyboard focus, popover, window resizing and interaction with VoiceOver require a real Mac.

An attempt to link the Linux editor tests with Observation enabled encountered a Swift Observation runtime linker error. The deliverable enables @Observable only on macOS and runs the same editor logic headlessly on Linux. The 9 editor tests genuinely execute, but do not test the property-observation machinery. No synthetic macOS SDK or platform stand-ins are included.

The **12 macOS tests** (5 original persistence, 4 original ChatStore, 3 new connection-persistence tests) remain unexecuted against the real host. Real SwiftData migration/reopening and Keychain behavior remain unverified. Xcode package download/linking and transitively complete Package.resolved remain pending. No private-LAN or paid-provider requests were made here. Provider presets and request tests are not end-to-end authentication/streaming tests.

No memory, performance, binary-size, notarization or distribution claim is made.

## Mac acceptance checklist

1. Back up local edits and any important existing history. Open the new Cove.xcodeproj, select Cove / My Mac and build. Do not delete the history store to hide an error.
2. Run the macOS test target and ensure the original chats/connections reopen unchanged.
3. Open + in the composer, then Settings → + Connect. Check API/Local sections, scrolling and SF Symbols at the target macOS version.
4. With no connection saved, confirm the home-screen onboarding card appears, opens the connection editor, and disappears once a connection is saved. Then add an Ollama connection to a real server (this Mac or another computer). Discover models, save-and-use, send two turns, stop a response, and reopen the chat.
5. Cancel a new connection and a modified existing one; confirm neither is saved. Start discovery and edit the URL/key or close the sheet; old results must not reappear.
6. Configure two connections with the same model ID. Search by connection/provider/model and verify selection stays distinct, including keyboard Return/down-arrow.
7. Test a cloud connection with an owned key. Confirm generation consent, exact-endpoint Keychain scoping, wrong-key errors and no automatic retries/fallback. A public catalog may succeed with an invalid key; test a generation explicitly.
8. Check Cloudflare ID validation and manual model entry in Cloudflare/Z.ai; verify real credentials and billing separately. No website subscription token should be collected.
9. Verify editor height at the minimum chat size, system appearance, IME composition, scroll behavior, Markdown rendering, resizing and screen-reader labels.
10. Measure CPU/memory before describing quantitative lightness; this update adds no external dependencies, but that alone is not a measurement.
