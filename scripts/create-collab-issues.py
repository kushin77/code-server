#!/usr/bin/env python3
"""Create 100 collaboration platform enhancement issues on GitHub."""
import subprocess, sys, time

REPO = "kushin77/code-server"

ISSUES = [
    # ── EPIC 1: Real-Time Co-Editing Engine ─────────────────────────────────
    (
        "EPIC [Collab-1]: Real-Time Co-Editing Engine — CRDT-based concurrent file editing",
        "P1,enhancement,collaboration",
        """## Summary
Implement a CRDT (Conflict-free Replicated Data Type) operation-transform engine so multiple users can edit the same file simultaneously with sub-100ms sync latency, identical to VS Code Live Share or Google Docs.

## Why
Currently zero native co-editing support. Users must context-switch to external tools (Tuple, Zoom screenshare) breaking flow. FAANG-grade collaboration platforms treat co-editing as a first-class primitive.

## Technical Approach
1. Adopt **Yjs** (CRDT library, battle-tested in VS Code / Jupyter) as the sync substrate.
2. Deploy a **y-websocket** relay service in Docker Compose alongside session-broker.
3. Patch the code-server extension host to bind the open TextDocument to a `Y.Doc` shared type.
4. Broadcast awareness tokens (cursor position, selection, user identity) over the same WebSocket channel.
5. Persist document state snapshots to PostgreSQL every 30 s so joins are fast.

## Architecture
```
Browser A  ──▶  Caddy  ──▶  y-websocket relay  ──▶  Browser B
                                  │
                             PostgreSQL (snapshots)
```

## Acceptance Criteria
- [ ] Two users opening the same file see each other's cursors within 100 ms
- [ ] Typing from both ends converges to the same document (no data loss)
- [ ] State persists across browser refreshes and user sessions
- [ ] y-websocket relay deployed as Docker Compose service with health check
- [ ] Prometheus metric: `crdt_op_latency_ms` p99 < 100 ms
- [ ] Unit tests cover convergence of 100 concurrent operations
- [ ] E2E Playwright test: two browser contexts editing same file → same content

## Effort: 40-60 h""",
    ),
    (
        "[Collab-1.1]: Cursor & selection presence broadcast in shared editor",
        "P1,enhancement,collaboration",
        """## Summary
Show teammate cursors, selections, and usernames inline in the Monaco editor during a shared session — same UX as Google Docs colored carets.

## Acceptance Criteria
- [ ] Remote cursor moves are reflected within 50 ms
- [ ] User badge (avatar + name) floats next to remote cursor
- [ ] Selection ranges shown as colored highlights
- [ ] Cursors disappear within 2 s of user disconnecting
- [ ] Works across >5 concurrent users without visual degradation

## Effort: 12-16 h""",
    ),
    (
        "[Collab-1.2]: Collaborative undo/redo history tree with per-user attribution",
        "P1,enhancement,collaboration",
        """## Summary
Maintain a branching undo/redo tree so each user can undo only their own changes without affecting teammates' work.

## Acceptance Criteria
- [ ] Ctrl+Z for User A undoes only A's operations, B's state unaffected
- [ ] Undo tree panel shows timestamps and per-user operation counts
- [ ] Max undo stack depth configurable (default 200 ops)
- [ ] Unit tests: interleaved ops from 3 users → correct per-user undo

## Effort: 10-14 h""",
    ),
    (
        "[Collab-1.3]: Document conflict resolution UI with 3-way merge visualization",
        "P1,enhancement,collaboration",
        """## Summary
When a CRDT divergence or git merge conflict is detected, present an interactive 3-way diff editor (ours / base / theirs) inside the IDE with one-click resolution actions.

## Acceptance Criteria
- [ ] Conflict detected automatically on `git pull` with merge conflicts
- [ ] 3-pane diff renders without performance degradation on files < 5 MB
- [ ] Resolution actions update the working-tree file atomically
- [ ] Audit log records resolution with user + timestamp

## Effort: 16-20 h""",
    ),
]

def create_issue(title, labels, body):
    label_list = [l.strip() for l in labels.split(",")]
    cmd = [
        "gh", "issue", "create",
        "--repo", REPO,
        "--title", title,
        "--body", body,
    ]
    for label in label_list:
        cmd += ["--label", label]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode == 0:
        url = result.stdout.strip()
        print(f"  ✓ Created: {title[:60]}... → {url}")
        return url
    else:
        print(f"  ✗ FAILED: {title[:60]}")
        print(f"    stderr: {result.stderr.strip()[:200]}")
        return None

def main():
    print(f"Creating {len(ISSUES)} collaboration enhancement issues on {REPO}")
    print("=" * 70)
    created = 0
    failed = 0
    for i, (title, labels, body) in enumerate(ISSUES, 1):
        print(f"[{i:3d}/{len(ISSUES)}] ", end="")
        url = create_issue(title, labels, body)
        if url:
            created += 1
        else:
            failed += 1
        time.sleep(0.3)  # gentle rate limiting
    print("=" * 70)
    print(f"Done: {created} created, {failed} failed")

if __name__ == "__main__":
    main()
