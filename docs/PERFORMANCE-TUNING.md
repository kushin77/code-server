# Performance Tuning

This document is the canonical performance baseline and tuning reference for the current platform.

## Scope

- Portal and IDE user-facing paths
- Authentication and redirect flows
- Stateful services and caching layers
- Load, soak, and chaos validation for production readiness

## Current Evidence

- Historical Tier 2 load test report: [../.tier2-reports/TIER-2-LOAD-TEST-REPORT.md](../.tier2-reports/TIER-2-LOAD-TEST-REPORT.md)
- Load test engine: [../src/services/testing/LoadTestEngine.ts](../src/services/testing/LoadTestEngine.ts)
- Phase 13 load test runner: [../scripts/phase13-load-test.py](../scripts/phase13-load-test.py)
- Chaos testing surface: [../apps/extensions/agent-farm/src/ml/ChaosEngineer.ts](../apps/extensions/agent-farm/src/ml/ChaosEngineer.ts)
- Platform SLOs: [slos/PLATFORM-SLOS.md](slos/PLATFORM-SLOS.md)
- Current live samples: static CSS 30/30 HTTP 200 at 0.060s average, IDE root 30/30 HTTP 302 at 0.032s average, oauth2 start 30/30 HTTP 302 at 0.028s average
- Current failover checkpoint: active host marker `192.168.168.31`, VIP owner `192.168.168.31`, primary health healthy, replica health healthy, replica ingress healthy
- NAS/cache baseline report: [status/NAS-CACHE-BASELINE-APRIL-19-2026.md](status/NAS-CACHE-BASELINE-APRIL-19-2026.md)
- Current live cache hit ratio: 99.95% on the `codeserver` database

## Baseline Targets

| Metric | Baseline Target | Notes |
|---|---:|---|
| Auth latency P99 | < 300 ms | Focus on login, redirect, and session restore |
| Portal static asset latency P99 | < 500 ms | CSS/JS delivery under cached and uncached paths |
| IDE interactive latency P99 | < 800 ms | Editor load and first-action responsiveness |
| Error rate | < 1% | During normal load and soak windows |
| Recovery time | <= 15 minutes | Failover and restart-sensitive paths |
| PostgreSQL cache hit ratio | >= 80% | Workspace artifact and dependency cache baseline |
| Build/deploy time | <= 30 minutes | Reduce from the documented 45-60 minute baseline |

## Load Test Classes

1. Authenticated concurrency tests for portal and IDE.
2. Ingress and API throughput tests under current topology.
3. Soak tests long enough to detect memory leaks, session churn, and cache instability.
4. Chaos tests for auth, ingress, NAS-dependent flows, and failover behavior.
5. Regression checks after redeploy or infra changes.

## Recommended Execution Flow

1. Validate the host and compose topology using the operational checklist.
2. Run a low-concurrency baseline to confirm the path is healthy.
3. Increase to sustained load and record P50/P95/P99 latency.
4. Run soak duration long enough to surface memory and session regressions.
5. Inject one controlled failure at a time and measure recovery.
6. Attach results to the live issue and the production readiness tracker.

## Tooling Notes

- `scripts/phase13-load-test.py` is useful for quick verification runs.
- `LoadTestEngine` is the reusable model for more structured distributed load campaigns.
- `ChaosEngineer` is the reusable failure-injection model for resilience validation.

## Open Gap

The repository has historical load evidence and reusable test scaffolding, but it still needs current production-grade campaigns for the active stack. Those campaigns remain tracked in [GitHub issue #805](https://github.com/kushin77/code-server/issues/805) and [GitHub issue #828](https://github.com/kushin77/code-server/issues/828).

## Related Docs

- [ops/OPERATIONS-INDEX.md](ops/OPERATIONS-INDEX.md)
- [ops/DEPLOYMENT-CHECKLIST.md](ops/DEPLOYMENT-CHECKLIST.md)
- [ops/DISASTER-RECOVERY-PLAN.md](ops/DISASTER-RECOVERY-PLAN.md)
- [ops/INCIDENT-RESPONSE-PLAYBOOK.md](ops/INCIDENT-RESPONSE-PLAYBOOK.md)
- [ops/EXTERNAL-BROWSER-QA-SMOKE-TESTS.md](ops/EXTERNAL-BROWSER-QA-SMOKE-TESTS.md)
- [slos/PLATFORM-SLOS.md](slos/PLATFORM-SLOS.md)