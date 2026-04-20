# Service SLO Matrix

This document is the top-level SSOT for service-level objectives across the platform. It complements [docs/slos/README.md](slos/README.md) and the platform targets in [docs/slos/PLATFORM-SLOS.md](slos/PLATFORM-SLOS.md).

## Policy

- Every production service has an explicit availability target.
- User-facing HTTP services also have a latency target based on P99 request duration.
- Error budgets are tracked over a 30-day rolling window.
- Alerts should page on sustained burn rate, not on isolated spikes.

## Service Targets

| Service | SLI | SLO | Notes |
| --- | --- | --- | --- |
| code-server | Availability | 99.9% monthly | Primary developer IDE path. |
| code-server | P99 latency | < 800ms | Measured at the HTTP request layer. |
| oauth2-proxy | Availability | 99.9% monthly | Auth gateway for IDE and portal entry. |
| oauth2-proxy | P99 latency | < 500ms | Auth redirects must remain fast enough to avoid login friction. |
| caddy | Availability | 99.95% monthly | Edge proxy and TLS termination. |
| caddy | P99 latency | < 250ms | Proxy overhead must stay low. |
| postgres | Availability | 99.9% monthly | Primary data store for platform services. |
| postgres | Replication lag | < 5s | Replica health and recovery objective. |
| redis | Availability | 99.9% monthly | Session/cache backing store. |
| redis | P99 latency | < 50ms | Cache performance target. |
| session-broker | Availability | 99.9% monthly | Internal session orchestration path. |
| session-broker | P99 latency | < 500ms | Session creation and routing must stay responsive. |
| token-microservice | Availability | 99.9% monthly | Token minting and validation service. |
| token-microservice | Correctness | 99.99% successful responses | Token operations must fail closed. |

## Error Budget Policy

For a 30-day window:

- 99.9% SLO = 43.2 minutes of error budget.
- 99.95% SLO = 21.6 minutes of error budget.

If a service consumes more than 50% of its budget, release risk must be reviewed before further rollout.
If a service consumes more than 80% of its budget, new deployments pause until the service is back within policy.

## Alerting Model

The alert rules consume three layers of signal:

- `up{job=...}` for service availability.
- `http_requests_total` and `http_request_duration_seconds_bucket` for HTTP error-rate and latency signals.
- Rolling recording rules for 5m, 1h, 6h, and 30d windows so burn rate can be compared against the remaining budget.

The active Prometheus rules in `alert-rules.yml` and `config/alert-rules-31.yaml` must stay aligned with this document.

## Evidence and Review

- Update this matrix before changing targets or alert thresholds.
- Link production validation evidence or an incident review when targets change.
- Revisit the matrix when new production services are added.