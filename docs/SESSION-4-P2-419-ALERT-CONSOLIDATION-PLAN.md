# P2 #419: Alert Rule Consolidation - Execution Plan

**Status**: EXECUTING NOW  
**Priority**: P2 🟡 HIGH  
**Goal**: Consolidate all alert rules into SSOT system with SLO/SLI definitions  

---

## Current State Analysis

Alert rules currently scattered across multiple files:
- `alert-rules.yml` — Base rules (incomplete)
- `alert-rules-phase-6-slo-sli.yml` — Phase 6 SLO/SLI rules
- `alertmanager-base.yml` — AlertManager configuration
- `alertmanager.tpl` — AlertManager template
- Prometheus scrape configs in docker-compose.yml
- Manual alert definitions in multiple scripts

**Problem**: 
- ❌ No single source of truth
- ❌ Duplicate rules with different thresholds
- ❌ SLO/SLI definitions inconsistent
- ❌ Hard to find which rule applies where
- ❌ Difficult to update thresholds globally

---

## SSOT Alert System Design

### Tier 1: Central Alert Configuration (alerts.yaml)
Single source of truth for all alert rules with:
- Rule name, severity, description
- Metric, operator, threshold, duration
- SLO/SLI classification
- Runbook references
- Notification routing

### Tier 2: Alert Severity Levels
```yaml
critical:  # P0 - Page on-call immediately
  - Production down
  - Data loss
  - Security breach
  
high:      # P1 - Escalate within 15 min
  - Major degradation
  - 5%+ users affected
  - Security warning
  
medium:    # P2 - Escalate within 1 hour
  - Moderate issues
  - Feature degradation
  - Resource warnings
  
low:       # P3 - Ticket only
  - Info alerts
  - Non-critical warnings
```

### Tier 3: SLO/SLI Definitions
```yaml
services:
  code-server:
    availability: 99.9%      # SLO: 99.9% uptime
    latency_p99: 100ms       # SLI: p99 latency < 100ms
    error_rate: 0.1%         # SLI: error rate < 0.1%
    
  database:
    availability: 99.99%     # SLO: 99.99% uptime
    query_latency_p99: 50ms  # SLI: query p99 < 50ms
    replication_lag: 1s      # SLI: replication lag < 1s
    
  cache:
    availability: 99.9%      # SLO: 99.9% uptime
    hit_rate: 95%            # SLI: cache hit rate > 95%
    eviction_rate: < 1%      # SLI: eviction rate < 1%
```

### Tier 4: Alert Rules Mapped to SLO/SLI
```yaml
alerts:
  - name: CodeServerDown
    severity: critical
    service: code-server
    slo: availability
    threshold: 0%
    duration: 1m
    condition: up{job="code-server"} == 0
    runbook: runbooks/code-server-down.md
    
  - name: DatabaseLatencyHigh
    severity: high
    service: database
    sli: query_latency_p99
    threshold: 100ms
    duration: 5m
    condition: histogram_quantile(0.99, rate(...)) > 100
    runbook: runbooks/database-slow-queries.md
```

---

## Implementation Plan

### Step 1: Create Central Alert Configuration (1 hour)
- [ ] `config/alerts/alerts.yaml` — Central SSOT for all alert rules
- [ ] `config/slo/slo-sli-definitions.yaml` — SLO/SLI targets per service
- [ ] `config/alerts/severities.yaml` — Severity level definitions

### Step 2: Generate Prometheus Rules (30 min)
- [ ] `prometheus-rules.yml` — Generated from alerts.yaml
- [ ] `prometheus-slo-rules.yml` — Generated SLO/SLI recording rules
- [ ] Script to validate Prometheus rules syntax

### Step 3: Generate AlertManager Config (30 min)
- [ ] `alertmanager-consolidated.yml` — Generated from alerts.yaml
- [ ] Routes, receivers, grouping rules
- [ ] Notification templates

### Step 4: Consolidate Documentation (1 hour)
- [ ] `docs/ALERT-SYSTEM-SSOT.md` — Complete alert system guide
- [ ] Alert runbooks linked to each rule
- [ ] SLO/SLI dashboards configured

