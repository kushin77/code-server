# NAS Performance Baselines and Optimization

## Issue #1536 - Networking, DNS & Performance Epic

### Purpose
Establish performance baselines for network-attached storage (NAS) access patterns and optimize infrastructure for maximum throughput and latency.

## Architecture Overview

### Storage Topology
- **NAS Host**: 192.168.168.56 (eiq-nas)
- **Primary Host**: 192.168.168.31 (code-server deployment)
- **Replica Host**: 192.168.168.42 (failover deployment)
- **Mount Point**: `/mnt/nas` (Linux), `Z:` (Windows via CIFS)
- **Protocol**: SMB3 over CIFS (TCP port 445)
- **Network**: 1GbE LAN (100 Mbps baseline, 10GbE capable)

### NAS Directory Structure
```
/nas/persistent/paperclip/data/     # PostgreSQL + app data (primary)
/nas/hot/paperclip-docker/          # Docker images, cache
/nas/cold/paperclip-backups/        # Backups, archives
```

## Performance Baselines

### Network Throughput

#### Expected Metrics (1GbE)
- **Sustained throughput**: 80-100 Mbps
- **Burst throughput**: Up to 110 Mbps (utilization peaks)
- **Latency**: <5ms round-trip average
- **Jitter**: <2ms standard deviation

#### Expected Metrics (10GbE)
- **Sustained throughput**: 900-1200 Mbps
- **Burst throughput**: Up to 1400 Mbps
- **Latency**: <1ms round-trip average
- **Jitter**: <0.5ms standard deviation

#### Measurement Method
```bash
# Network throughput using iperf3
# On NAS host: iperf3 -s (server mode)
# On primary: iperf3 -c 192.168.168.56 -t 60 -f M

# Expected output
# Bitrate: 95 Mbps (1GbE) or 1050 Mbps (10GbE)
```

### File I/O Performance

#### Sequential Operations
- **Write throughput**: 50+ MB/s
- **Read throughput**: 80+ MB/s
- **Block size**: 1MB (optimal for bulk data transfer)
- **Concurrency**: Single stream

#### Random Operations
- **IOPS**: 500+ ops/sec
- **Latency**: <10ms per operation
- **Block size**: 4KB (typical database I/O)
- **Concurrency**: 8 parallel streams

#### Measurement Method
```bash
# File I/O benchmark using fio
bash scripts/benchmark-nas.sh --nas-host 192.168.168.56

# Tests:
# 1. Sequential write: 128MB @ 1MB blocks
# 2. Random read: 64MB @ 4KB blocks, 8 jobs
# 3. Database simulation: Mixed R/W patterns
```

## Optimization Strategies

### SMB3 Configuration

#### Enable Multichannel (Parallel Connections)
```bash
# SMB3 multichannel allows multiple connections for increased throughput
# Configuration (Samba/Windows):
# - Max channels: 4-8 (depends on NIC capacity)
# - Automatically selects best available channels
# - Improves throughput by 2-4x on idle NICs
```

#### Performance Tuning
```bash
# /etc/samba/smb.conf (Samba server)
[global]
    smb3 signing = default
    smb3 multichannel enabled = yes
    max connections = 4096
    socket options = TCP_NODELAY IPTOS_LOWDELAY SO_RCVBUF=262144 SO_SNDBUF=262144
    read raw = yes
    write raw = yes
    dead time = 15
    workgroup = PAPERCLIP
```

### Network Optimization

#### NIC Settings
```bash
# Check current settings
ethtool -i eth0
ethtool -g eth0

# Enable jumbo frames (if switch supports)
# MTU 9000 can improve throughput by 10-15%
ip link set dev eth0 mtu 9000

# Verify
ip link show eth0
```

#### TCP Window Scaling
```bash
# Verify TCP window scaling enabled
sysctl net.ipv4.tcp_window_scaling

# Set optimal window size
sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864"
sysctl -w net.ipv4.tcp_wmem="4096 65536 67108864"
```

### Storage Optimization

