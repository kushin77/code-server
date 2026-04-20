# NAS / Cache Baseline Report - April 19, 2026

Scope: issue #895 baseline for NAS, 10G network utilization, and cache efficiency.

## Collected Evidence

- NAS health on the primary host: both mounts are up, workspace and coder-home paths are present and writable, ollama is present but not writable by the current user, and both mounts report 68% used.
- PostgreSQL cache hit ratio on the live `codeserver` database: 99.95%.
- Historical deploy-time baseline from the migration verification record: 45 min to 1 hour.
- Post-tuning deploy target: 30 minutes or less, which is a 33-50% reduction from the conservative baseline used in this report.

## Baseline Table

| Indicator | Baseline | Target | Notes |
| --- | ---: | ---: | --- |
| NAS mount availability | 2/2 mounts up | 100% | Measured with `scripts/nas-workspace-health.sh` on the primary host. |
| NAS capacity | 68% used | <85% | Currently within the safe operating window. |
| Cache hit ratio | 99.95% | >=80% | Measured from `pg_stat_database` on the live `codeserver` database. |
| Deploy time | 45-60 min historical | <=30 min | The current target is a 33-50% reduction from the conservative baseline. |
| Regression response | manual today | automated issue creation | The baseline script can open a GitHub issue when thresholds are breached. |

## Post-Tuning Plan

1. Keep the NAS mounts and capacity within the current safety envelope.
2. Re-run the cache benchmark after tuning to confirm the ratio stays above target.
3. Re-run the deploy benchmark and record the reduction against the 45-60 minute baseline.
4. Let the regression hook create an issue whenever the cache target or NAS health gates fail.

## Related Surfaces

- [scripts/performance/nas-cache-baseline.sh](../../scripts/performance/nas-cache-baseline.sh)
- [scripts/nas-workspace-health.sh](../../scripts/nas-workspace-health.sh)
- [scripts/performance/analyze-query-performance.sh](../../scripts/performance/analyze-query-performance.sh)
- [docs/PERFORMANCE-TUNING.md](../PERFORMANCE-TUNING.md)
- [config/grafana-dashboards-31.yaml](../../config/grafana-dashboards-31.yaml)
- [config/alert-rules-31.yaml](../../config/alert-rules-31.yaml)
