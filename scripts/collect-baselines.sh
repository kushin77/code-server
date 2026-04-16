#!/bin/bash
# scripts/collect-baselines.sh
# Performance baseline collection script for April 2026 infrastructure assessment
# Usage: bash scripts/collect-baselines.sh
# Output: monitoring/baselines/YYYY-MM-DD/

set -euo pipefail

BASELINE_DIR="monitoring/baselines/$(date +%Y-%m-%d)"
mkdir -p "$BASELINE_DIR"

echo "=========================================="
echo "Performance Baseline Collection"
echo "Date: $(date)"
echo "Output: $BASELINE_DIR"
echo "=========================================="
echo ""

# ==============================================
# 1. NETWORK LAYER BASELINES
# ==============================================
echo "=== NETWORK LAYER BASELINES ===" | tee "$BASELINE_DIR/network.log"
echo "" | tee -a "$BASELINE_DIR/network.log"

# Test 1: Link Speed to Replica (iperf3)
if command -v iperf3 &> /dev/null; then
  echo "Test 1: Network Throughput (iperf3)" | tee -a "$BASELINE_DIR/network.log"
  iperf3 -c 192.168.168.42 -t 30 -R 2>&1 | tee -a "$BASELINE_DIR/network.log" || echo "iperf3 not available on remote" | tee -a "$BASELINE_DIR/network.log"
else
  echo "⚠️  iperf3 not installed, skipping network throughput test" | tee -a "$BASELINE_DIR/network.log"
fi
echo "" | tee -a "$BASELINE_DIR/network.log"

# Test 2: NAS Throughput (Write via NFS)
echo "Test 2: NAS Write Throughput" | tee -a "$BASELINE_DIR/network.log"
if [ -d "/mnt/nas-56" ]; then
  (time dd if=/dev/zero of=/mnt/nas-56/baseline-write-test bs=1M count=100 conv=fdatasync 2>&1) | tee -a "$BASELINE_DIR/network.log"
  rm -f /mnt/nas-56/baseline-write-test
else
  echo "⚠️  NAS mount point not found at /mnt/nas-56" | tee -a "$BASELINE_DIR/network.log"
fi
echo "" | tee -a "$BASELINE_DIR/network.log"

# Test 3: NAS Throughput (Read via NFS)
echo "Test 3: NAS Read Throughput" | tee -a "$BASELINE_DIR/network.log"
if [ -d "/mnt/nas-56" ]; then
  dd if=/dev/zero of=/mnt/nas-56/baseline-read-test bs=1M count=100 conv=fdatasync 2>&1 > /dev/null
  (time dd if=/mnt/nas-56/baseline-read-test of=/dev/null bs=1M count=100 2>&1) | tee -a "$BASELINE_DIR/network.log"
  rm -f /mnt/nas-56/baseline-read-test
else
  echo "⚠️  NAS mount point not found" | tee -a "$BASELINE_DIR/network.log"
fi
echo "" | tee -a "$BASELINE_DIR/network.log"

# Test 4: Network Latency (Ping)
echo "Test 4: Network Latency (ping to replica)" | tee -a "$BASELINE_DIR/network.log"
ping -c 50 192.168.168.42 2>&1 | tee -a "$BASELINE_DIR/network.log" || echo "Ping failed" | tee -a "$BASELINE_DIR/network.log"
echo "" | tee -a "$BASELINE_DIR/network.log"

# Test 5: DNS Resolution Time
echo "Test 5: DNS Resolution Time" | tee -a "$BASELINE_DIR/network.log"
for i in {1..10}; do
  (time nslookup code-server.kushnir.cloud 8.8.8.8 > /dev/null 2>&1) 2>&1 | tee -a "$BASELINE_DIR/network.log"
done
echo "" | tee -a "$BASELINE_DIR/network.log"

# ==============================================
# 2. STORAGE LAYER BASELINES
# ==============================================
echo "=== STORAGE LAYER BASELINES ===" | tee "$BASELINE_DIR/storage.log"
echo "" | tee -a "$BASELINE_DIR/storage.log"

