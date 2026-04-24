# Session Provenance Contract

**Purpose**: Session Provenance Contract runbook — operational procedure for SESSION PROVENANCE CONTRACT response.

---
title: Session Provenance Contract
description: Versioned provenance contract for session-broker launch gating and metadata persistence.
owner: platform
last_review_date: 2026-04-19
status: active
---

# Session Provenance Contract

The session broker launch path requires a provenance manifest that can be validated against the trusted code-server image digest before a session is created.

## Canonical Fields

- `manifestVersion`: `v1`
- `imageDigest`: pinned `sha256:` digest for the launched image
- `attestationRef`: provenance statement or attestation pointer
- `signerIdentity`: trusted signer identity for the provenance statement
- `verifiedAt`: ISO-8601 timestamp for the verification event
- `verificationResult`: must be `verified` before launch
- `policyVersion`: provenance policy version string
- `freshnessHours`: verification freshness window in hours
- `sessionFingerprint`: computed canonical fingerprint for the manifest payload

## Enforcement

- Public session creation requests must include a provenance payload.
- The broker validates the manifest against the trusted launch image digest.
- Stale, missing, or rejected provenance fails closed with a policy error.
- Valid provenance is persisted with the session record and returned in API responses.
- The broker computes and verifies a stable `sessionFingerprint` for persisted manifests.

## Implementations

- TypeScript contract and validators: [apps/session-broker/src/session-provenance.ts](../../apps/session-broker/src/session-provenance.ts)
- Broker integration: [apps/session-broker/src/index.ts](../../apps/session-broker/src/index.ts)
- API contract: [docs/api/session-broker.openapi.yaml](../api/session-broker.openapi.yaml)

## Related Issues

- #945 provenance contract
- #918 build provenance launch gate
- #919 deterministic session fingerprinting
