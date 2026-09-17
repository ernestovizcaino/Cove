# Cove: working instructions

Cove is a native macOS app, not a website. Preserve the compact, quiet UI from the user's reference. The app window defaults to 540×640 points. There is no permanent sidebar, hero section, onboarding funnel, account system, or backend.

The bundle identifier and Keychain service prefix still read `app.nativechat.NativeChat`, from the app's former name. Do not "clean them up": they are lookup keys for the existing sandbox container and stored credentials, and only change together with a migration.

The one exception is the first-run card in `Features/Onboarding`: it appears only while `store.connections` is empty, is dismissible, and opens the existing `ConnectionEditorView`. It is not a funnel and must not grow into a multi-step welcome flow. No connection is seeded on first launch, and no personal server address or model name belongs in the shipped defaults.

## First task on a Mac

Read README.md and docs/VALIDATION.md. Build the actual Xcode project before claiming it compiles. Run the macOS tests and manually verify the UI and the user's Ollama connection. Fix build errors without rewriting the app in another technology.

Commands:

```bash
swift test
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' -configuration Debug build
xcodebuild -project Cove.xcodeproj -scheme Cove -destination 'platform=macOS' -configuration Debug test
```

Package.swift builds the portable domain, catalog transport and connection-editor logic for tests, NOT the macOS app. On Linux the editor runs without the Observation macro. The application is Cove.xcodeproj. New application sources must be added to the Xcode project, since it uses explicit source references.

## Boundaries

- Domain contains own Codable/Sendable value types; do not persist SDK objects.
- ChatStore is MainActor-isolated, observable, and owns the single generation lifecycle.
- Requests capture immutable connection, model, history, and generation IDs.
- Do not make model-switching or chat navigation reroute an active generation.
- URLSession handles Ollama's native NDJSON. Cloud providers use SDKGenerationClient.
- The SDK is zaidmukaddam/swift-ai-sdk, import AI. Do not substitute teunlao APIs accidentally.
- The renderer is Textual, not MarkdownUI. Read the pinned source when using an unfamiliar modifier.
- Keep package revisions fixed until an intentional, verified upgrade. Commit Xcode's generated lockfile after resolution.
- SwiftData has an explicit V1 schema and migration plan. Never delete the store to hide an error.
- Keep no-op UI buttons out of the app. Add features only when their actual behavior exists.

## Connect boundaries

- Read docs/CONNECT.md. ProviderCatalog is data; ProviderKind is the wire protocol. Do not add a new client for each compatible brand.
- Preserve optional presetID/gatewayID backward decoding. The current update does not need to reset SchemaV1.
- Reuse ProviderMenuItems and ConnectionEditorView from composer/settings; avoid two competing connection forms.
- Keep lookup tokens, synchronous endpoint/key invalidation and cancellation. A late response must never mutate a newer draft.
- Never treat catalog success as billing, generation or key validation. Preserve manual IDs and partial-list warnings.
- Keep compound connection/model selection identity and searchable cached lists without a 30-item cutoff.
- Cloudflare uses its current account-scoped REST route and narrowly scoped header. Do not silently substitute the older compat route.
- Do not add inactive/fake OAuth buttons. Copilot or Claude Code runtimes need a separate official integration, not scraped subscription cookies.

## Security and behavior

- Keys belong in Keychain, scoped to connection ID AND canonical endpoint, not preferences or SwiftData.
- The project signs ad hoc on purpose, so anyone can build it. That binds each Keychain item to the binary that wrote it: rebuilding invalidates stored keys, `save` replaces rather than updates to repair them, and Settings shows the affected connection. Do not "fix" this by moving keys out of the Keychain, and do not commit a DEVELOPMENT_TEAM.
- Never embed, log, export, or silently reuse keys for another host.
- SDK telemetry is explicitly disabled. Do not add an exporter or analytics service.
- Public endpoints require HTTPS; HTTP is permitted only for local/private addresses.
- Preserve App Sandbox outgoing-network and user-selected-file entitlements.
- Never globally set NSAllowsArbitraryLoads to work around a LAN problem.
- Ask before sending history to an unapproved external connection/endpoint.
- Never fall back to a cloud model when Ollama fails.
- No automatic generation retries, tool execution, command execution, or remote Markdown image loads.
- Preserve partial responses and label cancellation/failure/interruption.
- Do not write to SwiftData on every token. Keep checkpoints and final saves explicit.
- Respect user scroll position and IME composition in the editor.

## Honest verification

The original generation environment was Linux without Xcode. Portable core tests passed and source/plist structure was checked; the macOS UI, SwiftData, Keychain, real SDK linking, and live providers were not end-to-end tested. Do not carry forward an assumption that they were.

The macOS tests use in-memory persistence, isolated preferences, and simulated generation events; do not require paid API calls to run them. A model catalog returning HTTP 200 does not establish that a provider key or generation request works.
