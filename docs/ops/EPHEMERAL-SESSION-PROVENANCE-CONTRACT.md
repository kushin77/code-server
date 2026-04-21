# Ephemeral Session Provenance Contract

**Purpose**: Ephemeral Session Provenance Contract reference document.

---
title: Ephemeral Session Provenance Contract
description: Source-of-truth contract for verified-build launch gating and deterministic session manifest replay.
owner: kushin77
last_review_date: 2026-04-19
status: active
related_issues:
  - 945
  - 918
  - 919
---

# Ephemeral Session Provenance Contract

## Purpose

This contract defines the minimum provenance data required before an ephemeral workspace launch may proceed.
It is the source of truth for launch gating, audit linkage, and deterministic replay fingerprints.

## Required Fields

A launch request MUST carry a provenance manifest with the following fields:

- `imageDigest`: immutable image digest, formatted as `sha256:<64-hex>`.
- `attestationRef`: stable attestation reference or URI.
- `signerIdentity`: identity that verified the build.
- `verificationTimestamp`: verification time recorded at or before launch.
- `verificationResult`: must be `verified`.
- `policyVersion`: must be `ephemeral-provenance-v1`.

## Fail-Closed Behavior

Launch MUST be denied when any of the following is true:

- Provenance manifest is missing.
- `verificationResult` is not `verified`.
- `imageDigest` does not match the required digest format.
- `attestationRef` or `signerIdentity` is empty.
- `policyVersion` is unsupported.
- `verificationTimestamp` is stale or in the future beyond the allowed clock skew.

The launch path must not downgrade to a permissive mode when provenance is unavailable.

## Session Metadata

On a successful launch, session metadata MUST capture:

- The provenance manifest used for admission.
- A deterministic `sessionFingerprint` derived from the launch inputs.
- Audit linkage to the active repo, workspace set, and provenance attestation.

## Fingerprint Rules

The session fingerprint is deterministic for identical launch inputs and MUST be derived from:

- Workspace set id
- Owner and org
- Active repo id
- Repository ids in the workspace set
- Open files in the snapshot, if present
- Provenance manifest fields

The fingerprint MUST NOT depend on ephemeral tracing values such as correlation id.

## Validation Policy

- Maximum provenance age: 24 hours.
- Clock skew allowance: 5 minutes.
- Policy version: `ephemeral-provenance-v1`.

## Related Tests

The workspace context hub service test suite includes:

- Missing provenance denial
- Invalid provenance denial
- Stale provenance denial
- Deterministic session fingerprint checks

## Implementation Notes

- Backend launch enforcement is implemented in `apps/backend/src/services/workspace-context-hub`.
- Frontend session models expose the same provenance shape for API alignment.
- This contract is intended to unblock #918 and #919 by defining the attestation and replay inputs explicitly.
