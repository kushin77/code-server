# Repository Index — Navigation and Discoverability

Purpose: fast-path index for all canonical file locations, enabling agents and contributors to locate the right file without searching.

Status: ACTIVE
Lifecycle: active-production
Owner: platform engineering
Last Updated: 2026-04-18

## Canonical File Locations

### Infrastructure Entry Points

| File | Purpose |
|------|---------|
| `docker-compose.yml` | **Canonical** production compose (NFS-backed volumes, hardened) |
| `docker-compose.tpl` | Terraform template source for compose generation |
| `docker-compose.socket-override.yml` | Local-dev-only docker socket override |
| `terraform/main.tf` | IaC entry point — versions, storage, Keepalived module |
| `Caddyfile.production` | Production Caddy reverse proxy config |
| `.env.example` | Required environment variable template |

### Operations and Deployment

| File | Purpose |
|------|---------|
| `scripts/operations/redeploy/onprem/redeploy-remote-execute.sh` | **Primary redeploy entrypoint** |
| `scripts/operations/redeploy/preflight/onprem/redeploy-preflight.sh` | Pre-deploy validation |
| `scripts/operations/redeploy/onprem/failover-orchestrate.sh` | VRRP failover/failback |
| `scripts/operations/redeploy/onprem/state-replication-verify.sh` | NAS state verification |
| `scripts/ci/check-compose-hardening-guard.sh` | CI compose security gate (13/13 checks) |

### Documentation SSOT

| Path | Purpose |
|------|---------|
| `docs/governance/elite-best-practices/` | **Master EBP hub** (this tree) |
| `docs/governance/elite-best-practices/ssot/` | Immutable/idempotent deploy SSOT |
| `docs/governance/elite-best-practices/instructions/TRIAGE-NEXT-STEPS-EXECUTION-2026-04-18.md` | Current execution plan |
| `docs/governance/POLICY.md` | Governance policy |
| `docs/SCRIPT-WRITING-GUIDE.md` | Script authoring standards |

### Monitoring Stack

| Port | Service |
|------|---------|
| 3000 | Grafana |
| 9090 | Prometheus |
| 9093 | AlertManager |
| 16686 | Jaeger |
| 3100 | Loki |

## Active GitHub Issues (as of 2026-04-18)

| # | Priority | Title |
|---|----------|-------|
| #715 | P0 | Automate failover/failback orchestration (.31/.42) |
| #729 | P1 | Replica ingress ownership on .42 / VIP cutover |
| #714 | P1 | DR game-day suite |
| #712 | P1 | In-code-server operator run mode |
| #698 | P1 | SSH deploy identity bootstrap standardization |
| #697 | P1 | Root markdown sprawl reduction |
| #696 | P1 | Elite SSOT structure + redeploy hardening |
| #695 | P0 | Non-interactive GSM auth for portal redeploy |
| #692 | P0 | Portal OAuth redeploy reachable execution path |

## Navigation Rule

> When in doubt about where something belongs: check this index first, then the relevant subfolder README, then `docs/governance/POLICY.md`.
