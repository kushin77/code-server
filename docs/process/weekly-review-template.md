# Weekly Review & Reporting Template

Tracks: GitHub issue [#2413](https://github.com/kushin77/code-server/issues/2413).

## Cadence

- **When**: Friday 14:00 local, 45 minutes
- **Owner**: rotating weekly (matches standup facilitator)
- **Output**: a single markdown report committed under `artifacts/weekly/`

## Inputs (gathered automatically)

The owner runs:

```bash
bash scripts/process/generate-weekly-report.sh
```

…which collects:

- PRs merged in the last 7 days (count, list)
- Issues opened / closed in the last 7 days
- Top 5 most-active issues
- CI green-rate (last 100 runs)
- Open P0/P1 issues (count + list)
- Deployment events (success / rollback)

## Report format

```markdown
# Weekly Review — <ISO week, year>

## 1. Headline
- <single sentence: did we move forward, hold, or regress?>

## 2. Shipped
- (#NNNN) <one-line outcome>
- ...

## 3. KPIs

| Metric | This week | Last week | Δ |
|---|---|---|---|
| PRs merged          | N | N | ±N |
| Issues closed       | N | N | ±N |
| P0 open             | N | N | ±N |
| CI green-rate       | % | % | ±% |
| Deployments         | N (R rollbacks) | … | … |
| MTTR (incidents)    | … | … | … |

## 4. Risks & blockers
- <topic> — owner: @handle — needs: <decision/help>

## 5. Next week
- Top 3 outcomes we will commit to.

## 6. Decisions logged
- <Decision> — owner: @handle — link: <issue/PR>
```

## Reporting rules

- Numbers are always pulled from the generator script — no manual fudging.
- Anything claimed as "done" must link a merged PR or closed issue.
- Risks must have an owner, otherwise they become an issue before the meeting ends.

## Definition of done

- [x] Cadence and owner defined
- [x] Auto-generator script integrated (`scripts/process/generate-weekly-report.sh`)
- [x] Report format with KPI table
- [x] Decision-log section
