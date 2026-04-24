# Runbook: Full Redeploy Certification

**Purpose**: Runbook: Full Redeploy Certification runbook — operational procedure for full redeploy certification response.

**Related Issue**: #902

## Purpose

Run a deterministic redeploy lifecycle with preflight, deploy, post-verify, and automatic rollback on failure.

## One-Command Entry Point

```bash
bash scripts/operations/redeploy/onprem/full-redeploy-certify.sh
```

## Behavior

1. Captures the current commit and the parent commit for rollback.
2. Runs the on-prem preflight guard.
3. Runs the deterministic redeploy wrapper.
4. Verifies the live surface for either the primary or replica host path.
5. If verification fails, automatically rolls back to the parent commit and re-verifies.
6. Writes an evidence manifest and SHA256 checksum bundle under `artifacts/triage/`.

## Host Paths

- Primary path: `192.168.168.31`
- Replica path: `192.168.168.42`

Pass `--host 192.168.168.42` to certify the replica path.

## Failure Conditions

- Dirty working tree on the target host.
- Preflight failure.
- Deploy failure.
- Post-verify failure followed by rollback failure.

## Evidence Files

- `artifacts/triage/redeploy-certify-<timestamp>-preflight.log`
- `artifacts/triage/redeploy-certify-<timestamp>-deploy.log`
- `artifacts/triage/redeploy-certify-<timestamp>-verify.log`
- `artifacts/triage/redeploy-certify-<timestamp>-manifest.txt`
- `artifacts/triage/redeploy-certify-<timestamp>-manifest.sha256`

## Notes

- The rollback procedure restores the previous commit and reruns the redeploy wrapper.
- The checksum file provides a stable integrity record for the evidence bundle.