### Step 5: Test & Validate (1 hour)
- [ ] Validate all Prometheus rules
- [ ] Test AlertManager routing
- [ ] Verify notifications work

### Step 6: Deploy & Monitor (30 min)
- [ ] Update docker-compose to use consolidated configs
- [ ] Deploy to production
- [ ] Monitor for 1 hour

---

## Alert Rules - Complete SSOT Mapping

### CODE-SERVER SERVICE
```yaml
alerts:
  - name: CodeServerDown
    severity: critical
    service: code-server
    condition: up{job="code-server"} == 0
    for: 1m
    slo: availability
    threshold: 100% (down = 0% availability)
    runbook: runbooks/code-server-down.md
    annotations:
      summary: "Code-server is down"
      description: "Code-server endpoint unreachable for > 1 minute"

  - name: CodeServerLatencyHigh
    severity: high
    service: code-server
    sli: latency_p99
    condition: histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m])) > 0.1
    for: 5m
    runbook: runbooks/code-server-slow.md
    annotations:
      summary: "Code-server p99 latency > 100ms"
      description: "Users experiencing slow response times ({{ $value }}ms)"

  - name: CodeServerErrorRateHigh
    severity: high
    service: code-server
    sli: error_rate
    condition: rate(http_requests_total{status=~"5.."}[5m]) > 0.001
    for: 5m
    runbook: runbooks/code-server-errors.md
    annotations:
      summary: "Code-server error rate > 0.1%"
      description: "{{ $value }}% of requests failing"
```

### DATABASE SERVICE
```yaml
alerts:
  - name: PostgreSQLDown
    severity: critical
    service: database
    condition: up{job="postgres"} == 0
    for: 1m
    slo: availability
    runbook: runbooks/postgres-down.md

  - name: PostgreSQLConnectionsExceeding90Percent
    severity: high
    service: database
    condition: sum(pg_stat_activity_count) / max(pg_settings_max_connections) > 0.9
    for: 5m
    runbook: runbooks/postgres-connections.md

  - name: PostgreSQLSlowQueries
    severity: high
    service: database
    sli: query_latency_p99
    condition: histogram_quantile(0.99, rate(pg_slow_queries_seconds[5m])) > 0.05
    for: 5m
    runbook: runbooks/postgres-slow.md

  - name: PostgreSQLReplicationLag
    severity: high
    service: database
    sli: replication_lag
    condition: pg_replication_lag > 1
    for: 2m
    runbook: runbooks/postgres-replication.md

  - name: PostgreSQLDiskFull
    severity: critical
    service: database
    condition: (pg_settings_max_wal_size - pg_current_wal_lsn) / pg_settings_max_wal_size < 0.1
    for: 1m
    runbook: runbooks/postgres-disk-full.md
```

### REDIS CACHE SERVICE
```yaml
alerts:
  - name: RedisDown
    severity: critical
    service: cache
    condition: up{job="redis"} == 0
    for: 1m
    slo: availability
    runbook: runbooks/redis-down.md

  - name: RedisCacheHitRateLow
    severity: medium
    service: cache
    sli: hit_rate
    condition: rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m])) < 0.95
    for: 10m
    runbook: runbooks/redis-hit-rate.md

  - name: RedisMemoryExceeding80Percent
    severity: high
    service: cache
    condition: redis_memory_used_bytes / redis_memory_max_bytes > 0.8
    for: 5m
    runbook: runbooks/redis-memory.md

  - name: RedisEvictionRateHigh
    severity: high
    service: cache
    sli: eviction_rate
    condition: rate(redis_evicted_keys_total[5m]) > 0.01
    for: 5m
    runbook: runbooks/redis-eviction.md
```

