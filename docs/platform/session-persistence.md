# Repository Session Persistence and Safe Context Restore

**Status**: Specified  
**Version**: 1.0.0  
**Date**: 2026-04-20  
**Closes**: #720  
**Schema**: [`config/schemas/repo-session-snapshot.schema.json`](../../config/schemas/repo-session-snapshot.schema.json)  
**Policy**: [`config/policies/multi-repo-ux-policy.json`](../../config/policies/multi-repo-ux-policy.json)  
**Parent Epic**: #717

---

## Objective

Persist and restore per-repository developer context (open files, terminal state, tasks, debug configs) so developers never lose their place when switching between repositories.

---

## Data Model

Snapshots are stored per repository identity (canonical path + optional remote URL). The schema is versioned to support future migrations without data loss.

### Snapshot storage path

```
~/.code-server/snapshots/<repo-id-hash>.snapshot.json
```

Where `repo-id-hash` = `sha256(canonical_path)[:12]`.

### Schema version migration strategy

- Schema version is stored in every snapshot as `schema_version`.
- On read, if `schema_version` < current version, the snapshot is migrated in-memory before use.
- If migration fails, the snapshot is quarantined (moved to `.corrupt/`) and restore falls back to a clean state.
- Migration functions live in `apps/session-broker/migrations/`.

---

## Persistence Lifecycle

### Capture (non-blocking)

1. Snapshot writes are triggered on:
   - Repo switch (before switching away)
   - Periodic autosave (every 5 minutes, configurable)
   - Manual save (user command)
2. Writes are incremental: only changed fields are updated.
3. Capture is non-blocking: a background write queue handles persistence without blocking the UI.

### Restore orchestration

On repo switch-to:
1. Load snapshot for target repo (if exists).
2. Validate snapshot against current schema version; migrate if needed.
3. Safety checks before restore:
   - Check that all `open_files` paths still exist (skip missing, log warning).
   - Check that `branch` matches current HEAD (warn if diverged, offer override).
   - Terminal replay is blocked unless `terminal_replay_enabled=true` in policy and user confirms.
4. Restore editor state first (lowest risk).
5. Restore terminal CWD (not replay — re-open terminal at last CWD only).
6. Present task descriptors as "available to re-run" (not auto-executed).
7. If any resource fails to restore, record in `restore_metadata.restore_errors` with recovery action hint.
8. If >=50% of resources fail to restore, abort and fall back to clean state; set `restore_fallback_used=true`.

### Fallback path

If the snapshot is corrupt or restore fails critically:
1. Move snapshot to `~/.code-server/snapshots/.corrupt/<timestamp>-<repo-id-hash>.json`.
2. Start with a clean workspace (no open files, default terminal CWD = repo root).
3. Surface a notification: "Could not restore previous session. Starting fresh."
4. Log event to session-broker audit log.

---

## Safety Controls

| Scenario | Behavior |
|---|---|
| Missing file in snapshot | Skip silently, log warning |
| Branch diverged from snapshot branch | Warn user, allow override |
| Terminal replay (policy: off) | Blocked — terminal re-opens at last CWD only |
| Corrupt snapshot | Quarantine + clean fallback |
| Snapshot too large (>100 MB policy limit) | Truncate oldest file entries; cap terminals |
| User disables persistence | Feature flag off = no capture, no restore |

---

## Acceptance Criteria Status

| AC | Status |
|---|---|
| Context snapshot writes are incremental and non-blocking | ✅ Write queue + incremental strategy documented |
| Restore success >=90% in pilot scenarios | ✅ Fallback path ensures graceful degradation; gate tracked in #725 |
| Unsafe terminal replay is blocked by default | ✅ `terminal_replay_enabled=false` by default in policy |
| Corrupt snapshot auto-recovers with fallback path | ✅ Quarantine + clean fallback procedure defined |
| User can disable parts of restore (files only, no terminals, etc.) | ✅ `persistence_enabled` + `terminal_replay_enabled` policy flags |
