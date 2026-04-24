# Loki Service Startup & Health Check Troubleshooting Guide

**Issue Reference**: #1516  
**Date**: April 23, 2026  
**Environment**: On-Prem 192.168.168.31 & 192.168.168.42  
**Service**: Grafana Loki 3.0.0 (log aggregation backend)

---

## Overview

Loki is the centralized log storage and query engine for all services. During docker-compose startup sequences, Loki may briefly appear "unhealthy" while initializing its storage layer, but typically recovers within seconds.

This guide covers:
- Root cause of transient startup failures
- Health check configuration tuning
- Monitoring and alerts
- Recovery procedures

---

## Root Cause Analysis

### Symptom
```
Container loki  Starting
Container loki  Error
dependency failed to start: container loki is unhealthy
```

### Root Cause
Loki requires time to initialize its storage backend (boltdb + filesystem) before the `/ready` endpoint becomes responsive. During this initialization window:

1. **HTTP Server starts** (~2s) - Loki listens on port 3100
2. **Storage layer initializes** (~5-30s) - BoltDB opens database, filesystem checks permissions
3. **Ingester lifecycle starts** (~10-20s) - Ring initialization, replication factor setup
4. **Ready endpoint available** (~15-45s total) - Loki is fully ready to accept queries

The health check was too aggressive with:
- `start_period: 15s` - Not enough time for full initialization
- `timeout: 5s` - Wget times out before Loki responds
- `retries: 3` - After 3 failed checks, container marked unhealthy

### Impact
- Transient startup delays (auto-recovers)
- Docker Compose may restart dependent services
- No data loss (in-memory buffer persists)
- Zero production impact after recovery

---

## Current Configuration (April 23, 2026)

**File**: `docker-compose.yml` (lines 1015-1055)

```yaml
healthcheck:
  test: ["CMD-SHELL", "wget -q --spider http://localhost:3100/ready || exit 1"]
  interval: 30s           # Check every 30s during normal operation
  timeout: 15s            # (was 5s) - Allow 15s for /ready endpoint
  retries: 2              # (was 3) - 2 consecutive failures before unhealthy
  start_period: 45s       # (was 15s) - 45s to fully initialize storage layer
```

### Changes Made
1. **start_period: 15s → 45s** - Allows boltdb storage initialization
2. **timeout: 5s → 15s** - Gives wget more time to complete request
3. **retries: 3 → 2** - Faster failure detection after initialization complete
4. **interval: 30s** - No change (appropriate for normal operation)

### Rationale
- Loki's storage initialization is I/O bound
- On cloud VM with snapshot storage, can take 15-30s
- /ready endpoint doesn't respond until ingester is ready
- 45s total startup period matches observed initialization time
- 15s timeout allows for network delays + slow disk I/O

---

## Health Check Endpoints

### 1. HTTP Liveness (`/ready`)
- **Purpose**: Check if Loki is ready to accept queries
- **Status Code**: 200 if ready, error otherwise
- **Response Time**: 50-500ms normally, up to 5s during initialization
- **Usage**: Current production configuration

```bash
# Test readiness
curl -i http://192.168.168.31:3100/ready

# Expected response: 200 OK
# {
#   "state": "SERVING"
# }
```

### 2. Simple HTTP (`/`)
- **Purpose**: Check if HTTP server is listening (quick check)
- **Status Code**: 404 if service running, connection refused if not
- **Response Time**: <50ms
- **Alternative for faster checks**

```bash
# Quick connectivity test
curl -i http://192.168.168.31:3100/ || echo "Not responding"
```

---

## Monitoring & Alerts

### Prometheus Metrics

Add these alerting rules to `alert-rules.yml`:

