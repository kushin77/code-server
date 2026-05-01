# SLOG Taxonomy and Error Capture

**Issue:** #3151 - Unified Logging, Monitoring, Observability + SLOG Error Capture  
**Status:** Active taxonomy reference

## Purpose

SLOG (Structured Logging Over Git) defines a comprehensive error and event taxonomy for capturing, routing, and retaining all issues across hardware, services, infrastructure, and application layers.

## Severity Classifications

| Level | Definition | Examples | Routing | Retention |
|-------|-----------|----------|---------|-----------|
| **CRITICAL** | Complete outage or data loss | Database down, all APIs 5xx, network partition | PagerDuty + Slack critical | 90 days |
| **WARNING** | Service degradation or anomaly | High latency (>2s), 50% error rate, resource exhaustion | Slack warnings | 30 days |
| **INFO** | Operational event or status change | Service startup, config reload, scaling event | Logs only | 14 days |
| **DEBUG** | Diagnostic information | Request trace, memory profile, SQL trace | Logs only | 7 days |

## Error Categories

### Infrastructure Errors

**Disk Space**
- Error: `CRITICAL: Disk usage > 90%`
- Source: `node-monitor`, `disk-watchdog`
- Retention: 90 days
- Actions: Alert ops, trigger cleanup workflow, scale storage

**CPU/Memory Pressure**
- Error: `WARNING: CPU > 80%`, `WARNING: Memory > 85%`
- Source: `system-monitor`, `cgroups-watchdog`
- Retention: 30 days
- Actions: Profile, scale horizontally, investigate runaway processes

**Network Connectivity**
- Error: `CRITICAL: Replica unreachable`, `WARNING: Latency spike (>100ms)`
- Source: `keepalived`, `network-monitor`
- Retention: 90 days
- Actions: Check firewall, DNS, BGP routes, failover

**GPU Health**
- Error: `CRITICAL: GPU ECC errors detected`, `WARNING: GPU memory > 90%`
- Source: `dcgm-exporter`, `gpu-monitor`
- Retention: 90 days
- Actions: Alert SRE, schedule GPU replacement, workload migration

### Service Errors

**Database**
- Error: `CRITICAL: pg_stat_replication shows lag`, `WARNING: Slow query detected`
- Source: `postgres-exporter`, `application-logs`
- Retention: 90 days
- Actions: Check replication status, optimize query, scale vertically

**API Gateway**
- Error: `CRITICAL: All endpoints returning 5xx`, `WARNING: Error rate > 1%`
- Source: `caddy`, `api-gateway`, `oauth2-proxy`
- Retention: 30 days
- Actions: Check certificate expiry, TLS configuration, rate limiting rules

**Message Queue**
- Error: `CRITICAL: Redpanda down`, `WARNING: Consumer lag growing`
- Source: `redpanda-exporter`
- Retention: 30 days
- Actions: Check disk space, rebalance partitions, scale brokers

### Application Errors

**Authentication/Authorization**
- Error: `WARNING: OAuth2 callback failure`, `INFO: User login attempt from unusual location`
- Source: `oauth2-proxy`, `auth-logs`
- Retention: 90 days (compliance requirement)
- Actions: Review security rules, check IdP status, investigate origin

**Business Logic**
- Error: `WARNING: Transaction rollback`, `INFO: Validation error on input`
- Source: `application-logs`, control-plane
- Retention: 30 days
- Actions: Review logs with team, update validation rules, release fix

**Resource Exhaustion**
- Error: `CRITICAL: Connection pool exhausted`, `WARNING: Timeout on resource lock`
- Source: `connection-pool-monitor`, `application-logs`
- Retention: 30 days
- Actions: Increase pool size, profile connection usage, implement backpressure

### Infrastructure-as-Code Errors

**Terraform Drift**
- Error: `WARNING: Terraform plan shows drift`, `CRITICAL: Critical drift requiring intervention`
- Source: `drift-watchdog`, `terraform-plan`
- Retention: 90 days
- Actions: Review drift, reconcile, apply fix, post-mortem

**Git Sync Issues**
- Error: `WARNING: Git push rejected`, `CRITICAL: Deployment branch diverged`
- Source: `gitops-controller`, `ci-logs`
- Retention: 30 days
- Actions: Investigate merge conflicts, validate automation, replay

## Logging Levels

All application code should use one of these levels:

```
ERROR   → Use only for conditions requiring immediate human action
WARNING → Use for degradation, anomalies, or unusual states
INFO    → Use for state changes, transitions, milestones
DEBUG   → Use for diagnostic data (variable values, timing info, traces)
```

Microservices should emit structured JSON logs at INFO level during normal operation.

## Compliance & Retention

- **Authentication logs (OAuth, RBAC decisions)**: 90 days (SOC2/HIPAA compliance)
- **Database activity logs**: 90 days (audit trail)
- **API error logs**: 30 days
- **Infrastructure event logs**: 30 days
- **Application debug logs**: 7 days
- **Rotation**: Automated by Loki retention policies (configured in prometheus config)

## Querying the SLOG Taxonomy

Use the [Unified Observability Query Guide](./observability-query-guide.md) to construct Loki queries that span the taxonomy.

---

**Last Updated:** May 1, 2026  
**Owner:** Observability / Platform
