# Triage Next Steps Execution (2026-04-18)

Purpose: convert current governance and redeploy work into issue-driven, measurable execution with on-prem focus.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Current State

- Elite best-practices folder structure consolidated to single canonical tree: `docs/governance/elite-best-practices/` (12 subfolders, no stubs, no duplicates).
- Former `docs/elite-best-practices/` stub tree retired (git rm'd, redirected here).
- Replica failover host path is live on `.42` for code-server + oauth2-proxy, with ingress validation on `:18080`.
- New deterministic failover entrypoint implemented:
   - `scripts/operations/redeploy/onprem/failover-orchestrate.sh`
- In-workspace operator tasks added for preflight, redeploy, status, promote, failback.
- Secure baseline hardening completed in compose/template (13/13 CI guard checks passing):
   - required `CODE_SERVER_PASSWORD` (no weak fallback)
   - no TLS bypass env in baseline compose
   - no baseline docker socket mount (optional override file only)
   - profile backups emit `sha256` checksum sidecars
   - NFS-backed volumes for NAS .56 (workspace, profile, ollama, postgres-backup)
   - legacy compose stubs retired (`scripts/docker-compose.yml`, `docker/docker-compose.yml`)
- Compose hardening CI guard: `scripts/ci/check-compose-hardening-guard.sh` (13/13)
- NAS `.56` shared storage wired (commit `4e1882b4`):
   - workspace, profile, profile-backups, ollama-data, postgres-backup → NFS `/export/*`
   - DB engines remain `driver: local` (NFS locking incompatible)
- Keepalived VRRP module wired in Terraform (commit `e2e7d149`):
   - VIP: `192.168.168.30`
   - Primary: `.31` (MASTER, priority 150), Replica: `.42` (BACKUP, priority 100)
   - `advert_int=1`, `fall=2` → ~2s failover SLA
   - Activation and orchestration path completed under #715 (closed)
- Authenticated failover continuity execution path is now present:
   - `.github/workflows/e2e-authenticated-failover-continuity.yml`
   - `scripts/ci/prepare-playwright-storage-state.sh`
   - `docs/ops/AUTHENTICATED-FAILOVER-CONTINUITY-733.md`
- Remaining strict closure gate for #733: set `PLAYWRIGHT_STORAGE_STATE_B64` and run the authenticated workflow.
- Core domain-managed client enhancement stream is now consolidated under:
   - #751 EPIC (runtime transformation)
   - #752-#760 child implementation issues
- Overlap cleanup completed for superseded issues:
   - #738 -> superseded by #759
   - #739 -> superseded by #756
   - #741 -> superseded by #757
   - #749 -> superseded by #758

## Issue-Mapped Next Steps

1. **#692 (P0)**: Portal OAuth redeploy reachable execution path — validate `redeploy-remote-execute.sh` succeeds from all operator environments.
2. **#695 (P0)**: Non-interactive GSM auth path for portal redeploy — implement `--non-interactive` flag in `scripts/fetch-gsm-secrets.sh`.
3. **#733 (P1)**: Validate authenticated code-server continuity during failover with workflow evidence.
4. **#750 (P1)**: Provision non-interactive Playwright storage-state secret pipeline for #733.
5. **#714 (P1)**: DR game-day suite — scripted promote+failback drill from `.31`→`.42`→`.31` with RPO/RTO evidence.
6. **#751 (P1 EPIC)**: Execute core runtime transformation stream with #752-#760 in dependency order.
7. **#742 (P1 EPIC)**: Execute Backstage/Appsmith/OPA/Vault adoption stream with dependency links to #751 and #735.
8. **#710 (P0 EPIC)**: Close only when #733 authenticated continuity evidence is attached and accepted.

## Execution Order

1. Validate SSH identity is available in runtime that executes deploy.
2. Run:
   - `bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode ssh --ssh-key "$SSH_KEY_PATH" --fix-stale-logs`
3. Run deterministic redeploy wrapper:
   - `bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode ssh --ssh-key "$SSH_KEY_PATH" --fix-stale-logs`
   - WSL fallback: add `--ssh-bin ssh.exe` when OpenSSH key permissions differ across runtimes.
4. Run failover orchestration flow:
   - `bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action status`
   - `bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action promote`
   - `bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action failback`
5. Run authenticated continuity workflow after secret provisioning:
   - Workflow: `E2E Authenticated Failover Continuity`
   - Inputs: `failover_wait_ms=45000` and optional `failover_trigger_cmd`
6. Capture and attach evidence in issues:
   - branch and commit
   - compose render success
   - container health table
   - auth redirect verification
   - failover evidence JSON path under `/tmp/code-server-failover-evidence/`
   - state evidence JSON paths under `/tmp/code-server-state-evidence/`
   - authenticated continuity workflow run URL and pass/fail output
   - note any degraded but non-blocking services (example: `pgbouncer` unhealthy) with a follow-up issue
7. Open runtime transformation implementation PR batches by epic child grouping:
   - Batch A: #752 + #753
   - Batch B: #754 + #755
   - Batch C: #756 + #757 + #758
   - Batch D: #759 + #760

## State Durability Commands

Run Tier-A drift and snapshot-restore verification:

- `bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action drift-report`
- `bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action replicate-tier-a`
- `bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action snapshot-restore-test`

Run compose hardening baseline guard:

- `bash scripts/ci/check-compose-hardening-guard.sh`

## Bootstrap Reference

- See `docs/governance/elite-best-practices/instructions/DEPLOY-IDENTITY-BOOTSTRAP.md` for deterministic identity setup and `local-on-host` fallback.

## Anti-Duplication Guardrails

- Do not add new helper functions if equivalents exist under `scripts/_common/`.
- Keep all operational guidance under `docs/governance/elite-best-practices/`.
- Avoid introducing duplicate workflow logic when templates can be reused.

## Done Definition

- P0 reachability and secret bootstrap issues are resolved with successful run evidence.
- Redeploy path is deterministic, repeatable, and host-executed.
- Authenticated continuity evidence is attached to #733 and linked to #710.
- No new loose root files are introduced in active branches.
