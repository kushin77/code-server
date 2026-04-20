## CI minute consumption trend update (schedule optimization)

Measured optimization applied in this pass (high-frequency scheduled workflows):

| Workflow | Previous cadence | New cadence | Estimated runs/day before | Estimated runs/day after |
|---|---|---|---:|---:|
| `.github/workflows/error-triage.yml` | `*/5 * * * *` | `*/15 * * * *` | 288 | 96 |
| `.github/workflows/org-repo-onboarding-dispatch.yml` | `*/5 * * * *` | `*/30 * * * *` | 288 | 48 |
| `.github/workflows/org-governance-reconcile.yml` | `*/15 * * * *` | `*/30 * * * *` | 96 | 48 |
| `.github/workflows/ide-blackbox-monitor.yml` | `*/10 * * * *` | `*/15 * * * *` | 144 | 96 |
| `.github/workflows/cloudflare-log-triage.yml` | `*/15 * * * *` | `*/30 * * * *` | 96 | 48 |
| `.github/workflows/kubernetes-log-triage.yml` | `*/15 * * * *` | `*/30 * * * *` | 96 | 48 |

Trend impact (scheduled invocation proxy):

- Total estimated scheduled runs/day before: `1008`
- Total estimated scheduled runs/day after: `384`
- Net reduction: `624` runs/day
- Relative reduction: `61.90%`

Interpretation:

- This is a measurable downward trend in scheduled GitHub Actions invocations and therefore expected GitHub-hosted minute burn for the affected workflows.
- Manual `workflow_dispatch` remains available for on-demand deep triage.
- Delivery/security coverage remains intact via periodic runs plus on-demand execution.
