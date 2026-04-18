# Triage Next Steps Execution (2026-04-18)

Purpose: convert current governance and redeploy work into issue-driven, measurable execution with on-prem focus.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Current State

- Elite best-practices folder structure exists with 8 subfolders.
- On-prem preflight script exists and is wired to shared libraries.
- Real execution from this session shows SSH auth blocker from local shell:
  - `Permission denied (publickey,password)` when reaching `akushnir@192.168.168.31`

## Issue-Mapped Next Steps

1. #695 (P0): implement non-interactive secret auth path for self-hosted workflow.
2. #692 (P0): ensure workflow execution environment can reach on-prem host.
3. #696 (P1): run preflight and redeploy from SSH-authenticated context and attach evidence.
4. #697 (P1): execute root markdown migration in small `git mv` batches.

## Execution Order

1. Validate SSH identity is available in runtime that executes deploy.
2. Run:
   - `bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode ssh --ssh-key "$SSH_KEY_PATH" --fix-stale-logs`
3. Run deterministic redeploy wrapper:
   - `bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode ssh --ssh-key "$SSH_KEY_PATH" --fix-stale-logs`
   - WSL fallback: add `--ssh-bin ssh.exe` when OpenSSH key permissions differ across runtimes.
4. Capture and attach evidence in issues:
   - branch and commit
   - compose render success
   - container health table
   - auth redirect verification
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
