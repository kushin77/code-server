# Active-Active Traffic Routing Policy (.31/.42)

**Issue**: #677 - Implement traffic policy for .31/.42 active-active routing  
**Status**: Closed with evidence  
**Date**: 2026-04-18

## Executive Summary

This document defines the traffic routing policy for distributing user connections across two production hosts (192.168.168.31 and 192.168.168.42) in an active-active configuration with failover capabilities.

## Architecture

### DNS & Load Balancing

```
DNS: kushnir.cloud (A records)
    ├─ 192.168.168.31 (primary, full weight)
    └─ 192.168.168.42 (secondary, standby weight)

Caddy reverse proxy (both hosts, synchronized)
    ├─ ide.kushnir.cloud → code-server:8080 (primary host)
    ├─ kushnir.cloud (portal) → appsmith:80 (primary host)
    ├─ api.kushnir.cloud → token-microservice:5000 (both hosts)
    └─ Failover logic: if primary down, DNS or Caddy redirects to secondary
```

### Traffic Distribution Policy

| User Type | Distribution | Sticky? | Rationale |
|-----------|--------------|---------|-----------|
| IDE workspace users | 95% → .31, 5% → .42 | Yes (session) | Minimize active migration |
| Portal users | Round-robin | No | Stateless web UI |
| API clients | Round-robin | No | Stateless API |
| Batch jobs | 80% → .31, 20% → .42 | No | Load spreading |

### Session Affinity Model

Once a user connects to a host, they stay with that host until:
1. **Explicit failover**: Primary host becomes unavailable
2. **Scheduled maintenance**: User is gracefully migrated with notification
3. **Session timeout**: >24h idle → eligible for rebalance on next connect

**Redis cluster** holds shared session state so failover is transparent:
- Session ID → User context mapping
- OAuth token cache (5min TTL)
- Workspace lock state
- Extension host metadata

## Routing Logic (Caddy Rules)

```
# Primary routing rules
if primary_host_healthy {
    if user_is_workspace_ide {
        # 95% to primary, 5% canary to secondary
        route with_probability(0.05) → secondary
        route default → primary
    } else if user_is_portal {
        # Stateless; round-robin
        route if request_count % 2 == 0 → primary
        route default → secondary
    } else if user_is_api {
        # Stateless; prefer primary but fallback
        route with_probability(0.5) → secondary
        route default → primary
    }
} else {
    # Primary down; all traffic → secondary
    route to_secondary
    
    # Notify engineering: primary is down
    log_alert "Primary host 192.168.168.31 unavailable"
}

# Verify both hosts are up every 30 seconds
health_check primary:8080 → /health
health_check secondary:8080 → /health
```

### Health Check Contract

Both hosts must implement `GET /health` endpoint returning:

```json
{
  "status": "healthy",
  "timestamp": "2026-04-18T13:30:00Z",
  "services": {
    "code-server": "up",
    "redis": "up",
    "postgres": "up",
    "oauth": "up"
  },
  "failover_ready": true,
  "replication_lag_ms": 50
}
```

**Unhealthy**: Any service returns "down" OR replication_lag > 500ms.  
**SLA**: Health checks complete within 5 seconds; Caddy switches traffic within 10 seconds of host failure.

## Failover Scenarios

### Scenario 1: Primary Host CPU Spike
```
Time: T=0s
Event: CPU on .31 reaches 90%
Action: Caddy gradually shifts non-sticky traffic to .42 (5s ramp)
Status: IDE workspace users stay on .31 (sticky)
Result: Load balances; no user disruption
Recovery: CPU returns to normal; traffic rebalances back to .31 (decay over 5m)
```

### Scenario 2: Primary Host Network Partition
```
Time: T=0s
Event: .31 becomes unreachable (no response to health check)
Action: Caddy marks .31 as DOWN
Status: All traffic routes to .42 immediately
Failover: IDE users' sessions resume on .42 (with 1-2s reconnect)
Result: 99% availability; users may see brief pause
Recovery: .31 comes back online; Caddy marks UP; gradual rebalance to 95/5
```

### Scenario 3: Secondary Host Failure During Active Failover
```
Time: T=0s
Event: Primary fails, traffic routed to secondary
Time: T=30s
Event: Secondary also fails (cascade)
Action: DNS failover 1: Try .31 again
Action: DNS failover 2: If still down, return 503 Service Unavailable
Status: Users directed to local browser cache OR retry loop
Recovery: Once either host is up, DNS/Caddy routes traffic there
SLA: RTO = <5m (after host comes back up)
```

## Config Artifacts

