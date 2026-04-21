# Reviewer Collaboration Flow

**Purpose**: Reviewer Collaboration Flow reference document.

---
title: Reviewer Collaboration Flow
description: Requestor and reviewer UX flow for scoped live-session access links with expiry, audit, and revocation.
owner: platform
last_review_date: 2026-04-19
status: active
related_issues:
  - 920
---

# Reviewer Collaboration Flow

This document describes the user-facing flow for scoped live-session reviewer access.

## Requestor Flow

1. The workspace owner opens the session context hub and issues a reviewer access link for a specific session.
2. The requestor selects a permission level:
   - `view-only` for read-only observation.
   - `approve-only` for reviewer approval actions without broader access.
3. The link is bound to a single session, has an expiry timestamp, and is recorded in the audit log.
4. The requestor may revoke the link at any time before expiry.

## Reviewer Flow

1. The reviewer receives the scoped access link.
2. The link resolves only when the session matches, the link is still valid, and the requested permission does not exceed the grant.
3. One-time links are consumed on first use and cannot be reused.
4. Expired, revoked, or mismatched links fail closed and emit an audit event.

## Security Rules

- Access is session-scoped and permission-scoped.
- Link tokens are never stored in plaintext; only token hashes are retained for lookup.
- Reuse attempts are blocked when a link is one-time use.
- Revocation removes the active token reference immediately.
- Audit events include the session id and lifecycle action for traceability.

## Operational Notes

- The backend implementation lives in `apps/backend/src/services/workspace-context-hub`.
- The reviewer-link lifecycle is covered by service tests that verify permission limits, expiry, revocation, and one-time use behavior.
- This flow is intentionally minimal: it supports collaboration without granting broad workspace ownership.