# P3 Issue #410: Performance Baseline Establishment
**Status**: IMPLEMENTATION STARTED - April 21, 2026  
**Priority**: P3 (Foundation for May 2026 optimization epic)  
**Effort**: 40 hours (May 1-7)  
**Dependencies**: None (read-only baseline collection)

---

## Objective
Establish comprehensive performance baselines across all infrastructure layers (network, storage, compute, containers) to:
1. Measure current state (April 2026)
2. Track improvements (May 2026 optimization work)
3. Validate SLO achievements
4. Create trending reports

---

## Baseline Categories

### 1. Network Layer Baselines

**Tests to Execute:**
```bash
# Test 1: Link Speed Verification
iperf3 -c 192.168.168.31 -t 60 -R
# Expected: 1 Gbps (1000 Mbps) for 1G NICs, 9+ Gbps for 10G NICs

# Test 2: NAS Throughput (NFS)
dd if=/dev/zero of=/mnt/nas/testfile bs=1M count=1000 conv=fdatasync
# Measure: MB/s written (baseline: ~125 MB/s expected)

# Test 3: NAS Read Performance
dd if=/mnt/nas/testfile of=/dev/null bs=1M count=1000
# Measure: MB/s read

# Test 4: Network Latency (ping)
ping -c 100 192.168.168.31
# Capture: min/avg/max/stddev latency (baseline: <1ms expected)

# Test 5: DNS Resolution Time
time nslookup code-server.kushnir.cloud
# Measure: Cloudflare tunnel + DNS resolution time
```

**Metrics to Store:**
- `network_iperf3_throughput_mbps` (primary ↔ replica)
- `network_nas_write_throughput_mbps`
- `network_nas_read_throughput_mbps`
- `network_ping_latency_ms` (p50/p95/p99)
- `network_dns_resolution_ms`

---

### 2. Storage Layer Baselines

**Tests to Execute:**
```bash
# Test 1: Local Docker Volume Speed
docker run --rm -v testvolume:/data alpine \
  dd if=/dev/zero of=/data/testfile bs=1M count=100 conv=fdatasync

# Test 2: NAS IOPS (if cache tier exists)
fio --name=randread --ioengine=libaio --iodepth=32 \
    --rw=randread --bs=4k --numjobs=4 --size=1G --runtime=60 \
    --filename=/mnt/nas/fiotest

# Test 3: PostgreSQL Backup/Restore Time
time pg_dump code_server_db > /tmp/backup.sql
time psql code_server_db < /tmp/backup.sql
# Measure: Backup duration, restore duration (database size)

# Test 4: Redis AOF Rewrite Time (if persistence enabled)
redis-cli BGREWRITEAOF
# Monitor: AOF file size, rewrite duration
```

**Metrics to Store:**
- `storage_local_volume_write_mbps`
- `storage_nas_iops_read` (4K random)
- `storage_nas_iops_write` (4K random)
- `storage_postgres_backup_seconds`
- `storage_postgres_restore_seconds`
- `storage_redis_aof_size_bytes`

---

### 3. Container Performance Baselines

**Tests to Execute:**
```bash
# Test 1: Code-server Startup Time
time docker-compose restart code-server
# Measure: Container start → ready-to-accept-connections (health check pass)

# Test 2: PostgreSQL Query Latency
psql -h 192.168.168.31 -U postgres -d code_server_db \
  -c "SELECT COUNT(*) FROM large_table; " \
  (repeat 100 times, measure p50/p95/p99)

# Test 3: Prometheus Query Latency (Grafana dashboard)
curl -s 'http://localhost:9090/api/v1/query_range' \
  --data-urlencode 'query=rate(container_cpu_usage_seconds_total[5m])' \
  --data-urlencode 'start=2026-04-01T00:00:00Z' \
  --data-urlencode 'end=2026-04-21T23:59:59Z' \
  --data-urlencode 'step=1m' \
  | time jq .

# Test 4: Grafana Dashboard Load Time
time curl -s http://localhost:3000/api/dashboards/uid/system-metrics > /dev/null

# Test 5: Redis Memory & CPU
redis-cli INFO memory
redis-cli INFO stats
# Capture: used_memory, ops_per_sec, evicted_keys_total
```

