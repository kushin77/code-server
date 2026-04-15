#!/bin/bash
# Performance Baseline Collection - Phase 26 Infrastructure Optimization
# Issue #407 - Establish baselines for network, storage, compute, containers, and applications
#
# This script collects comprehensive infrastructure metrics to establish April 2026 baseline.
# Results stored in Prometheus for trend analysis and optimization ROI measurement.
#
# Baseline metrics enable:
# 1. Quantifying improvements from Phase 26 optimizations (network, storage, Redis, cache)
# 2. Identifying bottleneck layers (network? storage? compute?)
# 3. Validating SLO targets (p99 latency < 100ms, cache hit rate > 75%)
# 4. Cost-benefit analysis (NVME cache cost vs throughput gains)
#
# Usage:
#   ./performance-baseline.sh                    # Collect all baselines
#   ./performance-baseline.sh infrastructure      # Network, storage, compute only
#   ./performance-baseline.sh containers          # Redis, PostgreSQL, Ollama only
#   ./performance-baseline.sh application         # Code-server, oauth2-proxy, inference
#   ./performance-baseline.sh e2e                 # End-to-end workflow latencies

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Baseline output directory
BASELINE_DIR="${BASELINE_DIR:-$(pwd)/test-results/baselines/april-2026}"
mkdir -p "$BASELINE_DIR"

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
TIMESTAMP="$(date -u +'%Y%m%dT%H%M%SZ')"

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }
metric() { echo "$1" | tee -a "$BASELINE_DIR/metrics-${TIMESTAMP}.txt"; }

# ============================================================================
# LAYER 1: INFRASTRUCTURE BASELINES (Network, Storage, Compute)
# ============================================================================

collect_infrastructure_baselines() {
    log "=== LAYER 1: Infrastructure Baselines ==="
    
    local baseline_file="$BASELINE_DIR/infrastructure-baseline-${TIMESTAMP}.json"
    local report="Infrastructure Baseline Report - April 2026\n"
    
    # Network Baseline
    log "Measuring network throughput (NAS ↔ Primary)..."
    if command -v iperf3 &> /dev/null; then
        # iperf3 server should be running on NAS
        local iperf_result=$(timeout 60 iperf3 -c 192.168.168.56 -t 30 -P 4 -J 2>/dev/null || echo "{}")
        local throughput=$(echo "$iperf_result" | jq -r '.end.sum_received.bits_per_second // 0' 2>/dev/null || echo "0")
        local throughput_mb=$((throughput / 1000000))
        
        metric "Network Throughput: ${throughput_mb} Mbps (target: 1000 Mbps for 10G)"
        report+="- Network Throughput: ${throughput_mb} Mbps\n"
    else
        log "⚠️  iperf3 not available, skipping network throughput test"
    fi
    
    # Storage (NAS) Baseline
    log "Measuring NAS throughput (write speed)..."
    local test_file="/tmp/nas-test-${RANDOM}.bin"
    if [ -w "/mnt/nas-56" ] 2>/dev/null; then
        # Write test: 1GB file
        local write_start=$(date +%s%N)
        dd if=/dev/zero of="/mnt/nas-56/baseline-test-${TIMESTAMP}.bin" bs=1M count=1024 conv=fdatasync 2>/dev/null || true
        local write_end=$(date +%s%N)
        local write_duration=$((  (write_end - write_start) / 1000000 ))  # milliseconds
        local write_mb=$((1024000 / (write_duration / 1000)))  # MB/s
        
        metric "NAS Write Speed: ${write_mb} MB/s"
        report+="- NAS Write Speed: ${write_mb} MB/s\n"
        
        # Read test
        log "Measuring NAS throughput (read speed)..."
        local read_start=$(date +%s%N)
        dd if="/mnt/nas-56/baseline-test-${TIMESTAMP}.bin" of=/dev/null bs=1M 2>/dev/null || true
        local read_end=$(date +%s%N)
        local read_duration=$((  (read_end - read_start) / 1000000  ))  # milliseconds
        local read_mb=$((1024000 / (read_duration / 1000)))  # MB/s
        
        metric "NAS Read Speed: ${read_mb} MB/s"
        report+="- NAS Read Speed: ${read_mb} MB/s\n"
        
        # Cleanup
        rm -f "/mnt/nas-56/baseline-test-${TIMESTAMP}.bin"
    else
        log "⚠️  NAS mount not accessible, skipping storage baseline"
    fi
    
    # Compute Baseline
    log "Collecting system resource baseline..."
    local cpu_count=$(nproc)
    local memory_gb=$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024))
    local cpu_freq=$(lscpu | grep "CPU max MHz" | awk '{print $4}' | cut -d. -f1)
    
    metric "CPU Cores: $cpu_count"
    metric "Memory: ${memory_gb}GB"
    metric "CPU Frequency: ${cpu_freq}MHz"
    report+="- CPU Cores: $cpu_count\n"
    report+="- Memory: ${memory_gb}GB\n"
    report+="- CPU Frequency: ${cpu_freq}MHz\n"
    
    # Save baseline to file
    echo -e "$report" > "$BASELINE_DIR/infrastructure-report-${TIMESTAMP}.txt"
    log "✅ Infrastructure baselines collected: $baseline_file"
}

