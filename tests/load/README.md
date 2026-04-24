# Load Test Suite

This directory provides the canonical k6-facing load test entrypoints for performance and capacity planning.

The scripts here re-export the maintained implementations under `scripts/load-testing/` so the suite stays in sync with the operational runner while still giving the repo a stable `tests/load/` location for CI, docs, and issue tracking.

## Scenarios

- `oauth2-proxy-load-test.js` - OAuth2 proxy and login flow throughput
- `session-broker-load-test.js` - session creation and listing pressure
- `rbac-authorization-load-test.js` - authenticated API and RBAC checks
- `database-load-test.js` - database-backed session lifecycle pressure
- `failover-performance-load-test.js` - primary-to-replica failover resilience

## Run

```bash
k6 run tests/load/oauth2-proxy-load-test.js
k6 run tests/load/session-broker-load-test.js
k6 run tests/load/rbac-authorization-load-test.js
k6 run tests/load/database-load-test.js
k6 run tests/load/failover-performance-load-test.js
```

## Notes

- Set `OAUTH_BASE_URL`, `OIDC_ISSUER`, `API_BASE`, and `JWT_TOKEN` as needed.
- The failover scenario expects a healthy primary and replica before the failover window begins.
- Weekly execution is handled by the existing GitHub Actions load-testing workflow.
