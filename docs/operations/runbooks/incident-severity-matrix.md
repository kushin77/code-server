# Incident Severity Matrix & Response Playbook

Tracks: GitHub issue [#2405](https://github.com/kushin77/code-server/issues/2405)
(Phase 12 — Incident Management at Scale).

## Severity matrix

| Severity | Definition (any one matches)                                                | User impact          | Page on-call? | Comms cadence | Target resolve |
|---|---|---|---|---|---|
| **SEV-1** | Full outage, data-loss risk, or security breach                          | All users            | Yes (page)    | Every 15 min  | < 1 h          |
| **SEV-2** | Major degradation; one cluster or one critical service down              | > 25% of users       | Yes (page)    | Every 30 min  | < 4 h          |
| **SEV-3** | Partial degradation; redundant component down                            | < 25% of users       | No (notify)   | Every 2 h     | < 24 h         |
| **SEV-4** | Cosmetic / minor; no SLO impact                                          | None                 | No            | Daily         | < 5 business d |

A SEV-2 or worse opens a GitHub issue with the `incident` label automatically.

## Detection-to-resolution flow

```
detect ──► declare ──► triage ──► mitigate ──► verify ──► resolve ──► post-mortem
  │           │           │           │           │          │            │
 ≤5m         ≤2m         ≤5m         depends    ≤5m        immediate    ≤5d
```

## Roles (during an active incident)

| Role            | Responsibility |
|---|---|
| Incident Commander (IC) | Runs the response. One person, full attention. |
| Communications lead     | Updates `#incidents` and stakeholders on cadence above. |
| Operations lead         | Executes mitigation/rollback steps on systems. |
| Scribe                  | Captures timeline in the incident issue. |

The IC is the on-call engineer by default; they can delegate any role.

## Mitigation toolkit

1. **Roll back** the most recent change first — see
   [docs/operations/runbooks/CONTINGENCY-ROLLBACK-RUNBOOK.md](CONTINGENCY-ROLLBACK-RUNBOOK.md).
2. **Failover** to the standby cluster:

   ```bash
   bash scripts/phase1/test-failover-procedures.sh
   ```

3. **Throttle / shed load**: enable rate-limit profile in Caddy / API gateway.
4. **Restore from backup**:

   ```bash
   bash scripts/ops/backup-idempotent.sh --restore --to=<timestamp>
   ```

## Post-mortem template

Stored in `docs/operations/post-mortems/YYYY-MM-DD-<slug>.md`.

```markdown
# Post-mortem: <title> — <date>

- **Severity**: SEV-N
- **Duration**: <detect → resolve>
- **User impact**: <quantified>
- **Incident commander**: @handle

## Timeline (UTC)
- HH:MM — first signal
- HH:MM — declared SEV-N
- ...
- HH:MM — resolved

## Root cause
<single paragraph>

## What went well
- ...

## What didn't
- ...

## Action items (each is a GitHub issue, P0/P1)
- [ ] (#NNNN) <owner> <due>
```

## SLO targets

| Metric | Target |
|---|---|
| MTTD (Mean Time To Detect)        | < 5 min  |
| MTTA (Mean Time To Acknowledge)   | < 5 min  |
| MTTR (Mean Time To Resolve, SEV-1)| < 30 min |
| MTTR SEV-2                        | < 4 h    |
| Post-mortem completion            | 100% within 5 business days |

## Definition of done

- [x] Severity definitions are quantitative
- [x] Roles named with one-sentence responsibilities
- [x] Mitigation toolkit reuses existing scripts
- [x] Post-mortem template included
- [x] SLO targets are measurable