### OBSERVABILITY SERVICES
```yaml
alerts:
  - name: PrometheusDown
    severity: high
    service: monitoring
    condition: up{job="prometheus"} == 0
    for: 1m
    runbook: runbooks/prometheus-down.md

  - name: PrometheusHighMemory
    severity: high
    service: monitoring
    condition: process_resident_memory_bytes{job="prometheus"} > 1e9
    for: 10m
    runbook: runbooks/prometheus-memory.md

  - name: GrafanaDown
    severity: medium
    service: monitoring
    condition: up{job="grafana"} == 0
    for: 5m
    runbook: runbooks/grafana-down.md

  - name: AlertManagerDown
    severity: high
    service: monitoring
    condition: up{job="alertmanager"} == 0
    for: 1m
    runbook: runbooks/alertmanager-down.md

  - name: JaegerDown
    severity: medium
    service: monitoring
    condition: up{job="jaeger"} == 0
    for: 5m
    runbook: runbooks/jaeger-down.md

  - name: LokiDown
    severity: high
    service: monitoring
    condition: up{job="loki"} == 0
    for: 2m
    runbook: runbooks/loki-down.md
```

### INFRASTRUCTURE SERVICES
```yaml
alerts:
  - name: CaddyDown
    severity: high
    service: networking
    condition: up{job="caddy"} == 0
    for: 1m
    runbook: runbooks/caddy-down.md

  - name: KongDown
    severity: high
    service: networking
    condition: up{job="kong"} == 0
    for: 2m
    runbook: runbooks/kong-down.md

  - name: OAuthProxyDown
    severity: critical
    service: security
    condition: up{job="oauth2-proxy"} == 0
    for: 1m
    runbook: runbooks/oauth-down.md

  - name: VaultDown
    severity: critical
    service: security
    condition: up{job="vault"} == 0
    for: 1m
    runbook: runbooks/vault-down.md

  - name: HostCPUUsageHigh
    severity: high
    service: infrastructure
    condition: (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))) > 0.85
    for: 10m
    runbook: runbooks/high-cpu.md

  - name: HostMemoryUsageHigh
    severity: high
    service: infrastructure
    condition: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.9
    for: 10m
    runbook: runbooks/high-memory.md

  - name: DiskSpaceRunningOut
    severity: high
    service: infrastructure
    condition: (node_filesystem_avail_bytes / node_filesystem_size_bytes) < 0.1
    for: 5m
    runbook: runbooks/disk-full.md
```

---

## File Structure

```
config/
├── alerts/
│   ├── alerts.yaml                    # CENTRAL SSOT for all alert rules
│   ├── severities.yaml                # Severity level definitions
│   └── routing.yaml                   # AlertManager routing rules
├── slo/
│   ├── slo-sli-definitions.yaml       # SLO/SLI targets per service
│   └── error-budgets.yaml             # Error budget calculations
└── dashboards/
    ├── slo-sli-dashboard.json         # Grafana SLO/SLI dashboard
    └── alert-status-dashboard.json    # Alert health dashboard

prometheus-rules/
├── prometheus-rules.yml               # Generated from alerts.yaml
└── prometheus-slo-rules.yml           # SLO/SLI recording rules

alertmanager/
└── alertmanager-consolidated.yml      # Generated from alerts.yaml

docs/
├── ALERT-SYSTEM-SSOT.md               # Complete guide
├── SLO-SLI-TARGETS.md                 # SLO/SLI reference
└── runbooks/                          # Alert runbooks
    ├── code-server-down.md
    ├── postgres-down.md
    ├── redis-down.md
    └── ... (25+ runbooks)
```

---

## Benefits

✅ **Single Source of Truth** - All alert rules in one place  
✅ **Consistency** - No duplicate/conflicting rules  
✅ **Clarity** - Clear SLO/SLI mapping for each alert  
✅ **Maintainability** - Update threshold in one place  
✅ **Observability** - Know why each alert exists  
✅ **Automation** - Generate Prometheus/AlertManager configs  
✅ **Documentation** - Linked runbooks for all alerts  
✅ **Scalability** - Easy to add new services/alerts  

---

## Acceptance Criteria

- [ ] Central alerts.yaml created with 30+ rules
- [ ] SLO/SLI definitions documented for all services
- [ ] Prometheus rules generated and validated
- [ ] AlertManager config generated
- [ ] All runbooks linked
- [ ] Grafana SLO/SLI dashboard created
- [ ] Tests pass (alert routing, severity levels)
- [ ] Documentation complete (ALERT-SYSTEM-SSOT.md)
- [ ] Deployed to production
- [ ] Monitored for 24 hours with no regressions

---

*P2 #419 Alert Rule Consolidation - Execution Plan Ready*
