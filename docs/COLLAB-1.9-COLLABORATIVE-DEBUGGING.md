# Collab-1.9: Collaborative Debugging

**Status**: Implementation in progress
**Target Issue**: [#1231](https://github.com/kushin77/code-server/issues/1231)
**Follow-up Transport Issue**: [#1421](https://github.com/kushin77/code-server/issues/1421)

## Overview

Collaborative debugging lets multiple workspace participants share a debug session, inspect variables, publish breakpoints, and coordinate step actions. The current implementation provides a shared session model, a DAP relay surface, and a polling-based sync path for new relay frames.

The present transport is intentionally incremental:

1. Participants create or join a shared debug session.
2. Breakpoints, variables, and step events are recorded in the session state.
3. DAP relay frames are assigned monotonically increasing sequence numbers.
4. Clients poll for relay deltas using a cursor and merge the new frames into their session view.

## Architecture

### Backend Service

The core service lives in [apps/backend/src/services/debug-session-collaboration/index.ts](../apps/backend/src/services/debug-session-collaboration/index.ts).

Key responsibilities:

- Create and manage collaborative debug sessions
- Track participants and ownership
- Store breakpoint, variable, and step history
- Relay DAP payloads to a configured target
- Expose delta sync for relay frames via a cursor

### Frontend Panel

The user-facing panel lives in [apps/frontend/src/components/CollaborativeDebuggingPanel.tsx](../apps/frontend/src/components/CollaborativeDebuggingPanel.tsx).

It provides:

- Session creation and join flow
- Breakpoint sharing
- Variable snapshot capture
- Step action relay
- Background refresh of session state
- Polling for new relay frames

### Relay Cursor Sync

Each relay frame now carries a `sequence` value, and each session tracks a `relaySequence` cursor.

The sync endpoint is:

- `GET /api/debug-sessions/:sessionId/relay/messages?actor=<name>&since=<cursor>`

This returns:

- `latestSequence`
- new relay messages after the supplied cursor

Clients can use the response to merge new DAP frames without reloading the full session.

## API Reference

### Session Routes

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/debug-sessions` | List sessions |
| POST | `/api/debug-sessions` | Create session |
| GET | `/api/debug-sessions/:sessionId` | Fetch session |
| POST | `/api/debug-sessions/:sessionId/join` | Join session |
| POST | `/api/debug-sessions/:sessionId/leave` | Leave session |
| PUT | `/api/debug-sessions/:sessionId/breakpoints` | Replace shared breakpoints |
| PUT | `/api/debug-sessions/:sessionId/variables` | Replace shared variables |
| POST | `/api/debug-sessions/:sessionId/step` | Record a shared step action |
| POST | `/api/debug-sessions/:sessionId/relay` | Relay a DAP frame |
| GET | `/api/debug-sessions/:sessionId/relay/messages` | Fetch relay deltas by cursor |

### Frontend Helper Methods

| Method | Description |
|--------|-------------|
| `createDebugSession()` | Create a shared debug session |
| `fetchDebugSession()` | Fetch the latest session state |
| `joinDebugSession()` | Join an existing session |
| `leaveDebugSession()` | Leave a session |
| `updateDebugBreakpoints()` | Update shared breakpoint set |
| `updateDebugVariables()` | Update shared variable snapshots |
| `recordDebugStep()` | Record a step action |
| `relayDebugProtocolMessage()` | Send a DAP message to the relay endpoint |
| `fetchRelayedDebugMessages()` | Fetch relay deltas using a sequence cursor |

## Usage Example

```tsx
<CollaborativeDebuggingPanel
  workspaceId="portal-main"
  actorName="Portal main"
  debuggerName="Portal debugger"
  debuggerProgram="src/main.ts"
  debuggerCwd="/workspace/portal"
/>
```

The panel can be embedded in any workspace-scoped view that already knows the active workspace and debugger launch context.

## Configuration

The collaboration relay uses a Vault-backed encryption key for outbound collaboration messages:

- `COLLABORATION_MESSAGE_ENCRYPTION_KEY`

Vault path:

- `secret/collaboration/message-encryption-key`

## Testing

Relevant tests:

- [apps/backend/src/services/debug-session-collaboration/__tests__/debug-session-collaboration.test.ts](../apps/backend/src/services/debug-session-collaboration/__tests__/debug-session-collaboration.test.ts)
- [apps/backend/src/services/debug-session-collaboration/__tests__/integration-example.test.ts](../apps/backend/src/services/debug-session-collaboration/__tests__/integration-example.test.ts)
- [apps/frontend/src/utils/__tests__/debugCollaboration.test.ts](../apps/frontend/src/utils/__tests__/debugCollaboration.test.ts)
- [apps/frontend/src/components/__tests__/CollaborativeDebuggingPanel.test.tsx](../apps/frontend/src/components/__tests__/CollaborativeDebuggingPanel.test.tsx)

## Notes

- The current implementation is polling-based for relay sync.
- The remaining real-time transport bridge work is tracked in [#1421](https://github.com/kushin77/code-server/issues/1421).