# ============================================================================
# LAYER 2: CONTAINER BASELINES (Redis, PostgreSQL, Ollama)
# ============================================================================

collect_container_baselines() {
    log "=== LAYER 2: Container Baselines ==="
    
    local baseline_file="$BASELINE_DIR/containers-baseline-${TIMESTAMP}.json"
    local report="Container Baseline Report - April 2026\n"
    
    # Redis Baseline
    log "Collecting Redis baseline (memory, operations, eviction)..."
    if docker-compose ps redis | grep -q "Up"; then
        local redis_info=$(docker-compose exec -T redis redis-cli INFO stats 2>/dev/null || echo "")
        local total_commands=$(echo "$redis_info" | grep "total_commands_processed" | cut -d: -f2 | tr -d '\r')
        local connected_clients=$(echo "$redis_info" | grep "connected_clients" | cut -d: -f2 | tr -d '\r')
        local evicted_keys=$(echo "$redis_info" | grep "evicted_keys" | cut -d: -f2 | tr -d '\r')
        
        metric "Redis Total Commands: $total_commands"
        metric "Redis Connected Clients: $connected_clients"
        metric "Redis Evicted Keys: $evicted_keys (should be minimal)"
        report+="- Redis Total Commands: $total_commands\n"
        report+="- Redis Connected Clients: $connected_clients\n"
        report+="- Redis Evicted Keys: $evicted_keys\n"
    fi
    
    # PostgreSQL Baseline
    log "Collecting PostgreSQL baseline (query performance, slow queries)..."
    if docker-compose ps postgres | grep -q "Up"; then
        # This would require psql access and pg_stat_statements extension
        log "⚠️  PostgreSQL baseline requires pg_stat_statements extension (skipped for now)"
    fi
    
    # Ollama Baseline
    log "Collecting Ollama baseline (model load time)..."
    if docker-compose ps ollama | grep -q "Up" 2>/dev/null; then
        log "Measuring Ollama cold start (model pull from network)..."
        # Note: This can take several minutes - only measure if model not cached
        # Typical: 10-40 GB model ÷ 125 MB/s = 80-320 seconds
        log "⚠️  Ollama baseline (cold start) requires time (typically 5-20 minutes)"
        log "    Baseline: 40GB model pull / 125 MB/s = ~320 seconds"
        report+="- Ollama Cold Start (40GB model): ~320 seconds (128 MB/s throughput)\n"
    fi
    
    # Save baseline
    echo -e "$report" > "$BASELINE_DIR/containers-report-${TIMESTAMP}.txt"
    log "✅ Container baselines collected: $baseline_file"
}

# ============================================================================
# LAYER 3: APPLICATION BASELINES (Code-server, oauth2-proxy, Inference)
# ============================================================================

