# Session Provenance Contract

**Purpose**: Session Provenance Contract runbook — operational procedure for session provenance contract response.

## Purpose

This contract defines the minimum provenance data required before a session broker may launch a code-server session. The launch path fails closed unless the image is digest-pinned and the provenance record is present, verified, and fresh.

## Contract

A launch is valid only when all of the following are true:

- `CODE_SERVER_IMAGE_ID` is a `sha256:` digest-pinned image reference.
- `SESSION_PROVENANCE_ATTESTATION_REF` is present.
- `SESSION_PROVENANCE_SIGNER_IDENTITY` is present.
- `SESSION_PROVENANCE_VERIFIED_AT` is a valid ISO-8601 timestamp.
- `SESSION_PROVENANCE_POLICY_VERSION` is present.
- `SESSION_PROVENANCE_VERIFICATION_RESULT` is `verified`.
- `SESSION_PROVENANCE_FRESHNESS_HOURS` is a positive integer and the attestation is still fresh.

## Launch-Time Failure Codes

- `provenance_image_not_pinned`
- `provenance_attestation_missing`
- `provenance_signer_missing`
- `provenance_verified_at_invalid`
- `provenance_policy_missing`
- `provenance_freshness_invalid`
- `provenance_not_verified`
- `provenance_stale`

## Persisted Session Metadata

The session broker persists the following provenance data with each session record:

- `provenance_manifest`
- `provenance_verified`
- `provenance_image_digest`
- `provenance_attestation_ref`
- `provenance_signer_identity`
- `provenance_verified_at`
- `provenance_policy_version`

## Operational Notes

- Launches must fail closed if provenance cannot be resolved at startup.
- The provenance record is copied onto the container environment for auditability.
- The contract is versioned as `v1` and should be updated only with a schema change and a new evidence comment.
