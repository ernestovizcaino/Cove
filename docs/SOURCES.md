# Implementation references

Checked against public documentation/source on 2026-09-16. The citations below establish APIs and dependency revisions, not a successful build of this app.

## AI SDK

- Getting started: https://swift-ai-sdk.dev/docs/getting-started
- Streaming: https://swift-ai-sdk.dev/docs/generating-text
- Messages: https://swift-ai-sdk.dev/docs/messages
- Compatible endpoints: https://swift-ai-sdk.dev/docs/providers/openai-compatible
- Pinned repository: https://github.com/zaidmukaddam/swift-ai-sdk/tree/d8d108ccf606a154647ef7eae948775a1e7aa969
- Source inspected under that revision: `Sources/AI/Core/StreamText.swift`, `Sources/AI/Core/RuntimeContext.swift`, `Sources/AI/Providers/OpenAICompatibleProvider.swift`, `OpenAIModel.swift`, `AnthropicModel.swift`, `GoogleModel.swift`, `OllamaModel.swift`.

The adapter uses `streamText(model:messages:maxOutputTokens:maxSteps:maxRetries:telemetry:)`, consumes `fullStream` only, sets retries to zero and telemetry to `.disabled`. OpenAI's specific adapter is `OpenAIChatModel`, intentionally labeled Chat Completions in Settings.

## Ollama

- Native chat API: https://docs.ollama.com/api/chat
- `/api/tags` is the catalog route already successfully called by the user.
- This project chooses native `/api/chat` for Ollama rather than the SDK's `/v1` compatibility route, so native `thinking` deltas can be retained separately.

## Textual

- Pinned repository: https://github.com/gonzalezreal/textual/tree/01b51875a5406eefc95f52a058cb059e7bc94dc4
- Manifest: https://github.com/gonzalezreal/textual/blob/01b51875a5406eefc95f52a058cb059e7bc94dc4/Package.swift
- Source inspected: `Sources/Textual/Attachment/AttachmentLoader.swift`, `Sources/Textual/Attachment/Attachment.swift`, and the attachment-loader modifier declaration.
- `StructuredText(markdown:)` handles the final Markdown. A custom `AttachmentLoader` always declines loading remote attachments.

## Apple

- SwiftData: https://developer.apple.com/documentation/swiftdata
- Versioned schema: https://developer.apple.com/documentation/swiftdata/schema/init(versionedschema:)
- Local networking ATS setting: https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowslocalnetworking
- Resizable native window: https://developer.apple.com/documentation/swiftui/windowresizability/contentminsize

No proprietary font files, copied SDK implementation, or screenshot content is bundled.


## Connect 0.2 (checked 2026-09-16)

These are implementation references, not evidence of real-key integration tests.

### Native interaction

- Menu API: https://developer.apple.com/documentation/swiftui/menu
- Menus HIG: https://developer.apple.com/design/human-interface-guidelines/menus
- Popovers HIG: https://developer.apple.com/design/human-interface-guidelines/popovers/
- Sheets HIG: https://developer.apple.com/design/human-interface-guidelines/sheets

Our design choice is a native provider menu, a separate edit sheet, and a searchable model popover. Do not assume a pixel-identical menu across OS releases.

### Endpoint and catalog contracts

- LM Studio OpenAI-compatible APIs: https://lmstudio.ai/docs/developer/openai-compat
- DeepSeek API: https://api-docs.deepseek.com/
- Google models and pagination: https://ai.google.dev/api/models
- Anthropic model listing and pagination: https://platform.claude.com/docs/en/api/models/list
- Moonshot/Kimi API overview: https://platform.kimi.ai/docs/overview
- xAI quickstart: https://docs.x.ai/developers/quickstart
- xAI chat: https://docs.x.ai/developers/rest-api-reference/inference/chat
- Z.ai API quickstart: https://docs.z.ai/guides/overview/quick-start
- Z.ai chat: https://docs.z.ai/api-reference/llm/chat-completion
- OpenRouter models: https://openrouter.ai/docs/api/api-reference/models/list-all-models-and-their-properties
- Vercel OpenAI-compatible gateway: https://vercel.com/docs/ai-gateway/sdks-and-apis/openai-chat-completions
- Cloudflare REST API: https://developers.cloudflare.com/ai-gateway/usage/rest-api/
- Cloudflare previous compat endpoint and migration notice: https://developers.cloudflare.com/ai-gateway/usage/chat-completion/

The Cloudflare REST page (last updated September 14, 2026 at retrieval) documents the account-scoped /ai/v1 base, Workers AI Read permission and cf-aig-gateway-id header. The older compat route is not used by our new preset. No validated models-list endpoint was established for the Cloudflare/Z.ai presets, so this release uses manual IDs there rather than guessing one.

### Subscription authentication

- ChatGPT Plus / API billing separation: https://help.openai.com/en/articles/6950777-what-is-chatgpt-plus
- Claude Code authentication/third-party credential rules and the unmodified runtime: https://code.claude.com/docs/en/legal-and-compliance
- Copilot SDK quickstart and CLI runtime: https://docs.github.com/en/copilot/get-started/sdk-quickstart

This release implements API/local connections only. It does not infer that every official agent runtime is impossible to embed, and does not treat an API subscription restriction as permission to reuse website session tokens.
