# Deprecated Scripts Reference

> **Issue #382** — Canonical Operational Entrypoints
>
> All phase-based scripts listed here are superseded by canonical entrypoints under `scripts/`.
> These scripts are retained for historical reference only and will be removed 90 days from their EOL date.

---

## Deprecation Status Key

| Status | Meaning |
|--------|---------|
| ⚠️ DEPRECATED | Has canonical replacement. Use the listed alternative. |
| 🗂️ ARCHIVE | No direct replacement; logic folded into orchestrator. |

---

## Phase-7 Scripts (HA / Replication / Failover)

| Deprecated Script | Status | Canonical Replacement | EOL Date |
|-------------------|--------|-----------------------|----------|
| `scripts/deploy-phase-7-complete.sh` | ⚠️ DEPRECATED | `scripts/deploy/deploy.sh` | 2026-07-14 |
| `scripts/deploy-phase-7b-replication.sh` | ⚠️ DEPRECATED | `scripts/deploy/deploy.sh --target replication` | 2026-07-14 |
| `scripts/deploy-phase-7c-failover.sh` | ⚠️ DEPRECATED | `scripts/deploy/deploy.sh --target failover` | 2026-07-14 |
| `scripts/deploy-phase-7d-integration.sh` | ⚠️ DEPRECATED | `scripts/deploy/deploy.sh --target integration` | 2026-07-14 |
| `scripts/phase-7b-backup-sync.sh` | ⚠️ DEPRECATED | `scripts/backup.sh` | 2026-07-14 |
| `scripts/phase-7c-automated-failover.sh` | ⚠️ DEPRECATED | `scripts/deploy-keepalived.sh` | 2026-07-14 |
| `scripts/phase-7c-disaster-recovery-test.sh` | ⚠️ DEPRECATED | `scripts/disaster-recovery-procedures.sh` | 2026-07-14 |
| `scripts/phase-7d-dns-load-balancing.sh` | ⚠️ DEPRECATED | `scripts/deploy-cloudflare-tunnel.sh` | 2026-07-14 |
| `scripts/phase-7d-local.sh` | 🗂️ ARCHIVE | `scripts/deploy/deploy.sh` | 2026-07-14 |
| `scripts/phase-7e-chaos-testing.sh` | ⚠️ DEPRECATED | `scripts/chaos-testing.sh` | 2026-07-14 |

## Phase-8 Scripts (Hardening / Security)

| Deprecated Script | Status | Canonical Replacement | EOL Date |
|-------------------|--------|-----------------------|----------|
| `scripts/deploy-phase-8-cis-hardening.sh` | ⚠️ DEPRECATED | `scripts/security/harden.sh` | 2026-07-14 |
| `scripts/deploy-phase-8-container-hardening.sh` | ⚠️ DEPRECATED | `scripts/security/harden.sh --scope containers` | 2026-07-14 |
| `scripts/deploy-phase-8-egress-filtering.sh` | ⚠️ DEPRECATED | `scripts/configure-egress-filtering.sh` | 2026-07-14 |
| `scripts/deploy-phase-8-immediate.sh` | 🗂️ ARCHIVE | `scripts/security/harden.sh` | 2026-07-14 |
| `scripts/deploy-phase-8-os-hardening.sh` | ⚠️ DEPRECATED | `scripts/security/harden.sh --scope os` | 2026-07-14 |
| `scripts/deploy-phase-8-secrets-management.sh` | ⚠️ DEPRECATED | `scripts/lib/secrets.sh` | 2026-07-14 |
| `scripts/phase-8-slo-monitoring.sh` | ⚠️ DEPRECATED | `scripts/audit-logging.sh` | 2026-07-14 |

## Phase-9 / Other Phase Scripts

| Deprecated Script | Status | Canonical Replacement | EOL Date |
|-------------------|--------|-----------------------|----------|
| `scripts/deploy-phase-9b.sh` | ⚠️ DEPRECATED | `scripts/deploy/deploy.sh` | 2026-07-14 |
| `scripts/deploy-phase-9c.sh` | ⚠️ DEPRECATED | `scripts/deploy/deploy.sh` | 2026-07-14 |
| `scripts/deploy-phase-ha-patroni.sh` | ⚠️ DEPRECATED | `scripts/deploy-ha-primary-production.sh` | 2026-07-14 |
| `scripts/deploy-phase-keepalived-vrrp.sh` | ⚠️ DEPRECATED | `scripts/deploy-keepalived.sh` | 2026-07-14 |
| `scripts/PHASE-3-QUICK-START.sh` | 🗂️ ARCHIVE | See `scripts/README.md` quickstart | 2026-07-14 |

---

## Finding a Deprecated Script's Logic

If you relied on a deprecated script, consult:

1. **`scripts/README.md`** — canonical task → script mapping
2. **`git log --all -- scripts/<deprecated-script-name>.sh`** — full history
3. **`git show HEAD:scripts/<deprecated-script-name>.sh`** — last known content

---

## How Deprecation Was Announced

1. This file published (April 2026) — 90-day notice started
2. All deprecated scripts received header: `# DEPRECATED: Use <canonical> instead (EOL: 2026-07-14)`
3. CI global-quality-gate.sh warns on phase-based naming in new commits

---

## Removal Schedule

Scripts listed above will be removed (moved to git archive tag `deprecated/phase-scripts-2026-07-14`) on **July 14, 2026** unless there is an active dependency justification filed as a GitHub issue.

---

*Last updated: April 2026 | Issue: #382*