**Metrics to Store:**
- `container_code_server_startup_seconds`
- `container_postgres_query_latency_ms` (p50/p95/p99)
- `container_prometheus_query_latency_ms`
- `container_grafana_dashboard_load_ms`
- `container_redis_memory_used_bytes`
- `container_redis_ops_per_second`

---

### 4. Application Performance Baselines

**Tests to Execute:**
```bash
# Test 1: Code-server Page Load Time
ab -n 100 -c 10 http://localhost:8080/
# Measure: Requests/sec, avg response time, p99 response time

# Test 2: OAuth2-Proxy Login Flow Time
time curl -s -L -c /tmp/cookies.txt \
  'http://localhost:4180/oauth2/start?rd=http%3A%2F%2Flocalhost%3A8080%2F' \
  > /dev/null

# Test 3: Ollama Model Load Time (if deployed)
time curl -X POST http://localhost:11434/api/pull -d '{"name": "mistral"}' | jq .

# Test 4: Code-server WebSocket Latency
wscat -c ws://localhost:8080/socket.io \
  (measure round-trip time for 1000 messages)
```

**Metrics to Store:**
- `app_code_server_requests_per_second`
- `app_code_server_response_time_ms` (p50/p95/p99)
- `app_oauth2_proxy_login_time_seconds`
- `app_ollama_model_load_seconds`
- `app_websocket_latency_ms`

---

### 5. System Resource Baselines

**Tests to Execute:**
```bash
# Test 1: CPU Utilization (idle state)
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}"

# Test 2: Memory Utilization (all containers)
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}"

# Test 3: Disk Space Usage
df -h /mnt/nas
du -sh /var/lib/docker/volumes/*

# Test 4: Network Interface Stats
ip -s link show eth0
# Capture: RX/TX bytes, errors, dropped packets

# Test 5: Load Average
uptime
# Capture: 1min, 5min, 15min load
```

**Metrics to Store:**
- `system_cpu_utilization_percent` (per container)
- `system_memory_utilization_mb` (per container)
- `system_disk_space_available_gb` (/mnt/nas)
- `system_network_rx_bytes_per_second`
- `system_network_tx_bytes_per_second`
- `system_load_average_1min`

---

## Implementation Steps

### Step 1: Create Baseline Collection Script (May 1)
```bash
# scripts/collect-baselines.sh
#!/bin/bash

BASELINE_DIR="monitoring/baselines/$(date +%Y-%m-%d)"
mkdir -p "$BASELINE_DIR"

# Network tests
echo "=== Network Layer ===" | tee "$BASELINE_DIR/network.log"
iperf3 -c 192.168.168.31 -t 60 -R 2>&1 | tee -a "$BASELINE_DIR/network.log"
# ... (all network tests)

# Storage tests
echo "=== Storage Layer ===" | tee "$BASELINE_DIR/storage.log"
# ... (all storage tests)

# Container tests
echo "=== Container Layer ===" | tee "$BASELINE_DIR/container.log"
# ... (all container tests)

# System tests
echo "=== System Layer ===" | tee "$BASELINE_DIR/system.log"
# ... (all system tests)

# Export to Prometheus format
cat > "$BASELINE_DIR/metrics.txt" <<EOF
# HELP network_iperf3_throughput_mbps Network throughput measured via iperf3
# TYPE network_iperf3_throughput_mbps gauge
network_iperf3_throughput_mbps $(extract_iperf_result)

# ... (all metrics in Prometheus format)
EOF

echo "✅ Baseline collection complete: $BASELINE_DIR"
```

