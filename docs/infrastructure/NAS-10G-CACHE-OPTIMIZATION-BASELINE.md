# NAS/10G Network Performance Baseline and Optimization Targets

**Purpose**: NAS/10G Network Performance Baseline and Optimization Targets — reference and operational document.

> Issue: [#895](https://github.com/kushin77/code-server/issues/895)
> Date: 2026-04-20
> Status: Baseline & targets defined

## Executive Summary

This document establishes the baseline performance profile for NAS-backed storage and 10G network connectivity on the on-prem deployment (192.168.168.31/.42). It defines measurable targets for throughput, latency, and cache efficiency, and provides the measurement methodology for detecting regressions.

---

## 1. Network Performance Baseline — 10G Interface

### 1.1 Target Metrics

| Metric | Target (P95) | Measurement Method |
|--------|---------|-------------------|
| Single-stream throughput | ≥ 900 Mbps (90% of 1Gbps link) | `iperf3` between .31 and .42 |
| Multi-stream throughput | ≥ 2.0 Gbps (aggregate, 4 streams) | `iperf3 -P 4` |
| Round-trip latency | ≤ 1ms | `ping` between hosts, 1000 samples |
| Packet loss | < 0.1% | `iperf3` + loss reporting |
| TCP retransmits | < 0.5% | `netstat -s` before/after test |
| Interface errors | 0 | `ethtool -S eth0` (no RX/TX errors) |

### 1.2 Current State (Pre-Optimization)

To be populated after first baseline run:

```bash
# Test command:
bash scripts/ops/benchmark-10g-network.sh
```

### 1.3 Configuration Checks

**MTU (Maximum Transmission Unit)**
- Current: `ip link show eth0 | grep mtu`
- Target: 1500 bytes (standard Ethernet), or 9000 (jumbo frames if switch supports)
- Tuning: `ip link set dev eth0 mtu 9000` (requires switch validation)

**TCP Window Scaling**
```bash
cat /proc/sys/net/ipv4/tcp_window_scaling  # should be 1 (enabled)
```

**TCP Congestion Control**
```bash
cat /proc/sys/net/ipv4/tcp_congestion_control  # bbr recommended for long pipes
echo "bbr" | sudo tee /proc/sys/net/ipv4/tcp_default_congestion_control
```

---

## 2. NAS Performance Baseline — NFSv4

### 2.1 Target Metrics

| Metric | Target (P95) | Measurement Method |
|--------|---------|-------------------|
| Single-file read throughput | ≥ 800 Mbps | `dd if=<nfs-file> of=/dev/null bs=1M` |
| Single-file write throughput | ≥ 700 Mbps | `dd if=/dev/zero of=<nfs-file> bs=1M` |
| Small-file read latency | ≤ 5ms | `stat` 1000 files, measure total time |
| Small-file write latency | ≤ 10ms | `touch` 1000 files, measure total time |
| Directory listing (10k files) | ≤ 500ms | `ls -l` on large directory |
| NFS Mount response time | ≤ 2s | time `mount -t nfs` command |
| Stale NFS handle count | 0/day | monitor `mount -t nfs` over 24h |

### 2.2 Current State (Pre-Optimization)

To be populated after first baseline run:

```bash
# Test command:
bash scripts/ops/benchmark-nfs-performance.sh
```

### 2.3 NFS Configuration Tuning

**Mount Options** (in `/etc/fstab` or compose volume spec)
```
mount -t nfs -o vers=4.1,rsize=131072,wsize=131072,hard,timeo=600,retrans=2 nas.internal:/export /mnt/nfs
```

**Key parameters:**
- `vers=4.1`: NFSv4.1 preferred (pNFS, session support)
- `rsize=131072, wsize=131072`: 128KB I/O chunks (larger than default 4KB)
- `hard`: Fail if server unresponsive, rather than returning error (data integrity)
- `timeo=600`: 60s timeout before retry (prevents hanging)
- `retrans=2`: Retry 2x before giving up
- Remove `softreval=180` if present (can cause silent data loss)

**Server-side NFS exports** (`/etc/exports` on NAS):
```
/export *.local(rw,sync,no_subtree_check,fsid=0,crossmnt)
```

---

## 3. Cache Efficiency Targets

### 3.1 Artifact Cache (Docker layer cache, npm/pnpm lock files)

| Target | Baseline | Post-Optimization |
|--------|----------|-------------------|
| Cache hit ratio | 40% | ≥ 75% |
| Build time (warm cache) | TBD | ≤ 60s (node rebuild) |
| Build time (cold cache) | TBD | ≤ 5min (full monorepo build) |
| Cache storage used | TBD | ≤ 50GB (enforced quota) |

**Measurement:**
```bash
# pnpm install with cache stats
time pnpm install --frozen-lockfile
pnpm store status  # cache hit ratio

# Docker build with BuildKit cache export
DOCKER_BUILDKIT=1 docker build --cache-from=type=local,src=/tmp/docker-cache -o type=local,dest=/tmp/docker-cache .
```

### 3.2 Workspace Metadata Cache (code-server project files, .git)

| Target | Baseline | Post-Optimization |
|--------|----------|-------------------|
| `.git` object cache hit | TBD | ≥ 80% |
| LSP index rebuild time | TBD | ≤ 10s on large file edit |
| File watch latency | TBD | ≤ 500ms |

**Tuning:**
- Enable `git gc` on the workspace NFS mount (periodic pack of loose objects)
- Increase inotify limit: `sysctl fs.inotify.max_user_watches=524288`
- Consider persistent Redis cache for code-server metadata

---

## 4. Measurement Methodology

### 4.1 Baseline Run (Week 1)

Execute all benchmark scripts and record:
- Host metadata (kernel, NAS firmware, NIC driver version)
- Network topology (switch config, cable type)
- Load during benchmark (system utilization, competing workloads)
- Ambient conditions (room temp, power state, UPS status)

```bash
# Run full baseline suite
bash scripts/ops/benchmark-10g-network.sh        > artifacts/triage/baseline-10g.json
bash scripts/ops/benchmark-nfs-performance.sh   > artifacts/triage/baseline-nfs.json
bash scripts/ops/benchmark-build-cache.sh       > artifacts/triage/baseline-cache.json
bash scripts/ops/benchmark-workspace-metadata.sh > artifacts/triage/baseline-metadata.json
```

### 4.2 Regression Detection (Continuous)

Add to Prometheus scrape targets:
```yaml
  - job_name: 'infrastructure-performance'
    scrape_interval: 1h
    metrics_path: '/metrics'
    static_configs:
      - targets: ['primary.internal:9100']  # node_exporter
        labels:
          - host: primary
  - job_name: 'nfs-exporter'
    static_configs:
      - targets: ['nas.internal:9100']
```

**Alert conditions in Prometheus:**
```yaml
groups:
  - name: infrastructure-alerts
    rules:
      - alert: NASReadThroughputDegraded
        expr: nfs_read_throughput_bytes < 800e6  # < 800 Mbps
        for: 5m
      - alert: NetworkLatencyHigh
        expr: ping_latency_seconds > 0.001  # > 1ms
        for: 5m
      - alert: DiskIoWaitHigh
        expr: node_disk_io_time_seconds_total > 50  # > 50% util
        for: 10m
```

### 4.3 Post-Optimization Validation

After each tuning change:
1. Run benchmark suite again
2. Compare to baseline using `diff-json` or custom script
3. Record delta (% improvement or regression)
4. Add results to this document as "Post-Optimization"
5. If regression: revert change and document why it failed

```bash
# Diff results
jq -s '.[0] as $baseline | .[1] | with_entries(
  .value |= {
    baseline: $baseline[.key],
    current: .value,
    delta_pct: (((.value - $baseline[.key]) / $baseline[.key]) * 100)
  }
) | add' \
  artifacts/triage/baseline-nfs.json \
  artifacts/triage/current-nfs.json
```

---

## 5. Implementation Roadmap

| Phase | Owner | Target Date | Deliverables |
|-------|-------|-------------|--------------|
| **Phase 1: Baseline** | @kushin77 | April 25, 2026 | JSON benchmark results in `artifacts/triage/` |
| **Phase 2: Analysis** | @kushin77 | April 27, 2026 | Bottleneck report + tuning plan |
| **Phase 3: Tuning** | @kushin77 | May 5, 2026 | Applied configs on primary + validation |
| **Phase 4: Replication** | DevOps | May 10, 2026 | Tuning applied to replica + both validated |
| **Phase 5: Monitoring** | @kushin77 | May 12, 2026 | Prometheus alerts + dashboard live |

---

## 6. Success Criteria

All metrics from Section 1–3 must meet targets with sustained measurement over 2 weeks:

- [ ] 10G network sustained at ≥ 900 Mbps P95 single-stream
- [ ] NFS read throughput ≥ 800 Mbps P95
- [ ] Build cache hit ratio ≥ 75%
- [ ] Zero NFS stale handle events
- [ ] Regression alerts configured + validated
- [ ] Tuning procedure documented in ops runbook

---

## 7. Appendix: Benchmark Scripts

All scripts referenced in this document are located in `scripts/ops/`:

- `benchmark-10g-network.sh` — Network throughput/latency via iperf3
- `benchmark-nfs-performance.sh` — NAS read/write throughput and latency
- `benchmark-build-cache.sh` — pnpm/Docker build cache hit ratio
- `benchmark-workspace-metadata.sh` — .git and LSP metadata performance