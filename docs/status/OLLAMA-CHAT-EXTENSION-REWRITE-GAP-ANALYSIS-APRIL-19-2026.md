# Ollama Chat Extension Rewrite & Gap Analysis - April 19, 2026

Status: Active
Scope: Local chat extension rewrite for code-server, focused on replacing brittle chat UX with a controllable, repo-aware assistant surface.

## Purpose

This document rewrites the current local chat experience into an explicit implementation plan and gap analysis. It is not a critique of Microsoft Copilot Chat source code itself, because that source is not present in this repository. The editable surface here is the local chat-capable extension at [../../apps/extensions/ollama-chat/src/extension.ts](../../apps/extensions/ollama-chat/src/extension.ts).

## What Exists Today

### Implemented in code

- Chat participant registration at `ollama.chat`.
- Repository-aware prompt augmentation using local workspace context.
- Live Ollama connectivity checks and model listing.
- File analysis, code generation, refactor guidance, and documentation generation helpers.
- Workspace indexing for a small set of key files.
- Extension manifest contributions for chat participants, commands, and configuration.

### Implemented in the latest rewrite pass

- Added proper disposal of the chat participant lifecycle.
- Added missing command coverage for tests, refactor guidance, and documentation generation.
- Normalized the chat prompt path around intent inference.
- Kept the chat flow fail-soft when cancellation is requested.

## Gap Analysis

| Area | Current State | Done | Gap |
| --- | --- | --- | --- |
| Chat entrypoint | The extension exposes `@ollama` chat and command shortcuts. | [x] | No dedicated conversation history or thread persistence yet. |
| Prompt orchestration | Prompts are augmented with file and repo context. | [x] | No token budgeting, prompt truncation policy, or citation strategy yet. |
| Model backend | Ollama is the only supported backend. | [x] | No abstraction for alternative chat providers or Copilot-backed routing. |
| Repository context | Key files are indexed and similarity-ranked. | [x] | Indexing is shallow, limited to the first workspace root, and not incremental. |
| Commands | Generate, analyze, index, and list-models actions exist. | [x] | No first-class UI for selecting intent, model, or output destination. |
| Output handling | Responses can be shown in chat or copied to clipboard. | [x] | No structured editor insertion flow for tests/docs/refactors yet. |
| Health checks | Ollama connectivity is probed on activation. | [x] | No background reconnect, health telemetry, or degraded-mode indicator. |
| Tests | Type-level and runtime behavior are lightly covered by code shape only. | [ ] | No extension test suite or command-level regression tests yet. |
| Permissions / safety | The extension reads workspace files and sends them to the backend. | [ ] | No explicit user consent gate, file allow-list, or redaction policy yet. |
| Observability | Console logs exist for activation and deactivation. | [ ] | No structured logs, metrics, or audit trail for chat actions yet. |
| Performance | Repository indexing and prompt assembly are simple and fast for small trees. | [x] | No large-repo throttling, caching, or background indexing strategy yet. |
| UX polish | The chat participant is usable, but basic. | [ ] | No status bar, panel, history browser, or first-run walkthrough yet. |

## What Was Done vs What Is Still Gapped

### Done

- [x] Created a local chat participant with a custom prompt pipeline.
- [x] Exposed commands for the main assistant actions.
- [x] Added repository-aware context and file context injection.
- [x] Added a health check at activation time.
- [x] Registered the extension capabilities in `package.json`.
- [x] Added lifecycle cleanup for the chat participant.
- [x] Added missing command entries for tests, refactor, and documentation generation.

### Still gapped

- [ ] Add automated tests for chat intent inference, command wiring, and prompt construction.
- [ ] Add a consent or allow-list policy before workspace content is sent to the backend.
- [ ] Add prompt truncation and context budgeting for larger repositories.
- [ ] Add incremental or cached indexing rather than a one-shot scan.
- [ ] Add structured output actions for editor insertion and diff review.
- [ ] Add telemetry or at least structured audit logging for assistant actions.
- [ ] Add a backend abstraction if the assistant should support more than Ollama.
- [ ] Add a user-facing settings surface for model selection, context limits, and safety controls.

## Rewrite Recommendation

If the goal is a durable in-repo assistant instead of a brittle chat toy, the extension should evolve toward this shape:

1. A chat participant for conversational use.
2. An explicit command palette surface for deterministic actions.
3. A workspace-context service that supports allow-lists, redaction, and incremental indexing.
4. A test suite that guards prompt assembly, intent routing, and output handling.
5. A settings and telemetry surface that makes model selection and safety behavior visible.

## Immediate Next Steps

- Add a test harness for the chat extension package.
- Add workspace consent / file filtering before repository content is sent to the backend.
- Replace the one-shot index with cached or incremental indexing.
- Add a settings UI for model, context window, and safety controls.
- Decide whether the extension should remain Ollama-only or be abstracted behind a provider interface.

## Cross-References

- Extension source: [../../apps/extensions/ollama-chat/src/extension.ts](../../apps/extensions/ollama-chat/src/extension.ts)
- Ollama client: [../../apps/extensions/ollama-chat/src/ollama-client.ts](../../apps/extensions/ollama-chat/src/ollama-client.ts)
- Repository indexer: [../../apps/extensions/ollama-chat/src/repository-indexer.ts](../../apps/extensions/ollama-chat/src/repository-indexer.ts)
- Code analyzer: [../../apps/extensions/ollama-chat/src/code-analyzer.ts](../../apps/extensions/ollama-chat/src/code-analyzer.ts)
- Manifest: [../../apps/extensions/ollama-chat/package.json](../../apps/extensions/ollama-chat/package.json)
- Program tracker SSOT: [OLLAMA-INTEGRATION.md](OLLAMA-INTEGRATION.md)
