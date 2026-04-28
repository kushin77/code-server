# Contingency & Rollback Runbook

Tracks: GitHub issue [#2412](https://github.com/kushin77/code-server/issues/2412).

> **TL;DR** — every production change must have a documented rollback path
> verified ahead of time. This runbook is the single entry point.

## 1. When to roll back

Roll back, do not roll forward, when **any** of the following is true:

| Trigger | Threshold |
|---|---|
| Service availability drops | < 99.5% over 5 min |
| Error rate spikes          | > 1% sustained 3 min |
| Latency P95 regression     | > 2× the pre-deploy 1h baseline for 5 min |
| Critical alert fires       | Pager rule `severity=critical` |
| Manual STOP                | On-call SRE calls "ROLLBACK" in #incidents |

## 2. Decision matrix (≤ 5 minutes)

```
                   was the change deployed
                   in the last 30 minutes?
                          │
              ┌───────────┴───────────┐
             yes                      no
              │                       │
    is the trigger above?     follow incident-response
              │                runbook (no rollback yet)
       ┌──────┴──────┐
      yes            no
       │             │
   ROLLBACK     monitor 5 min,
   (this doc)   re-evaluate
```

## 3. Rollback paths

### 3.1 Docker Compose service rollback (most services)

```bash
# Verify dry-run first — must pass before live execution
bash scripts/ops/automated-rollback.sh --dry-run --target=compose

# Execute
bash scripts/ops/automated-rollback.sh --target=compose --service=<name>
```

The script restores the previous compose image tag from
`artifacts/deployment-state/<timestamp>.json` and re-runs health checks.

### 3.2 Terraform infrastructure rollback

```bash
bash scripts/ops/automated-rollback.sh --dry-run --target=terraform
bash scripts/ops/automated-rollback.sh --target=terraform
```

This re-applies the last known-good state file pinned in
`terraform/state-snapshots/`.

### 3.3 Database rollback

- **Schema migrations**: every migration must ship with a `down` step. Use:

  ```bash
  bash scripts/db/migrate.sh down --to=<revision>
  ```

- **Data corruption**: restore from idempotent backup:

  ```bash
  bash scripts/ops/backup-idempotent.sh --restore --to=<timestamp>
  ```

  RPO target: 0 seconds (streaming replication) for Postgres,
  ≤ 5 minutes for everything else.

### 3.4 DNS / failover cluster rollback

- Flip the DNS record back to the previous primary cluster.
- See [docs/operations/DNS-ARCHITECTURE.md](../operations/DNS-ARCHITECTURE.md)
  for record names, TTLs, and the canonical flip command.

## 4. Verification after rollback

Run, in order:

```bash
bash scripts/ops/quick-health-check.sh
bash scripts/ci/health-check-post-deploy.sh
bash scripts/phase1/test-failover-procedures.sh --dry-run
```

All three must return non-error before the incident is downgraded.

## 5. Communication

| Step | Audience | Channel |
|---|---|---|
| Declare ROLLBACK | On-call + SRE lead | #incidents (pinned) |
| 5-min status | Engineering | #eng-broadcast |
| Resolution | All hands | #eng-broadcast + email |
| Post-mortem (≤ 5 business days) | All hands | shared doc + GitHub issue |

## 6. Pre-flight: before any production change

- [ ] Rollback path identified and named in PR description
- [ ] Rollback dry-run passes in CI
- [ ] Last-known-good artifact exists under `artifacts/deployment-state/`
- [ ] On-call notified and acknowledged in #eng-broadcast
- [ ] Change tagged with the issue / PR number for the audit trail

## 7. Risk matrix

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| Compose image tag missing | Low | High | Image-tag retention check in CI |
| Terraform drift since deploy | Med | High | `gitops-drift-detector.sh` runs hourly |
| DB migration not reversible | Low | Critical | Migration review checklist enforced by CI |
| DNS TTL too long | Low | Med | TTL pinned ≤ 60s for prod records |

## 8. Definition of done for this runbook

- [x] Triggers are quantitative
- [x] Decision matrix fits on one screen
- [x] Each rollback path has a copy-pasteable command
- [x] Verification steps reuse existing scripts
- [x] Communication plan + pre-flight checklist included