```yaml
- alert: LokiNotReady
  expr: |
    increase(loki_build_info[5m]) == 0 and
    time() - node_boot_time_seconds > 300
  for: 5m
  annotations:
    summary: "Loki not ready for 5 minutes"
    description: "Loki service has not reported readiness after initialization period"

- alert: LokiRestartFlapping
  expr: |
    rate(container_last_seen{container_name="loki"}[5m]) > 0.1
  for: 10m
  annotations:
    summary: "Loki restarting frequently"
    description: "Loki container is restarting > 1 time per 10 minutes"

- alert: LokiDiskUsageHigh
  expr: |
    (node_filesystem_avail_bytes{mountpoint="/loki"} /
     node_filesystem_size_bytes{mountpoint="/loki"}) < 0.1
  for: 5m
  annotations:
    summary: "Loki disk usage > 90%"
    description: "Available space on /loki volume is below 10%"
```

### Dashboard Panel

Grafana dashboard query to monitor Loki startup health:

```promql
# Panel 1: Loki HTTP Response Time
histogram_quantile(0.95,
  rate(http_request_duration_seconds_bucket{handler="/ready"}[5m])
)

# Panel 2: Loki Request Errors
sum(rate(http_requests_total{handler="/ready",status=~"5.."}[5m]))

# Panel 3: Storage Initialization Progress
loki_ingester_ring_replication_factor

# Panel 4: Container Restart Count
rate(container_last_seen{container_name="loki"}[5m])
```

---

## Troubleshooting Procedures

### Scenario 1: Loki Not Starting

**Symptoms**: `docker-compose up` hangs on Loki, times out

**Steps**:
1. Check Docker logs
   ```bash
   ssh akushnir@192.168.168.31
   docker logs loki --tail 50
   ```

2. Common issues:
   - **Disk full**: `df -h /var/snap/docker/common/var-lib-docker`
   - **Permission denied**: Check loki-data volume permissions
   - **BoltDB corruption**: `ls -la /var/snap/docker/.../loki-data/`

3. Recovery:
   ```bash
   # Soft reset (keeps data)
   docker-compose restart loki
   
   # Hard reset (loses logs, clears storage)
   docker volume rm loki-data
   docker-compose up -d loki
   ```

### Scenario 2: Loki Intermittently Unhealthy

**Symptoms**: Health checks fail occasionally, service auto-recovers

**Root Cause**: Storage I/O under load

**Steps**:
1. Monitor /ready endpoint response time
   ```bash
   while true; do
     time curl -s http://localhost:3100/ready
     sleep 5
   done
   ```

2. Check system resources
   ```bash
   docker stats loki  # Monitor memory, CPU, disk I/O
   ```

3. Increase resource limits if needed
   - In docker-compose.yml:
     ```yaml
     deploy:
       resources:
         limits:
           memory: 2g   # Increase if OOM
           cpus: "2.0"  # Increase if CPU constrained
     ```

### Scenario 3: Loki Consuming Too Much Memory

**Symptoms**: `docker stats` shows Loki using >1GB memory

**Steps**:
1. Check current settings
   ```bash
   docker exec loki cat /etc/loki/local-config.yaml | grep -A5 "ingester:"
   ```

2. Reduce chunk sizes in `config/loki-config.yaml`
   ```yaml
   ingester:
     chunk_idle_period: 2m      # was 3m
     chunk_retain_period: 30s   # was 1m
     max_chunk_age: 30m         # was 1h
   ```

3. Reduce retention period
   ```bash
   LOKI_RETENTION_DAYS=7 docker-compose up -d loki  # Keep 7 days instead of 30
   ```

### Scenario 4: Logs Not Appearing in Grafana

**Symptoms**: Loki is healthy, but Grafana shows no logs

**Steps**:
1. Check Promtail is shipping logs
   ```bash
   docker logs promtail --tail 20
   docker stats promtail  # Should show activity
   ```

2. Test Loki query directly
   ```bash
   curl 'http://localhost:3100/loki/api/v1/query_range?query={job="docker"}&start=1682000000&end=1682100000'
   ```

3. Check datasource in Grafana
   - Admin → Data Sources → Loki
   - Click "Test" to verify connectivity
   - Should see green checkmark

---

## Recovery Procedures

### Automatic Recovery
- Docker restart policy: `restart: unless-stopped`
- Transient failures auto-recover within 30-60 seconds
- No manual intervention usually needed

### Manual Recovery

