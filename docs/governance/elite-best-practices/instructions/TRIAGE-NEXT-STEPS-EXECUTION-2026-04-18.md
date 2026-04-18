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
   - **Activation pending**: `terraform apply -target=module.keepalived` from SSH on `.31`

## Issue-Mapped Next Steps

1. **#715 (P0)**: Activate Keepalived on hosts — `terraform apply -target=module.keepalived` from `.31`. Attach VIP verification (`ip addr show`) as evidence.
2. **#729 (P1)**: Resolve `:80/:443` ingress ownership on `.42`. Implement deterministic ingress cutover in `failover-orchestrate.sh`. Evidence: `curl` to VIP `.30` from LAN.
3. **#714 (P1)**: DR game-day suite — scripted promote+failback drill from `.31`→`.42`→`.31` with RPO/RTO evidence.
4. **#712 (P1)**: Keep operator-run mode task coverage current as scripts evolve.
5. **#698 (P1)**: Standardize SSH deploy identity bootstrap — validate `DEPLOY-SSH-IDENTITY-BOOTSTRAP.md` covers all environments (CI, local, host-native).
6. **#696 (P1)**: Close — Elite SSOT structure complete (12 subfolders, all content, no stubs, no duplicates).
7. **#697 (P1)**: Close — root loose markdown reduced to 1 file (COMPREHENSIVE-WORK-ROADMAP moved to archives).
8. **#695 (P0)**: Non-interactive GSM auth path for portal redeploy — implement `--non-interactive` flag in `scripts/fetch-gsm-secrets.sh`.
9. **#692 (P0)**: Portal OAuth redeploy reachable execution path — validate `redeploy-remote-execute.sh` succeeds from all operator environments.

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
5. Capture and attach evidence in issues:
   - branch and commit
   - compose render success
   - container health table
   - auth redirect verification
   - failover evidence JSON path under `/tmp/code-server-failover-evidence/`
   - state evidence JSON paths under `/tmp/code-server-state-evidence/`
   - note any degraded but non-blocking services (example: `pgbouncer` unhealthy) with a follow-up issue

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
- Root markdown migration is in progress with no broken links.
- No new loose root files are introduced in active branches.
