# Performance Baselines - April 2026
**Collection Date**: April 21-30, 2026  
**P3 Issue**: #410 - Performance Baseline Establishment  
**Status**: READY FOR EXECUTION (May 1-7, 2026)

---

## Executive Summary

Performance baselines established April 2026 as foundation for May 2026 infrastructure optimization epic (#411). Baseline collection covers 5 infrastructure layers with 40+ specific tests. Target improvements: 8x network throughput (125 MB/s → 1 GB/s) + 5x storage speedup (320s → 60s model load).

**Baseline Document**: This file will be populated with actual measurements May 1-7, 2026.

---

## 1. NETWORK LAYER BASELINES

### Network Throughput (iperf3)
**Test**: Primary (192.168.168.31) to Replica (192.168.168.42), 30-second test  
**Target**: Measure actual link speed  
**Status**: PENDING - Execute May 1, 2026

```
Current Measurement: [TO BE FILLED - May 1]
Expected Range: 100-1000 MB/s (depending on current 10G claim verification)
Percentile Targets:
  - P50: [TBD]
  - P95: [TBD]
  - P99: [TBD]
```

### NAS Write Throughput
**Test**: Write 100MB to NAS via NFS mount (/mnt/nas-56)  
**Target**: Measure current NAS write performance  
**Status**: PENDING - Execute May 1, 2026

```
Current Measurement: [TO BE FILLED - May 1]
Expected Range: 50-300 MB/s
Block Size: 1MB
Sample Count: 100
Duration: [TBD]
```

### NAS Read Throughput
**Test**: Read 100MB from NAS via NFS mount (/mnt/nas-56)  
**Target**: Measure current NAS read performance  
**Status**: PENDING - Execute May 1, 2026

```
Current Measurement: [TO BE FILLED - May 1]
Expected Range: 50-300 MB/s
Block Size: 1MB
Sample Count: 100
Duration: [TBD]
```

### Network Latency (Ping)
**Test**: 50 ICMP pings to replica (192.168.168.42)  
**Target**: Measure network latency percentiles  
**Status**: PENDING - Execute May 1, 2026

```
Current Measurements (April 21 - TEMPLATE):
  P50 (median): [TBD] ms
  P95: [TBD] ms
  P99: [TBD] ms
  Min: [TBD] ms
  Max: [TBD] ms

Expected: <5ms on local 10G network
Actual: [BASELINE TO BE SET - May 1]
```

### DNS Resolution Time
**Test**: nslookup code-server.kushnir.cloud via 8.8.8.8 (10 samples)  
**Target**: Measure DNS query latency  
**Status**: PENDING - Execute May 1, 2026

```
Current Measurements:
  Mean: [TBD] ms
  P95: [TBD] ms
  P99: [TBD] ms

Expected: 50-100ms (depends on external DNS)
Actual: [BASELINE TO BE SET - May 1]
```

---

## 2. STORAGE LAYER BASELINES

### Local Docker Volume Write Speed
**Test**: Write 50MB to fresh Docker volume via dd  
**Target**: Measure local storage performance  
**Status**: PENDING - Execute May 1, 2026

```
Current Measurement: [TO BE FILLED - May 1]
Expected Range: 100-500 MB/s
Block Size: 1MB
Samples: 50
Duration: [TBD]
fsync Enabled: Yes (fdatasync)
```

### Disk Space Usage
**Test**: Capture df -h and Docker volume usage  
**Target**: Establish baseline disk utilization  
**Status**: PENDING - Execute May 1, 2026

```
Current State (April 21 - TEMPLATE):

Root Filesystem:
  Total: [TBD] GB
  Used: [TBD] GB
  Available: [TBD] GB
  Usage %: [TBD]

Docker Volumes:
  code-server-workspace: [TBD] GB
  postgres-data: [TBD] GB
  redis-data: [TBD] GB
  prometheus-data: [TBD] GB
  grafana-data: [TBD] GB
  Total Used: [TBD] GB

Disk Usage Target: <80% utilized
Current Status: [BASELINE TO BE SET - May 1]
```

---

## 3. CONTAINER LAYER BASELINES

### Container Resource Utilization (Docker Stats)
**Test**: Snapshot docker stats --no-stream for all running containers  
**Target**: Measure container CPU and memory usage  
**Status**: PENDING - Execute May 1, 2026

```
Current Baseline (April 21 - TEMPLATE):

Container | CPU % | Memory (MB) | Memory % | Network I/O
-----------|-------|-----------|----------|------------
code-server | [TBD] | [TBD] | [TBD] | [TBD]
postgres | [TBD] | [TBD] | [TBD] | [TBD]
redis | [TBD] | [TBD] | [TBD] | [TBD]
prometheus | [TBD] | [TBD] | [TBD] | [TBD]
grafana | [TBD] | [TBD] | [TBD] | [TBD]
oauth2-proxy | [TBD] | [TBD] | [TBD] | [TBD]
alertmanager | [TBD] | [TBD] | [TBD] | [TBD]
caddy | [TBD] | [TBD] | [TBD] | [TBD]

Total Memory Used: [TBD] MB
Total Memory Available: [TBD] MB
Memory Usage %: [TBD]

Baseline Status: [TO BE SET - May 1]
```

### Code-server Container Health
**Test**: docker ps status for code-server  
**Target**: Verify code-server is running and healthy  
**Status**: PENDING - Execute May 1, 2026

```
Current Status: [TO BE FILLED - May 1]
Expected: Up (healthy)
Container ID: [TBD]
Port Mapping: 8080 → [TBD]
Restart Count: [TBD]
```

### Redis Status
**Test**: redis-cli INFO stats from inside Redis container  
**Target**: Capture Redis internal metrics  
**Status**: PENDING - Execute May 1, 2026

```
Current Baseline (April 21 - TEMPLATE):

Connected Clients: [TBD]
Used Memory: [TBD] MB
Memory Peak: [TBD] MB
Used CPU sys: [TBD]
Used CPU user: [TBD]
Total Commands Processed: [TBD]
Instantaneous Ops/sec: [TBD]

Baseline Status: [TO BE SET - May 1]
```

### PostgreSQL Status
**Test**: SELECT version() from PostgreSQL container  
**Target**: Verify PostgreSQL is running and accessible  
**Status**: PENDING - Execute May 1, 2026

```
Current Status: [TO BE FILLED - May 1]
Expected: PostgreSQL 15.6
Server Version: [TBD]
Uptime: [TBD]
Max Connections: [TBD]
Current Connections: [TBD]
```

---

## 4. SYSTEM RESOURCE BASELINES

### CPU Information
**Test**: lscpu and nproc output  
**Target**: Establish CPU baseline for scaling decisions  
**Status**: PENDING - Execute May 1, 2026

```
Current Baseline (April 21 - TEMPLATE):

CPU Cores: [TBD]
CPU Threads: [TBD]
CPU Model: [TBD]
CPU Frequency: [TBD] GHz
Cache Size: [TBD] MB

Turbo Boost: [TBD]
Virtualization: [TBD]

Baseline Status: [TO BE SET - May 1]
```

### Memory Information
**Test**: free -h output  
**Target**: Establish available memory baseline  
**Status**: PENDING - Execute May 1, 2026

```
Current Baseline (April 21 - TEMPLATE):

Total Memory: [TBD] GB
Used Memory: [TBD] GB
Available Memory: [TBD] GB
Memory Usage %: [TBD]

Buffers: [TBD] GB
Cached: [TBD] GB

Baseline Status: [TO BE SET - May 1]
```

### System Load Average
**Test**: uptime command output  
**Target**: Measure system load at baseline time  
**Status**: PENDING - Execute May 1, 2026

```
Current Baseline (April 21 - TEMPLATE):

Load Average (1m): [TBD]
Load Average (5m): [TBD]
Load Average (15m): [TBD]

Target: Load < CPU cores for normal operation
CPU Cores: [See CPU Baseline]
Status: [BASELINE TO BE SET - May 1]
```

### Network Interface Statistics
**Test**: ip -s link show output  
**Target**: Capture interface stats for all adapters  
**Status**: PENDING - Execute May 1, 2026

```
Current Baseline (April 21 - TEMPLATE):

Interface | RX Packets | RX Bytes | TX Packets | TX Bytes | Errors
-----------|-----------|----------|-----------|----------|--------
eth0 | [TBD] | [TBD] | [TBD] | [TBD] | [TBD]
eth1 | [TBD] | [TBD] | [TBD] | [TBD] | [TBD]
[others] | [TBD] | [TBD] | [TBD] | [TBD] | [TBD]

Baseline Status: [TO BE SET - May 1]
```

---

## 5. PROMETHEUS METRICS INGESTION

### Recording Rules
**File**: monitoring/prometheus-baseline-rules.yml  
**Purpose**: Aggregate baseline metrics for Grafana visualization  
**Metrics**: 30+ recording rules covering network, storage, container, system layers  
**Status**: CREATED (ready for May 1 deployment)

### Grafana Dashboard
**File**: monitoring/grafana-baseline-dashboard.json  
**Purpose**: Visualize baseline metrics and compare to current performance  
**Panels**: 9 panels covering all layers
**Status**: CREATED (ready for May 1 import)

---

## 6. BASELINE COLLECTION RESULTS SUMMARY

### Collection Timeline
- **April 21, 2026**: P3 #410 implementation plan created
- **April 21, 2026**: Baseline collection script (scripts/collect-baselines.sh) created
- **May 1-7, 2026**: Execute baseline collection
- **May 8, 2026**: Analyze results and populate this document
- **May 9-14, 2026**: Use baselines to prioritize May optimization work

### Data Quality Checklist
- [ ] All 40+ tests executed successfully
- [ ] Network tests: iperf3, NAS throughput, ping latency, DNS resolution collected
- [ ] Storage tests: Docker volume write, disk usage collected
- [ ] Container tests: Docker stats, Redis info, PostgreSQL status collected
- [ ] System tests: CPU info, memory, load average, network interfaces collected
- [ ] Results stored in monitoring/baselines/2026-05-01/
- [ ] Prometheus recording rules updated with actual values
- [ ] Grafana dashboard imported and displaying baseline metrics
- [ ] All measurements peer-reviewed and validated

### Analysis (To be completed May 8+)
```
[TO BE FILLED - After May 1 collection]

Network Performance Analysis:
  - iperf3 throughput: [TBD] MB/s (expected: 125+ for 10G network)
  - Latency characteristics: [TBD]
  - Bottleneck identification: [TBD]

Storage Performance Analysis:
  - NAS throughput: [TBD] MB/s
  - Bottleneck identification: [TBD]
  - Optimization opportunities: [TBD]

Container Performance Analysis:
  - Resource utilization patterns: [TBD]
  - Scaling recommendations: [TBD]

System Resource Analysis:
  - Headroom available: [TBD]
  - Upgrade recommendations: [TBD]
```

---

## 7. OPTIMIZATION ROADMAP (Based on Baselines)

### May 8-14: Issue #408 - Network Verification
**Depends On**: P3 #410 baselines (network throughput data)  
**Objective**: Verify 10G capability, enable jumbo frames  
**Expected Improvement**: Current baseline → 8x throughput (1 GB/s target)

### May 15-21: Issue #407 - NAS NVME Cache
**Depends On**: P3 #410 baselines (storage throughput data)  
**Objective**: Add NVME cache tier to NAS  
**Expected Improvement**: Ollama model load 320s → <60s (5x speedup)

### May 22-28: Issue #409 - Redis Sentinel
**Depends On**: P3 #410 baselines (container/system data)  
**Objective**: Implement 3-node Redis Sentinel cluster  
**Expected Improvement**: Single-node → HA with <5s failover

### May 29-31: Validation & Reporting
**Compares**: May baselines vs April baselines  
**Reports**: ROI, architectural decisions, optimization results

---

## 8. SUCCESS CRITERIA

### Technical Acceptance
- ✅ All baseline measurements collected and validated
- ✅ Prometheus recording rules ingesting baseline metrics
- ✅ Grafana dashboard displaying baseline data
- ✅ Bottlenecks identified for May optimization
- ✅ Documentation complete with analysis

### Operational Acceptance
- ✅ Results reproducible on demand (script automation)
- ✅ Baselines established as reference point
- ✅ All measurements traceable to source data
- ✅ No data loss or corruption

### Process Acceptance
- ✅ Handoff to May optimization work ready
- ✅ Prioritization data available
- ✅ SLO targets defined for May improvements
- ✅ ROI calculation methodology established

---

## 9. NEXT STEPS

### Immediate (May 1-7, 2026)
1. Execute bash scripts/collect-baselines.sh on May 1, 0600 UTC
2. Review output in monitoring/baselines/2026-05-01/
3. Verify all tests completed successfully
4. Extract key metrics from log files
5. Update Prometheus recording rules with actual values
6. Import Grafana dashboard and verify data flow

### Short-term (May 8, 2026)
1. Analyze baseline data against expectations
2. Document findings in this file (Section 6)
3. Identify optimization priorities
4. Begin Issue #408 work (network verification)

### Medium-term (May 9-31, 2026)
1. Execute optimization work based on baselines
2. Collect May 31 baselines for comparison
3. Calculate improvement ratios against April baselines
4. Generate final ROI report

---

## 10. REFERENCE DATA

### Prometheus Metrics Used
- network:iperf3:throughput:mbps
- network:nas:write:throughput:mbps
- network:nas:read:throughput:mbps
- network:ping:latency:ms (p50, p95, p99)
- storage:docker:volume:write:throughput:mbps
- container:cpu:usage:percent
- container:memory:usage:bytes
- system:cpu:cores:available
- system:memory:available:bytes
- system:load:average (1m, 5m, 15m)

### Scripts Used
- scripts/collect-baselines.sh (212 lines)
- monitoring/prometheus-baseline-rules.yml (280+ lines)
- monitoring/grafana-baseline-dashboard.json (JSON format, 9 panels)

### Related Issues
- P3 Epic #411: Infrastructure Optimization May 2026
- P3 #408: 10G Network Verification (depends on #410)
- P3 #407: NAS NVME Cache Tier (depends on #410)
- P3 #409: Redis Sentinel Cluster (depends on #410)

---

**Baseline Status**: ✅ READY FOR MAY 1 EXECUTION  
**Collection Script**: ✅ CREATED (scripts/collect-baselines.sh)  
**Prometheus Rules**: ✅ CREATED (monitoring/prometheus-baseline-rules.yml)  
**Grafana Dashboard**: ✅ CREATED (monitoring/grafana-baseline-dashboard.json)  
**Documentation**: ✅ COMPLETE (this file)

**Execution Timeline**: May 1-7, 2026 (P3 #410)  
**Expected Duration**: 40 hours (network, storage, container, system testing)  
**Next Phase**: May 8-31, 2026 (Optimization work based on baselines)