# Test 1: Docker Volume Write Speed
echo "Test 1: Local Docker Volume Write Speed" | tee -a "$BASELINE_DIR/storage.log"
if docker volume inspect testvolume-baseline &> /dev/null; then
  docker volume rm testvolume-baseline
fi
docker volume create testvolume-baseline
docker run --rm -v testvolume-baseline:/data alpine sh -c "(time dd if=/dev/zero of=/data/testfile bs=1M count=50 conv=fdatasync 2>&1)" 2>&1 | tee -a "$BASELINE_DIR/storage.log"
docker volume rm testvolume-baseline
echo "" | tee -a "$BASELINE_DIR/storage.log"

# Test 2: Disk Space Usage
echo "Test 2: Disk Space Usage" | tee -a "$BASELINE_DIR/storage.log"
df -h | tee -a "$BASELINE_DIR/storage.log"
echo "" | tee -a "$BASELINE_DIR/storage.log"
echo "Docker volumes usage:" | tee -a "$BASELINE_DIR/storage.log"
du -sh /var/lib/docker/volumes/* 2>/dev/null | tee -a "$BASELINE_DIR/storage.log" || echo "Cannot access docker volumes" | tee -a "$BASELINE_DIR/storage.log"
echo "" | tee -a "$BASELINE_DIR/storage.log"

# ==============================================
# 3. CONTAINER PERFORMANCE BASELINES
# ==============================================
echo "=== CONTAINER LAYER BASELINES ===" | tee "$BASELINE_DIR/container.log"
echo "" | tee -a "$BASELINE_DIR/container.log"

# Test 1: Docker Stats (Resource Utilization)
echo "Test 1: Container Resource Utilization (snapshot)" | tee -a "$BASELINE_DIR/container.log"
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>&1 | tee -a "$BASELINE_DIR/container.log"
echo "" | tee -a "$BASELINE_DIR/container.log"

# Test 2: Code-server Container Status
echo "Test 2: Code-server Container Health" | tee -a "$BASELINE_DIR/container.log"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep code-server | tee -a "$BASELINE_DIR/container.log" || echo "code-server not running" | tee -a "$BASELINE_DIR/container.log"
echo "" | tee -a "$BASELINE_DIR/container.log"

# Test 3: Redis Info (if running)
echo "Test 3: Redis Status" | tee -a "$BASELINE_DIR/container.log"
if docker ps | grep -q redis; then
  docker exec $(docker ps -q -f name=redis) redis-cli INFO stats 2>&1 | tee -a "$BASELINE_DIR/container.log"
else
  echo "Redis container not found" | tee -a "$BASELINE_DIR/container.log"
fi
echo "" | tee -a "$BASELINE_DIR/container.log"

# Test 4: PostgreSQL Status (if running)
echo "Test 4: PostgreSQL Status" | tee -a "$BASELINE_DIR/container.log"
if docker ps | grep -q postgres; then
  docker exec $(docker ps -q -f name=postgres) psql -U postgres -c "SELECT version();" 2>&1 | tee -a "$BASELINE_DIR/container.log"
else
  echo "PostgreSQL container not found" | tee -a "$BASELINE_DIR/container.log"
fi
echo "" | tee -a "$BASELINE_DIR/container.log"

# ==============================================
# 4. SYSTEM RESOURCE BASELINES
# ==============================================
echo "=== SYSTEM LAYER BASELINES ===" | tee "$BASELINE_DIR/system.log"
echo "" | tee -a "$BASELINE_DIR/system.log"

# Test 1: CPU Info
echo "Test 1: CPU Information" | tee -a "$BASELINE_DIR/system.log"
nproc | xargs echo "Number of CPUs:" | tee -a "$BASELINE_DIR/system.log"
lscpu 2>/dev/null | head -20 | tee -a "$BASELINE_DIR/system.log" || echo "lscpu not available" | tee -a "$BASELINE_DIR/system.log"
echo "" | tee -a "$BASELINE_DIR/system.log"

# Test 2: Memory Info
echo "Test 2: Memory Information" | tee -a "$BASELINE_DIR/system.log"
free -h | tee -a "$BASELINE_DIR/system.log"
echo "" | tee -a "$BASELINE_DIR/system.log"

# Test 3: Load Average
echo "Test 3: Load Average" | tee -a "$BASELINE_DIR/system.log"
uptime | tee -a "$BASELINE_DIR/system.log"
echo "" | tee -a "$BASELINE_DIR/system.log"

# Test 4: Network Interfaces
echo "Test 4: Network Interface Statistics" | tee -a "$BASELINE_DIR/system.log"
ip -s link show 2>&1 | tee -a "$BASELINE_DIR/system.log"
echo "" | tee -a "$BASELINE_DIR/system.log"

# ==============================================
# 5. CREATE PROMETHEUS METRICS FILE
# ==============================================
echo "=== CREATING PROMETHEUS METRICS FILE ===" | tee "$BASELINE_DIR/metrics.txt"
echo "" | tee -a "$BASELINE_DIR/metrics.txt"

cat >> "$BASELINE_DIR/metrics.txt" <<'EOF'
# HELP baseline_network_iperf3_throughput_mbps Network throughput measured via iperf3
# TYPE baseline_network_iperf3_throughput_mbps gauge
baseline_network_iperf3_throughput_mbps{host="primary",target="replica",date="april_2026"} 0

# HELP baseline_storage_nas_write_throughput_mbps NAS write throughput
# TYPE baseline_storage_nas_write_throughput_mbps gauge
baseline_storage_nas_write_throughput_mbps{date="april_2026"} 0

# HELP baseline_storage_nas_read_throughput_mbps NAS read throughput
# TYPE baseline_storage_nas_read_throughput_mbps gauge
baseline_storage_nas_read_throughput_mbps{date="april_2026"} 0

# HELP baseline_network_ping_latency_ms Network latency (ping)
# TYPE baseline_network_ping_latency_ms gauge
baseline_network_ping_latency_ms{target="replica",percentile="p50",date="april_2026"} 0
baseline_network_ping_latency_ms{target="replica",percentile="p95",date="april_2026"} 0
baseline_network_ping_latency_ms{target="replica",percentile="p99",date="april_2026"} 0

# HELP baseline_system_load_average System load average
# TYPE baseline_system_load_average gauge
baseline_system_load_average{interval="1m",date="april_2026"} 0
baseline_system_load_average{interval="5m",date="april_2026"} 0
baseline_system_load_average{interval="15m",date="april_2026"} 0

# HELP baseline_system_memory_available_mb Available system memory
# TYPE baseline_system_memory_available_mb gauge
baseline_system_memory_available_mb{date="april_2026"} 0

# HELP baseline_system_cpu_count Total CPU cores
# TYPE baseline_system_cpu_count gauge
baseline_system_cpu_count{date="april_2026"} 0
EOF

echo "✅ Prometheus metrics template created" | tee -a "$BASELINE_DIR/metrics.txt"
echo "" | tee -a "$BASELINE_DIR/metrics.txt"

# ==============================================
# 6. SUMMARY
# ==============================================
echo "=========================================="
echo "✅ BASELINE COLLECTION COMPLETE"
echo "=========================================="
echo ""
echo "Output files:"
ls -lh "$BASELINE_DIR"
echo ""
echo "Next steps:"
echo "1. Review baseline results in $BASELINE_DIR"
echo "2. Extract key metrics and update Prometheus recording rules"
echo "3. Create Grafana dashboard for baseline comparison"
echo "4. Document findings in docs/BASELINE-APRIL-2026.md"
echo ""
echo "Timeline: May 1-7, 2026 (P3 #410)"
echo "=========================================="