#### NAS Cache Strategy
- **Read cache**: Aggressive (database queries frequently repeated)
- **Write cache**: Conservative (data durability critical)
- **Cache policy**: Write-back with battery backup
- **Size**: 512MB-1GB (typical NAS capability)

#### Docker Image Storage
```bash
# Store docker images on NAS hot tier for fast overlay operations
# /nas/hot/paperclip-docker/images/
# Symlink from /var/lib/docker/overlay2/

# Benefits:
# - Faster container startup (10-20% improvement)
# - NAS redundancy for container layers
# - Separates application data from system storage
```

## Benchmark Script

### Usage
```bash
# Run comprehensive benchmarking suite
bash scripts/benchmark-nas.sh

# Custom NAS host
bash scripts/benchmark-nas.sh --nas-host 192.168.168.56

# Generate specific report format
bash scripts/benchmark-nas.sh --output report-20260425.json
```

### Output Metrics
- Network throughput (Mbps)
- Sequential I/O throughput (MB/s)
- Random IOPS (operations/sec)
- Latency statistics
- Mount status and optimization recommendations

## Resilience Patterns

### Failover Verification
```bash
# Test automatic failover from primary to NAS cache
1. Monitor mount status: df -h /mnt/nas
2. Simulate NAS latency: tc qdisc add dev eth0 root netem delay 100ms
3. Verify app continues (degraded performance)
4. Remove latency: tc qdisc del dev eth0 root
```

### DNS Resolution for NAS
- **Hostname**: `nas.internal` (resolves to 192.168.168.56)
- **Health check**: `nc -zv 192.168.168.56 445` (SMB port)
- **Retry policy**: Exponential backoff (100ms, 200ms, 400ms, 800ms)

## Monitoring and Alerts

### Key Metrics to Track
```sql
-- Database queries to monitor NAS performance impact
SELECT 
  query_count,
  avg_execution_time_ms,
  io_wait_percentage
FROM performance_metrics
WHERE storage = 'nfs_mount'
ORDER BY io_wait_percentage DESC;
```

### Alert Thresholds
- **Throughput degradation**: <50 Mbps (1GbE) or <500 Mbps (10GbE)
- **Latency spikes**: >20ms sustained
- **IOPS drop**: <200 ops/sec sustained
- **Mount unavailability**: >5 second recovery time

## Testing Checklist

- [ ] Network throughput baseline established
- [ ] File I/O sequential performance baseline documented
- [ ] Random I/O IOPS baseline established
- [ ] SMB3 multichannel enabled and tested
- [ ] Jumbo frames (MTU 9000) validated
- [ ] DNS resolution tested (nas.internal)
- [ ] Failover scenarios exercised
- [ ] Monitoring alerts configured
- [ ] Performance degradation thresholds set
- [ ] Capacity growth projection created (6-month, 12-month)

## Next Steps

1. **Run benchmarks** on primary host
   - Execute: `bash scripts/benchmark-nas.sh`
   - Capture baseline metrics

2. **Implement optimizations**
   - Enable SMB3 multichannel
   - Configure jumbo frames
   - Tune TCP window sizes

3. **Re-run benchmarks** to measure improvement

4. **Document results** in [NAS-BENCHMARK-RESULTS.md](./NAS-BENCHMARK-RESULTS.md)

5. **Configure alerts** in Prometheus/Grafana

## Related Issues

- **Issue #1536**: Networking, DNS & Performance (this issue)
- **Issue #1532**: Observability (metrics collection foundation)
- **Issue #1534**: Repository Governance (IaC standardization)
- **Issue #1545**: Endpoint & SSO (depends on network performance)

## References

- [SMB3 Protocol Optimization](https://docs.microsoft.com/en-us/windows-server/storage/file-server/smb-direct)
- [Samba Performance Tuning](https://wiki.samba.org/index.php/Performance_Tuning)
- [fio Benchmarking Tool](https://fio.readthedocs.io/)
- [iperf3 Network Testing](https://iperf.fr/)
- [Linux TCP Tuning](https://wiki.linuxfoundation.org/networking/kernel_network_stack)
