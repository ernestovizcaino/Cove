# Architecture, v0.2

One native app target and one macOS test target. No web layer, backend, or extra dependency was added for Connect. The Swift package compiles the portable domain, catalog transport, and headless editor logic for tests; it does not build the app.

```text
SwiftUI views → ChatStore (@MainActor)
                 ├─ ChatRepository → SwiftData / SchemaV1
                 ├─ KeychainStore → Security
                 ├─ ContextBuilder → immutable text-only request
                 └─ GenerationClient
                     ├─ OllamaGenerationClient → /api/chat (NDJSON)
                     └─ SDKGenerationClient → AI SDK adapters

ConnectMenu → ConnectionSheet → ConnectionEditorView
                                   └─ ConnectionEditorStore
                                       ├─ ProviderCatalog presets
                                       ├─ ModelCatalogService
                                       │    └─ ModelCatalogProtocol
                                       └─ explicit ChatStore.saveConnection

ModelPickerButton → searchable popover → explicit ChatStore.select
```

## Connection state

ProviderPreset is UI/configuration data. ProviderKind remains the wire protocol, so compatible brands share one SDK adapter rather than multiplying enum cases and clients. ProviderConnection adds optional presetID and gatewayID inside its Codable payload. SchemaV1 remains unchanged. Legacy connections without those fields map to their original transport. Names and hostnames are never used to infer a brand or authentication privilege.

The editor owns an isolated draft. Discovery does not persist. Connection names, non-secret endpoints, model IDs and gateway IDs are saved only through explicit Save. API keys remain in Keychain, scoped to connection UUID plus canonical endpoint. Save-and-use is a separate caller choice; adding a connection in Settings does not change an active conversation.

Each lookup captures a unique token, endpoint and credential. In-flight results are discarded unless the token still matches. Editing the endpoint synchronously clears the pasted key and cached model list. Closing/canceling ends the request. Existing keys are resolved for the captured endpoint only. The service refuses redirects and never follows pagination URLs to another host.

Model choice identity is connection UUID plus raw model ID. Discovery is on demand, paginated with a ten-page ceiling, and labels incomplete catalogs. Lists are searchable without the original 30-model menu cutoff. Unknown protocol capabilities stay unknown; listing a model does not certify generation compatibility.

## Conversation state and persistence

The selected conversation and active generation are distinct. Mutations address conversation ID, message ID and generation ID, not whichever chat is visible. Navigation and selection do not reroute an active request. Only one generation runs at a time.

The first user message and assistant placeholder are saved before HTTP begins. Text deltas flush to observable state in small batches; checkpoints occur approximately each second while events arrive. Finalization, error and cancellation save explicitly. Pending records reopen as interrupted. SchemaV1 retains conversations, messages and connection payloads. Deleting a connection does not delete its earlier chats.

## Provider boundary and privacy

Views do not interpret wire data. SDKGenerationClient consumes fullStream once, disables retries and telemetry, validates the endpoint and passes only narrowly scoped additional headers. Ollama retains native thinking deltas. Cloudflare uses its current REST API with its gateway header; manual discovery avoids assuming an undocumented /models API.

Provider labels are not privacy boundaries. Consent and secrets are scoped to the actual endpoint. A remote Ollama or LM Studio endpoint still needs remote-send consent. An unreachable LAN endpoint never falls back to a paid/cloud model. Subscription website tokens are not accepted as substitute API keys.

## Context policy

Keep a suffix of completed user/assistant turns within a conservative 32,000-character budget. Include the optional system prompt and new message. Do not resend reasoning, failed output, orphaned turns, or provider-specific hidden metadata. This is not exact token accounting; a new message too large fails rather than silently truncating it. The whole history remains stored.

## Deliberate limits

Plain text during streaming, Textual afterward. Title-only history search. No attachments, speech, tool execution, MCP, sync, branching, global hotkey, subscription runtime, or additional database encryption. Generic SF Symbols instead of trademark logos. Pinned normal window, not a separate quick panel.

## Validation boundary

The portable suite exercises actual core/controller code, but the editor's Observation macro is enabled only on macOS. Linux tests do not validate SwiftUI observation, AppKit behavior, SwiftData/Keychain, the SDK build, or a live provider. Open the Xcode project and run the macOS acceptance checklist before claiming those are verified.
