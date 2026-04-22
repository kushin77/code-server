# Performance Capacity Plan

## Purpose

This document captures the capacity-planning baseline for the collaboration and auth surfaces that back the production IDE experience.

## Scope

The plan covers five load paths that are already represented in the repository load-testing suite:

- OAuth2 proxy and login flow
- Session broker creation and listing
- RBAC authorization and authenticated API calls
- Database-backed session lifecycle pressure
- Primary-to-replica failover behavior

## Baseline Assumptions

- Current production traffic is bursty, with short interactive requests and periodic session churn.
- The load-testing suite exercises the hot paths that dominate user-perceived latency.
- Baselines below are planning targets derived from the current k6 scenarios and the existing load-testing report, and should be refreshed after each major deployment change.

## Scenario Baselines

### OAuth2 Proxy

Target: 1000 req/s sustained.

- P50 target: 120 ms
- P95 target: 300 ms
- P99 target: 500 ms
- Success rate target: 99.9%
- Primary risk: upstream identity-provider latency and proxy header churn

### Session Broker

Target: 100 session creations per second, 50 filtered list requests per second, 200 metadata queries per second.

- P50 target: 60 ms
- P95 target: 120 ms
- P99 target: 200 ms
- Success rate target: 99.9%
- Primary risk: connection-pool pressure and row-lock contention

### RBAC Authorization

Target: 500 req/s with role checks.

- P50 target: 15 ms
- P95 target: 30 ms
- P99 target: 50 ms
- Success rate target: 99.99%
- Primary risk: JWT verification hot spots and policy cache misses

### Database Lifecycle Pressure

Target: 100 concurrent users driving create/read/delete cycles.

- P50 target: 40 ms
- P95 target: 80 ms
- P99 target: 100 ms
- Connection pool saturation target: below 80%
- Primary risk: PostgreSQL CPU spikes and queue buildup

### Failover Behavior

Target: 100 req/s during primary failure injection.

- Traffic loss target: under 2 seconds
- Recovery target: under 30 seconds
- P95 latency target during failover: under 1 second
- Error burst target: under 15%
- Primary risk: routing convergence delay and stale health state

## Hardware Planning

### 100 Users

Recommended minimum:

- 2 application instances
- 2 vCPU each for gateway/auth paths
- 4 GB RAM each
- PostgreSQL: 2 vCPU, 4 GB RAM
- Redis: 1 vCPU, 2 GB RAM

Expected behavior:

- Comfortable headroom for interactive use
- Failover should remain below the RTO target with little to no user-visible interruption

### 500 Users

Recommended minimum:

- 3 application instances
- 4 vCPU each for session-heavy services
- 8 GB RAM each
- PostgreSQL: 4 vCPU, 8 GB RAM
- Redis: 2 vCPU, 4 GB RAM

Expected behavior:

- Session broker remains the likely bottleneck before the gateway
- JWT and RBAC checks should remain bounded by cache hit rate
- Failover can stay within target if health checks are tuned aggressively

### 1000 Users

Recommended minimum:

- 5 application instances for session broker and gateway paths
- 4 to 8 vCPU each depending on auth and websocket mix
- 16 GB RAM per heavy session node
- PostgreSQL: 8 vCPU, 16 GB RAM
- Redis: 4 vCPU, 8 GB RAM

Expected behavior:

- Horizontal scaling should be mandatory for sustained operation
- Database and connection-pool tuning become first-order constraints
- Load shedding and queue protection should be enabled before this tier is reached

## Scaling Recommendations

1. Scale session-broker horizontally first.
2. Keep RBAC authorization stateless and cacheable.
3. Increase PostgreSQL connections only after confirming query plan stability.
4. Add Redis memory headroom before raising concurrent session ceilings.
5. Treat failover detection as an SLO, not a best-effort operational task.

## Capacity Guardrails

- Session broker instances: target 5 max before architecture review.
- OIDC issuer instances: target 3 max before architecture review.
- API gateway instances: target 5 max before architecture review.
- PostgreSQL memory usage: keep below 75% sustained.
- Redis memory usage: keep below 70% sustained.
- Docker container memory limits: leave at least 25% host headroom.

## Bandwidth Planning

For 1000 concurrent users:

- Estimate 100 to 250 KB per active user session minute for normal IDE traffic.
- Favor burst absorption over average throughput.
- Prioritize auth and session traffic above bulk transfer traffic.

## Monitoring Guidance

- Track p95 and p99 latency for all five load paths.
- Track session creation error spikes separately from auth failures.
- Alert on failover time exceeding 30 seconds.
- Alert on connection-pool occupancy above 80%.
- Keep burn-rate alerts aligned with the service SLO files in `config/prometheus/`.

## Next Refresh

Refresh this document after any major auth, database, session-routing, or failover-topology change, and rerun the load suite before adjusting the targets.
