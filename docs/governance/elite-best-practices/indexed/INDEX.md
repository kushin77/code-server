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
| `Caddyfile` | Canonical production reverse proxy config |
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
| #751 | P1 | EPIC: Core code-server transformation to domain-managed multi-user client |
| #752 | P1 | Replace shared single-user runtime with per-session/per-user isolation |
| #753 | P1 | Tenant-aware profile hierarchy and immutable policy overlay |
| #754 | P1 | Shared workspace ACL broker for controlled folder sharing |
| #755 | P1 | Ephemeral workspace container lifecycle with TTL and snapshots |
| #756 | P1 | Mandatory portal assertion and signed policy bundle at bootstrap |
| #757 | P1 | Strict revocation path with p95 propagation SLO |
| #758 | P1 | End-to-end correlation-id audit fabric in runtime decisions |
| #759 | P2 | Harden extension supply chain and unmanaged marketplace paths |
| #760 | P2 | Core conformance suite for domain-managed client behavior |
| #742 | P1 | EPIC: Open-source control-plane adoption (Backstage/Appsmith) |
| #735 | P1 | EPIC: Portal-only extension governance for thin-client IDE |
| #710 | P0 | Stateful failover EPIC (closure depends on #733 authenticated evidence) |
| #733 | P1 | Validate authenticated code-server session continuity during failover |
| #750 | P1 | Provision non-interactive authenticated Playwright storage state for #733 |
| #714 | P1 | DR game-day suite |
| #712 | P1 | In-code-server operator run mode |
| #698 | P1 | SSH deploy identity bootstrap standardization |
| #695 | P0 | Non-interactive GSM auth for portal redeploy |
| #692 | P0 | Portal OAuth redeploy reachable execution path |

## Recently Superseded Issues

| Closed | Superseded By | Reason |
|--------|----------------|--------|
| #738 | #759 | Consolidated marketplace + extension supply-chain hardening scope |
| #739 | #756 | Consolidated mandatory bootstrap policy assertion and signed bundle enforcement |
| #741 | #757 | Consolidated strict revocation and propagation SLO implementation |
| #749 | #758 | Consolidated runtime-path audit correlation enforcement |

## Navigation Rule

> When in doubt about where something belongs: check this index first, then the relevant subfolder README, then `docs/governance/POLICY.md`.