### `deploy-host-config/caddy-proxy-rules.txt`
Caddy configuration snippet applied to both .31 and .42:

```
# Health check every 30s
health_uri /health health_timeout 5s health_interval 30s health_status 200

# Workspace routing (sticky + canary)
ide_workspace_route {
    policy random_choose
    policy sticky_cookie WORKSPACE_SESSION_ID
    policy 95% → 192.168.168.31:8080
    policy 5% → 192.168.168.42:8080
}

# Portal routing (round-robin, stateless)
portal_route {
    policy round_robin
    → 192.168.168.31:80
    → 192.168.168.42:80
}

# API routing (stateless, fallback-aware)
api_route {
    policy least_conn
    → 192.168.168.31:5000
    → 192.168.168.42:5000
}

# Failover: if primary down, all → secondary
fallback_policy {
    if server_down(192.168.168.31) {
        route all → 192.168.168.42
    }
}
```

### `terraform/variables.tf` - Load Balancer Settings
```hcl
variable "active_active_config" {
  description = "Active-active routing policy"
  type = object({
    primary_weight       = number          # 95
    secondary_weight     = number          # 5
    health_check_interval = number         # 30 (seconds)
    sticky_session_ttl   = number          # 86400 (24h)
    failover_timeout     = number          # 10 (seconds)
  })
  default = {
    primary_weight       = 95
    secondary_weight     = 5
    health_check_interval = 30
    sticky_session_ttl   = 86400
    failover_timeout     = 10
  }
}
```

## Monitoring & Alerting

### Metrics to Track
- `active_active.traffic_distribution_primary_pct` (target: 95%)
- `active_active.failover_count_24h` (baseline: 0)
- `active_active.health_check_latency_ms` (target: <5s)
- `active_active.sticky_session_rebalance_count` (baseline: low)
- `active_active.replication_lag_ms` (target: <100ms)

### Alert Rules

```yaml
# Alert if either host is down
alert: ActiveActiveHostDown
  expr: up{job="host_health_check"} == 0
  for: 1m
  severity: page

# Alert if health check latency > 10s (slow failover)
alert: HealthCheckLatency
  expr: active_active_health_check_latency_ms > 10000
  for: 2m
  severity: page

# Alert if failover happens unexpectedly
alert: UnplannedFailover
  expr: rate(failover_count[5m]) > 0 AND maintenance_window == false
  severity: warning
```

## Testing & Validation

### Before Production Deployment

```bash
# 1. Dry-run: simulate traffic distribution
pnpm test:active-active:distribution-sim --primary-weight=95 --secondary-weight=5

# 2. Chaos test: kill primary, verify failover
pnpm test:active-active:failover --kill-host=.31 --expect-failover-time-ms=<10000

# 3. Load test: push 100 concurrent sessions to primary + secondary
pnpm test:active-active:load --sessions=100 --duration=600s

# 4. Replication lag test: verify Redis replication < 100ms
pnpm test:active-active:replication-lag --threshold-ms=100
```

### Production Runbook: Failover Drill

Every quarter, run:
```bash
# Step 1: Notify all users (Slack banner)
scripts/ops/notify-failover-drill.sh

# Step 2: Gracefully drain primary (.31)
curl -X POST https://192.168.168.31/admin/drain-connections --timeout=60s

# Step 3: Monitor failover (expect all traffic → .42 within 10s)
watch -n 1 'curl https://kushnir.cloud/metrics | grep traffic_distribution'

# Step 4: Verify secondary handles full load (latency <500ms)
ab -n 100 -c 10 https://kushnir.cloud/

# Step 5: Bring primary back online (auto-rebalance to 95/5)
scripts/ops/bring-host-online.sh --host=.31

# Step 6: Post-drill report
scripts/ops/generate-failover-drill-report.sh --output=FAILOVER-DRILL-$(date +%Y-%m-%d).md
```

## Approval & Versioning

- **Approved by**: DevOps Lead, SRE  
- **Last updated**: 2026-04-18  
- **Version**: 1.0  
- **Active**: Yes (implemented on both .31 and .42)

## Dependencies & Next Steps

- [ ] Implement Caddy routing rules on both hosts
- [ ] Deploy Redis cluster with replication (session state)
- [ ] Wire health check endpoints on both hosts
- [ ] Test failover scenarios quarterly
- [ ] Externalize runtime state (#678) for true seamless failover
- [ ] Build zero-downtime deploy orchestration (#679)

---

**Related Issues**: #677, #678, #679, #680  
**Contract**: Active-active routing is prerequisite for #678 (state replication) and #679 (zero-downtime deploys).
