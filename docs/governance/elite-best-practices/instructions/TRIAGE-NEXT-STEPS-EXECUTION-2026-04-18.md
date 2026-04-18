# Triage Next Steps Execution (2026-04-18)

Purpose: convert current governance and redeploy work into issue-driven, measurable execution with on-prem focus.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Current State

- Elite best-practices folder structure exists with 8+ subfolders and no loose governance files added.
- Replica failover host path is live on `.42` for code-server + oauth2-proxy, with ingress validation on `:18080`.
- New deterministic failover entrypoint implemented:
   - `scripts/operations/redeploy/onprem/failover-orchestrate.sh`
- In-workspace operator tasks added for preflight, redeploy, status, promote, failback.
- Host-side failover status run executed successfully from `.31` context with evidence file:
   - `/tmp/code-server-failover-evidence/failover-20260418T182653Z.json`

## Issue-Mapped Next Steps

1. #715 (P0): attach failover/failback evidence from scripted promote + failback drill.
2. #713 (P0): finalize immutable code-server state map and backup class verification evidence.
3. #711 (P1): implement and evidence host replication + restore checks.
4. #712 (P1): keep operator-run mode task coverage current as scripts evolve.
5. New ingress cutover gap: automate DNS/VIP transition for `.31/.42` (current replica ingress proof uses `:18080` due occupied `:80/:443` on `.42`).

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
   - note any degraded but non-blocking services (example: `pgbouncer` unhealthy) with a follow-up issue

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
