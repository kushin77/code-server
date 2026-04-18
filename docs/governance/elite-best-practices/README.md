# Elite Best Practices SSOT

Purpose: single authoritative hub for on-prem redeploy excellence, IaC immutability, idempotent operations, and repository hygiene.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Scope

- On-prem deployment target: `akushnir@192.168.168.31`
- Deployment method: Infrastructure as Code and deterministic compose workflows
- Session model: concurrent-agent safe, ephemeral runtime artifacts only

## Folder Index

- `monorepo-pnpm/` - pnpm workspace and monorepo standards
- `deep-shared-indexed-meta/` - deep indexing, metadata, shared ownership model
- `structure/` - canonical folder and placement structure
- `repo-rules/` - enforceable repository rules and CI policy mapping
- `instructions/` - session-aware execution instructions for human and agent workflows
- `instructions/DEPLOY-IDENTITY-BOOTSTRAP.md` - deterministic SSH identity and execution mode bootstrap
- `ssot/` - immutable/idempotent deployment source of truth
- `clean-git-tree/` - pre-deploy and post-deploy clean-tree procedure
- `standard-naming-convention/` - SNC naming standards for files, branches, and docs

## Reliability References

- Works-on-my-computer elimination: [instructions/WORKS-ON-MY-COMPUTER-ELIMINATION.md](instructions/WORKS-ON-MY-COMPUTER-ELIMINATION.md)
- Deploy SSH identity bootstrap: [instructions/DEPLOY-SSH-IDENTITY-BOOTSTRAP.md](instructions/DEPLOY-SSH-IDENTITY-BOOTSTRAP.md)
- Immutable state data plane: [ssot/ON-PREM-IMMUTABLE-STATE-DATA-PLANE.md](ssot/ON-PREM-IMMUTABLE-STATE-DATA-PLANE.md)

## Redeploy Priority Order

1. Validate clean tree and branch intent
2. Validate IaC and compose configs without side effects
3. Deploy only from on-prem host
4. Verify health gates
5. Record evidence and close or update issues

## Canonical Command Entry Points

- `bash scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh --mode ssh --fix-stale-logs`
- `bash scripts/operations/redeploy/onprem/redeploy-remote-execute.sh --mode ssh --fix-stale-logs`
- `bash scripts/operations/redeploy/onprem/failover-orchestrate.sh --action status|promote|failback`
- `bash scripts/operations/redeploy/onprem/operator-run-mode.sh --action preflight|redeploy|status|promote|failback`
- `bash scripts/operations/redeploy/onprem/state-replication-verify.sh --action drift-report|replicate-tier-a|snapshot-restore-test`

Baseline compose policy:

- `docker-compose.yml` is the secure production baseline and must not include docker socket mounts.
- `docker-compose.socket-override.yml` is optional and local-only for container-development workflows.
- `CODE_SERVER_PASSWORD` is required for deterministic secure startup; no weak fallback defaults.

## Operator Run Mode

- Workspace tasks in `.vscode/tasks.json` are canonical in-code-server operation entrypoints:
	- `ops:preflight-onprem`
	- `ops:redeploy-onprem`
	- `ops:failover-status`
	- `ops:failover-promote-replica`
	- `ops:failover-failback-primary`

## Non-Negotiables

- No local Windows terraform apply for production stack
- No manual in-container hotfixes for persistent config
- No untracked loose root docs; route docs under `docs/`
- No duplicate helper scripts when shared libraries exist in `scripts/_common/`