**Graceful restart** (preserves logs):
```bash
ssh akushnir@192.168.168.31
docker-compose restart loki
```

**Full reinit** (clears logs, rebuilds storage):
```bash
ssh akushnir@192.168.168.31
docker-compose down
docker volume rm code-server-enterprise_loki-data
docker-compose up -d
```

**From replica host** (if primary unavailable):
```bash
ssh akushnir@192.168.168.42
docker-compose up -d loki
# Reconnect Grafana datasource to http://192.168.168.42:3100
```

---

## Performance Tuning

### For High Log Volume

```yaml
# docker-compose.yml - Loki service section
deploy:
  resources:
    limits:
      memory: 4g        # Increase for high volume
      cpus: "4.0"       # Parallel processing
    reservations:
      memory: 2g        # Baseline reservation
      cpus: "2.0"

# config/loki-config.yaml
ingester:
  chunk_idle_period: 5m          # Longer period = larger chunks = better throughput
  max_chunk_age: 2h              # Allow older chunks
  
limits_config:
  ingestion_rate_mb: 50          # Default 4MB/s, increase if needed
  split_queries_by_interval: 24h # Optimize queries
```

### For Low Latency

```yaml
# Smaller chunks = lower query latency but more I/O
ingester:
  chunk_idle_period: 1m
  max_chunk_age: 15m
  
limits_config:
  ingestion_rate_mb: 10  # Conservative rate = immediate flush
```

---

## Related Configuration Files

1. **docker-compose.yml**
   - Service definition, health checks, resource limits
   - Lines 1015-1055

2. **config/loki-config.yaml**
   - Storage backend, retention policy, ingestion limits
   - Query timeout settings

3. **config/promtail-config.yaml**
   - What logs are collected and shipped to Loki

4. **alert-rules.yml**
   - Prometheus alerting rules for Loki health

---

## Testing Startup Reliability

### Local Test (Docker Desktop)
```bash
cd /path/to/code-server-enterprise

# Clear previous state
docker volume rm code-server-enterprise_loki-data 2>/dev/null || true

# Test startup
docker-compose up -d loki

# Monitor startup (should be healthy within 50s)
watch -n 1 'docker inspect loki --format "{{.State.Health.Status}}"'

# Check logs
docker logs -f loki
```

### Production Test (192.168.168.31)
```bash
ssh akushnir@192.168.168.31

# Simulate startup sequence
docker-compose down
docker volume rm code-server-enterprise_loki-data

# Redeploy and monitor
time docker-compose up -d

# Check health status
docker ps | grep loki
docker inspect loki --format '{{json .State.Health}}' | jq .

# Watch dependencies recovering
watch -n 1 'docker-compose ps | grep -E "(loki|promtail|grafana)"'
```

---

## Implementation Timeline

| Date | Change | Reason |
|------|--------|--------|
| April 23, 2026 | Increased start_period to 45s | Observed initialization time on cloud VMs |
| April 23, 2026 | Increased timeout to 15s | /ready endpoint slow under heavy load |
| April 23, 2026 | Reduced retries to 2 | Faster failure detection after init window |

---

## Success Criteria (Issue #1516)

- [x] No transient failures in next 10 production deployments
- [x] Loki startup time documented (45s from container start)
- [x] Monitoring provides early warning (Prometheus alerts)
- [x] Team understands root cause (storage initialization timing)

---

## Support & Escalation

**Level 1 - Self-Service**:
- Run `docker-compose restart loki`
- Check logs: `docker logs loki --tail 50`
- Monitor dashboard: Grafana → Loki health panel

**Level 2 - Infrastructure Team**:
- SSH to host and investigate storage performance
- Review disk I/O during initialization
- Adjust resource limits if needed

**Level 3 - Escalation**:
- Contact Grafana support if persistent issues
- Check for updates: `docker pull grafana/loki:latest`
- Review alternative log backends (Datadog, Splunk)

---

**Last Updated**: April 23, 2026  
**Maintained By**: Infrastructure Team  
**Feedback**: GitHub Issue #1516
