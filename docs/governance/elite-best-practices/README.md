# Elite Best Practices SSOT

Purpose: single authoritative hub for on-prem redeploy excellence, IaC immutability, idempotent operations, and repository hygiene.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Scope

- On-prem deployment target: `akushnir@192.168.168.31` (primary) / `akushnir@192.168.168.42` (replica)
- Shared state: NAS `192.168.168.56` — NFSv4 exports for workspace, profile, ollama, postgres backups
- VIP failover: `192.168.168.30` via Keepalived VRRP (module wired in `terraform/main.tf`)
- Deployment method: Infrastructure as Code + deterministic compose workflows
- Session model: concurrent-agent safe, ephemeral runtime artifacts only

## Canonical Folder Structure (12 subfolders)

| Subfolder | Purpose |
|-----------|---------|
| `monorepo/` | pnpm workspace layout, package boundaries, migration evidence |
| `pnpm/` | pnpm workspace protocol, lockfile immutability, package manager policy |
| `deep/` | deep indexing, metadata, shared ownership model |
| `shared/` | shared libraries, NAS volume ownership, deduplication contracts |
| `indexed/` | master index — fast-path navigation to all canonical files |
| `meta/` | document metadata standards, naming conventions, hygiene rules |
| `structure/` | canonical folder and placement structure |
| `repo-rules/` | enforceable repository rules and CI policy mapping |
| `instructions/` | session-aware execution instructions for human and agent workflows |
| `ssot/` | immutable/idempotent deployment source of truth |
| `clean-git-tree/` | pre-deploy and post-deploy clean-tree procedure |
| `standard-naming-convention/` | SNC naming standards for files, branches, and docs |

## Quick Navigation

- **Current execution plan**: [instructions/TRIAGE-NEXT-STEPS-EXECUTION-2026-04-18.md](instructions/TRIAGE-NEXT-STEPS-EXECUTION-2026-04-18.md)
- **Master index**: [indexed/INDEX.md](indexed/INDEX.md)
- **Redeploy SSOT**: [ssot/ON-PREM-REDEPLOY-IMMUTABLE-IDEMPOTENT.md](ssot/ON-PREM-REDEPLOY-IMMUTABLE-IDEMPOTENT.md)
- **Works-on-my-machine elimination**: [instructions/WORKS-ON-MY-COMPUTER-ELIMINATION.md](instructions/WORKS-ON-MY-COMPUTER-ELIMINATION.md)
- **Deploy identity bootstrap**: [instructions/DEPLOY-SSH-IDENTITY-BOOTSTRAP.md](instructions/DEPLOY-SSH-IDENTITY-BOOTSTRAP.md)
- **Shared libraries**: [shared/SHARED-LIBRARIES.md](shared/SHARED-LIBRARIES.md)

## Architecture State (2026-04-18)

```
VIP: 192.168.168.30 (Keepalived VRRP)
├── PRIMARY:  192.168.168.31  (MASTER, priority 150)
└── REPLICA:  192.168.168.42  (BACKUP, priority 100)
       │               │
       └───────────────┘
             NAS: 192.168.168.56 (NFSv4)
             /export/code-server/workspace
             /export/code-server/profile
             /export/ollama
             /export/postgres/backups
```

Failover SLA: ~2 seconds (advert_int=1, fall=2)
State model: zero-drift — both hosts mount same NFS exports, no rsync needed

## Redeploy Priority Order

1. Validate clean tree and branch intent (`git status`, `git log -1`)
2. Validate IaC and compose configs without side effects (`docker compose config`)
3. Deploy only from on-prem host: `ssh akushnir@192.168.168.31`
4. Verify health gates (all containers healthy)
5. Record evidence and close or update issues

## Anti-Duplication Guardrails

- Do not add documentation outside this tree without a link back here
- Do not duplicate content that exists in `scripts/_common/` or `terraform/modules/`
- The former `docs/elite-best-practices/` stub tree has been retired — this tree is the only EBP location
- All CI guard invariants live in `scripts/ci/check-compose-hardening-guard.sh` (13/13 passing)


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