### Step 2: Create Prometheus Recording Rules (May 2)
```yaml
# monitoring/prometheus-baseline-rules.yml
groups:
  - name: baseline_metrics
    interval: 1m
    rules:
      - record: baseline:network_iperf3_throughput:gauge
        expr: network_iperf3_throughput_mbps
        labels:
          baseline: "april_2026"
      
      - record: baseline:storage_nas_write:gauge
        expr: storage_nas_write_throughput_mbps
        labels:
          baseline: "april_2026"
      
      - record: baseline:container_postgres_query_latency:gauge
        expr: container_postgres_query_latency_ms
        labels:
          baseline: "april_2026"
      
      # ... (all baseline metrics)
```

### Step 3: Create Grafana Dashboard (May 3-4)
**Dashboard**: `Baseline Metrics - April 2026`
- **Panels**:
  1. Network Throughput (baseline vs current)
  2. Storage IOPS (baseline vs current)
  3. Container Startup Times
  4. Query Latencies (p50/p95/p99)
  5. Resource Utilization (CPU, Memory, Disk)
  6. Application Response Times

### Step 4: Document Baseline Results (May 5)
Create `docs/BASELINE-APRIL-2026.md`:
```markdown
# April 2026 Performance Baselines

## Network Layer
- iperf3 throughput: XXX Mbps
- NAS write: XXX MB/s
- NAS read: XXX MB/s
- Ping latency: XXX ms (p50), XXX ms (p99)

## Storage Layer
- Local volume write: XXX MB/s
- NAS IOPS (read): XXX
- NAS IOPS (write): XXX
- PostgreSQL backup: XXX seconds
- PostgreSQL restore: XXX seconds

## Container Layer
- Code-server startup: XXX seconds
- PostgreSQL query latency: XXX ms (p99)
- Prometheus query latency: XXX ms
- Grafana dashboard load: XXX ms

## System Resources
- CPU utilization: XXX%
- Memory utilization: XXX MB
- Disk space available: XXX GB
- Load average (1min): XXX

## Conclusions & Next Steps
- Identifies bottlenecks (network, storage, queries)
- Prioritizes May optimization work
- Sets SLO targets for P3 work
```

---

## Success Criteria

✅ All baseline tests executed and results captured  
✅ Prometheus metrics ingested (recording rules active)  
✅ Grafana dashboard displaying baseline + current metrics  
✅ Documentation complete with analysis  
✅ Baseline data stored for trend analysis (May 2026)  
✅ SLO targets defined based on baselines  

---

## Files Created/Modified

```
scripts/
  └── collect-baselines.sh (NEW) - Comprehensive baseline collection

monitoring/
  ├── prometheus-baseline-rules.yml (NEW) - Recording rules
  ├── baselines/april-2026/ (NEW) - Baseline data directory
  │   ├── network.log
  │   ├── storage.log
  │   ├── container.log
  │   ├── system.log
  │   └── metrics.txt
  └── grafana-baseline-dashboard.json (NEW)

docs/
  └── BASELINE-APRIL-2026.md (NEW) - Results & analysis
```

---

## Timeline

| Date | Task | Owner |
|------|------|-------|
| May 1 | Network + Storage baselines | Infrastructure |
| May 2 | Container + System baselines | Infrastructure |
| May 3 | Prometheus recording rules | Observability |
| May 4 | Grafana dashboard | Observability |
| May 5 | Documentation + analysis | Infrastructure |

---

## Next Work (May 8+)

Once baselines are established, proceed with:
1. **Issue #408** - Network 10G Verification (uses baselines as reference)
2. **Issue #407** - NAS NVME Cache (measure improvement vs baseline)
3. **Issue #409** - Redis Sentinel (measure failover performance vs baseline)

---

**Status**: Ready for execution May 1, 2026  
**Owner**: Infrastructure Team  
**Last Updated**: April 21, 2026
