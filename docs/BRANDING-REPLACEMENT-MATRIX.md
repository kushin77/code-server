# Branding Replacement Matrix - code-server → Kushnir.cloud / KC

**Status**: Draft replacement matrix and exception catalog
**Owner**: Platform Engineering
**Last Updated**: 2026-04-21
**Related SSOT**: [docs/BRANDING-SSOT.md](BRANDING-SSOT.md)
**Tracks**: #1186

## Purpose

This matrix translates the branding SSOT into file-by-file review decisions. Use it to decide whether a `code-server` reference should be kept, replaced, or reviewed before editing active repository surfaces.

The guiding rule is simple:

- Keep upstream and historical references that would be incorrect or unsafe to rewrite.
- Replace repository-owned brand language that is user-facing, operational, or descriptive.
- Review ambiguous references before changing them.

## Decision Categories

| Decision | Meaning | Action |
|----------|---------|--------|
| `keep` | Reference is upstream, vendor-owned, or historical evidence | Leave unchanged |
| `replace` | Reference is project-owned and active | Rewrite using approved brand terms |
| `review` | Reference may be safe to change, but context matters | Record rationale before editing |

## Replacement Matrix

| Reference Class | Default Decision | Replacement / Outcome | Notes |
|-----------------|------------------|------------------------|-------|
| `code-server` in active docs and scripts | `replace` | `Kushnir.cloud`, `KC IDE`, or a descriptive service label | Applies to user-facing docs, runbooks, scripts, workflow names, and comments |
| `code-server` in upstream dependency names | `keep` | No change | Includes external image references such as `codercom/code-server` and third-party protocol names |
| `code_server` database or internal identifier | `review` | Usually preserve if schema or migration compatibility depends on it | Change only with a dedicated migration plan |
| `CODE_SERVER_*` environment variable family | `review` | Preserve or wrap with new aliases depending on runtime compatibility | Do not break existing deployments without a migration path |
| `kushnir.cloud` / `ide.kushnir.cloud` public domains | `keep` | No change | These are approved brand/domain targets, not old names |
| `KC` short form | `keep` | No change | Approved internal shorthand |
| Archived evidence or frozen session docs | `keep` | No change | Preserve historical accuracy unless the archive is still linked from active documentation |

## Exception Catalog

### 1. Upstream Vendor Strings

Keep `code-server` when it is part of an external dependency, image tag, protocol name, or vendor-provided identifier.

Examples:

- `codercom/code-server`
- third-party protocol names that must match an upstream API

### 2. Historical Archive Material

Keep `code-server` in archived evidence that documents prior behavior or a pre-rebrand state.

Examples:

- archived incident reports
- frozen session summaries
- legacy completion documents not linked from active guides

### 3. Compatibility-Bound Identifiers

Review before changing identifiers that are bound to live contracts.

Examples:

- database names such as `code_server`
- environment variable families such as `CODE_SERVER_*`
- cookie names, JWT audiences, and test fixtures that still reflect the legacy contract

### 4. Active Project-Owned Language

Replace `code-server` when the text is clearly describing the current product, service, or operator workflow.

Examples:

- service names in docs
- command descriptions
- user-facing dashboard labels
- workflow titles and comments

## Review Checklist

Before replacing a reference, answer these questions:

1. Is the string owned by an external dependency?
2. Is the string part of a live compatibility contract?
3. Is the string inside archived evidence or historical documentation?
4. Would a replacement change runtime behavior, storage, or public URLs?
5. Does the replacement keep the repo consistent with [docs/BRANDING-SSOT.md](BRANDING-SSOT.md)?

If any answer is uncertain, mark the item `review` and capture the rationale in the relevant implementation ticket.

## File-Class Guidance

This matrix is intended to support the downstream cleanup tickets:

- #1184 for active code and configuration
- #1185 for documentation, comments, tests, and archives

When in doubt, prefer safety over cosmetic consistency. The rebrand should be deterministic, but it should not break live contracts without a separate migration plan.