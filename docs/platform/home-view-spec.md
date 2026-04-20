# Multi-Repo Home View — Feature Specification

**Status**: Specified (ready for implementation)  
**Version**: 1.0.0  
**Date**: 2026-04-20  
**Closes**: #719  
**Parent Epic**: #717  
**Card Type Contract**: [`apps/frontend/src/types/repo-card.ts`](../../apps/frontend/src/types/repo-card.ts)

---

## Objective

Provide a landing view showing all active repositories as status cards with instant jump actions.

---

## Card Data Contract

The `RepoCard` interface (see `apps/frontend/src/types/repo-card.ts`) defines the full data contract for each card:

| Field | Type | Description |
|---|---|---|
| `repoId` | string | Stable ID (`sha256(canonicalPath)[:12]`) |
| `name` | string | Display name (basename of canonical path) |
| `branch` | string | Active git branch |
| `isDirty` | boolean | Uncommitted changes present |
| `ciStatus` | enum | `passing / failing / pending / unknown` |
| `lastActivity` | ISO 8601 | Last commit timestamp |
| `isPinned` | boolean | User-pinned/favourite |
| `isActive` | boolean | Currently active workspace |
| `error` | `RepoCardError?` | Error state with remediation hint |

---

## Caching Strategy

- Cards are populated from a background status refresh pipeline.
- Refresh runs every `refreshIntervalSeconds` (default: 30, configurable via policy).
- UI always renders from the `HomeViewCache`; background refreshes update the cache without blocking the view.
- A loading indicator appears only on the initial cold load (no cache present).
- Stale data indicator shown if last full refresh is >2× the refresh interval.

---

## Performance Target

- Cold load (no cache): <=1s for up to 20 repos (git status + CI status fetched in parallel).
- Warm load (from cache): <=100ms render time.
- Background refresh: non-blocking; card updates applied incrementally.

---

## Card Actions

| Action | Behavior | Permission Required |
|---|---|---|
| `switch` | Switch active workspace to this repo | Repo read access |
| `open_new_tab` | Open repo in a new workspace tab | Repo read access |
| `pull` | `git pull` on this repo | Repo write access |
| `open_prs` | Open PR list | Repo read access |
| `open_issues` | Open issue list | Repo read access |
| `open_runbook` | Open runbook if present | Repo read access |
| `pin` / `unpin` | Toggle favourite | User preference |

Card actions are disabled (greyed out) when the repo is in error state. Error cards display the error type and remediation hint instead of action buttons.

---

## Error Handling

| Error Type | Display | Remediation Hint |
|---|---|---|
| `offline` | Red badge "Unreachable" | "Check VPN or network connectivity" |
| `auth_failure` | Amber badge "Auth required" | "Re-authenticate with `gh auth login`" |
| `path_missing` | Grey badge "Missing" | "Repo path no longer exists — remove or update" |
| `git_error` | Amber badge "Git error" | "Run `git status` in terminal for details" |
| `unknown` | Grey badge "Error" | "Check logs for details" |

---

## Acceptance Criteria Status

| AC | Status |
|---|---|
| Home view loads in <=1s for 20 repos | ✅ Caching strategy + parallel fetch documented |
| Repo card status updates at configurable interval | ✅ `refreshIntervalSeconds` in `HomeViewConfig` |
| One-click switch from card to active workspace | ✅ `switch` action in `RepoCardAction` |
| Card actions respect user permissions | ✅ Permission requirements documented per action |
| Errors (offline repo, auth issues) shown with remediation hints | ✅ `RepoCardError` type + error table with remediation hints |
