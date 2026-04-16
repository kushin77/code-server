# QA Coverage Phase 2 Runbook

## Overview

This runbook covers QA Coverage Gate Phase 2 — VPN integration and continuous SLO validation for `code-server` on-prem deployment.

## Trigger

- **Scheduled**: Daily at 08:00 UTC (`qa-coverage-gates.yml`)
- **On Push**: Triggers on changes to `tests/` or workflow files
- **Manual**: GitHub Actions → QA Coverage Gates → Run workflow

## SLO Targets

| Metric | Target | Alert Threshold | Regression Threshold |
|--------|--------|-----------------|----------------------|
| Route Coverage | 95% | 90% | >5% drop |
| Interaction Coverage | 80% | 70% | >5% drop |
| API Contract Pass Rate | 90% | 80% | >5% drop |
| P99 Latency | <1000ms | <1500ms | >20% increase |

## Coverage Data Flow

```
Endpoint Scan → current-run.json
      ↓
SLO Reporter → compares vs 7-day rolling baseline
      ↓
Results → Prometheus metrics (.prom file) + GitHub step summary
      ↓
Cache → .coverage-history/ saved across runs
      ↓
Artifact → uploaded for 30-day retention
```

## Alert Types

### 🔴 FATAL: SLO Violation (exit 1)
- SLO drops below **alert threshold** (not just target)
- Blocks PR merges
- Action: Immediately investigate endpoint failures

### 🟡 WARNING: Regression (exit 2)
- SLO still above alert threshold but trending downward >5% vs baseline
- Non-blocking but logged
- Action: Monitor for 24h, investigate if continues

### ✅ All Clear (exit 0)
- All SLOs at or above targets
- No regressions

## Investigations

### When Route Coverage Drops

1. Check endpoint health manually:
   ```bash
   ssh akushnir@192.168.168.31 "docker ps --format '{{.Names}}|{{.Status}}'"
   ```

2. Test each endpoint:
   ```bash
   curl -I http://192.168.168.31/health
   curl -I http://192.168.168.31:9090/-/healthy
   curl -I http://192.168.168.31:3000/api/health
   curl -I http://192.168.168.31:9093/-/healthy
   ```

3. Check if service restarted:
   ```bash
   ssh akushnir@192.168.168.31 "docker inspect prometheus --format '{{.State.StartedAt}}'"
   ```

### When P99 Latency Increases

1. Check host resources:
   ```bash
   ssh akushnir@192.168.168.31 "top -bn1 | head -20"
   ssh akushnir@192.168.168.31 "free -h"
   ```

2. Check container logs:
   ```bash
   ssh akushnir@192.168.168.31 "docker logs --tail 50 caddy"
   ```

3. Check network from CI (outside VPN):
   ```bash
   # If testing from GitHub Actions without VPN, expect timeouts
   # This is expected behavior — CI flags it as "offline mode"
   ```

### Viewing Coverage History

The history is stored in `.coverage-history/history.json` within the GitHub Actions cache:

```bash
# Download artifact from GitHub
gh run download --repo kushin77/code-server <run-id> --name coverage-report-<run-id>
cat .coverage-history/history.json | jq '.entries[0:5]'
```

### Viewing Prometheus Metrics

After a run, metrics are available in the workflow artifact at `.coverage-history/slo-metrics.prom`:

```
qa_slo_route_coverage{environment="on-prem",job="qa-coverage-gates"} 0.95
qa_slo_route_coverage_target{...} 0.95
qa_slo_route_coverage_meets_target{...} 1
qa_slo_overall_meets_target{...} 1
qa_slo_regression_detected{...} 0
```

## Rollback / Disable

### Disable QA gates temporarily

In `.github/workflows/qa-coverage-gates.yml`, set the schedule to a commented-out cron:

```yaml
schedule:
  # Temporarily disabled: - cron: '0 8 * * *'
```

### Reset coverage baseline

Delete the `.coverage-history/` directory and re-run the workflow once to establish a new baseline.

## Adding New Endpoints

Edit `tests/vpn-enterprise-endpoint-scan/coverage-config.json`:

```json
{
  "endpoints": {
    "health_endpoints": [
      "http://192.168.168.31/health",
      "http://192.168.168.31:NEW_PORT/health"  // Add here
    ]
  }
}
```

Then re-run the workflow manually to confirm the new endpoint is covered.

## Files

- `.github/workflows/qa-coverage-gates.yml` — CI workflow
- `tests/vpn-enterprise-endpoint-scan/slo-reporter.mjs` — SLO evaluation logic
- `tests/vpn-enterprise-endpoint-scan/coverage-config.json` — SLO config
- `.coverage-history/baseline.json` — Initial baseline
- `.coverage-history/history.json` — Rolling 90-day history (in CI cache)
- `.coverage-history/slo-metrics.prom` — Prometheus metrics output

## Owner

- On-prem team (Alex Kushnir / kushin77)
- Updated: April 16, 2026
- Issue: #338