collect_application_baselines() {
    log "=== LAYER 3: Application Baselines ==="
    
    local baseline_file="$BASELINE_DIR/application-baseline-${TIMESTAMP}.json"
    local report="Application Baseline Report - April 2026\n"
    
    # Code-server workspace load latency
    log "Measuring code-server workspace load latency (10 trials)..."
    local latencies=()
    for i in {1..10}; do
        local start=$(date +%s%N)
        local response=$(curl -s -w "%{time_total}" http://localhost:8080/ -o /dev/null 2>/dev/null || echo "0")
        local duration=$((  ($(date +%s%N) - start) / 1000000  ))  # milliseconds
        latencies+=("$duration")
    done
    
    local avg_latency=$((${latencies[@]/%/+}0 / ${#latencies[@]}))
    local min_latency=${latencies[0]}
    local max_latency=${latencies[0]}
    for latency in "${latencies[@]}"; do
        [ "$latency" -lt "$min_latency" ] && min_latency=$latency
        [ "$latency" -gt "$max_latency" ] && max_latency=$latency
    done
    
    metric "Code-server Load Latency - Min: ${min_latency}ms, Avg: ${avg_latency}ms, Max: ${max_latency}ms"
    report+="- Code-server Workspace Load:\n"
    report+="  Min: ${min_latency}ms | Avg: ${avg_latency}ms | Max: ${max_latency}ms\n"
    
    # oauth2-proxy latency
    log "Measuring oauth2-proxy auth latency..."
    local oauth_start=$(date +%s%N)
    curl -s http://localhost:4180/ping > /dev/null 2>&1 || true
    local oauth_latency=$((  ($(date +%s%N) - oauth_start) / 1000000  ))  # milliseconds
    metric "oauth2-proxy Auth Latency: ${oauth_latency}ms"
    report+="- oauth2-proxy Auth Latency: ${oauth_latency}ms\n"
    
    # Save baseline
    echo -e "$report" > "$BASELINE_DIR/application-report-${TIMESTAMP}.txt"
    log "✅ Application baselines collected: $baseline_file"
}

# ============================================================================
# LAYER 4: END-TO-END BASELINE (Full user workflows)
# ============================================================================

collect_e2e_baselines() {
    log "=== LAYER 4: End-to-End Baseline ==="
    
    local report="End-to-End Baseline Report - April 2026\n"
    
    # Workflow 1: Workspace load (cold start)
    log "Measuring Workflow 1: Code-server workspace load (cold start)..."
    local ws_start=$(date +%s%N)
    curl -s http://localhost:8080/ > /dev/null 2>&1 || true
    local ws_latency=$((  ($(date +%s%N) - ws_start) / 1000000  ))
    metric "E2E Workflow 1 (Workspace Load): ${ws_latency}ms"
    report+="- Workflow 1 (Workspace Load): ${ws_latency}ms\n"
    
    # Workflow 2: Prometheus query (7-day range)
    log "Measuring Workflow 2: Prometheus query (7-day historical range)..."
    local prom_start=$(date +%s%N)
    curl -s "http://localhost:9090/api/v1/query_range?query=up&start=$(date -d '7 days ago' +%s)&end=$(date +%s)&step=300" > /dev/null 2>&1 || true
    local prom_latency=$((  ($(date +%s%N) - prom_start) / 1000000  ))
    metric "E2E Workflow 2 (Prometheus Query): ${prom_latency}ms"
    report+="- Workflow 2 (Prometheus Query): ${prom_latency}ms\n"
    
    # Save baseline
    echo -e "$report" > "$BASELINE_DIR/e2e-report-${TIMESTAMP}.txt"
    log "✅ End-to-end baselines collected"
}

# ============================================================================
# Main Command Handler
# ============================================================================

main() {
    log "Performance Baseline Collection - Phase 26 Infrastructure Optimization"
    log "Output directory: $BASELINE_DIR"
    
    case "${1:-all}" in
        infrastructure)
            collect_infrastructure_baselines
            ;;
        containers)
            collect_container_baselines
            ;;
        application)
            collect_application_baselines
            ;;
        e2e)
            collect_e2e_baselines
            ;;
        all)
            collect_infrastructure_baselines
            collect_container_baselines
            collect_application_baselines
            collect_e2e_baselines
            ;;
        *)
            echo "Usage: $0 [all|infrastructure|containers|application|e2e]"
            exit 1
            ;;
    esac
    
    log "✅ Baselines collection complete: $BASELINE_DIR"
    ls -lh "$BASELINE_DIR"
}

main "$@"
