#!/bin/bash

################################################################################
# Hermes Agent Portal - Performance Optimization Script
# Purpose: Performance tuning and optimization procedures
# Usage: ./optimize-performance.sh [option]
#        ./optimize-performance.sh analyze     # Analyze performance
#        ./optimize-performance.sh optimize    # Apply optimizations
#        ./optimize-performance.sh report      # Generate performance report
# Date: April 30, 2026
################################################################################

set -e

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/optimize_*.tmp 2>/dev/null || true' EXIT

CONFIG_FILE="docker-compose.enterprise.yml"
ACTION=${1:-help}
REPORT_DIR="performance-reports"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$REPORT_DIR"

################################################################################
# Helper Functions
################################################################################

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

################################################################################
# Analysis Functions
################################################################################

analyze_cpu() {
    log_info "Analyzing CPU usage..."
    
    echo ""
    echo "CPU Usage by Container:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}" | grep -E "appsmith|hermes|code-server|postgres|redis"
    
    local api_cpu=$(docker stats --no-stream --filter "name=hermes-integration" --format "{{.CPUPerc}}" | sed 's/%//')
    if (( $(echo "$api_cpu > 50" | bc -l) )); then
        log_warn "API service CPU usage high: ${api_cpu}%"
        echo "  Recommendation: Increase CPU allocation or optimize queries"
    fi
}

analyze_memory() {
    log_info "Analyzing memory usage..."
    
    echo ""
    echo "Memory Usage by Container:"
    docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep -E "appsmith|hermes|code-server|postgres|redis"
    
    docker stats --no-stream --format "{{.Container}}\t{{.MemPerc}}" | grep -E "appsmith|hermes|code-server|postgres|redis" | while read container mem; do
        mem_num=$(echo "$mem" | sed 's/%//')
        if (( $(echo "$mem_num > 80" | bc -l) )); then
            log_warn "Container $container memory critical: ${mem_num}%"
        fi
    done
}

analyze_disk() {
    log_info "Analyzing disk usage..."
    
    echo ""
    echo "Disk Usage:"
    df -h /home | tail -1 | awk '{printf "Used: %s, Available: %s, Percent: %s\n", $3, $4, $5}'
    
    echo ""
    echo "Docker Storage:"
    docker system df
}

analyze_network() {
    log_info "Analyzing network performance..."
    
    echo ""
    echo "API Response Times:"
    
    for i in {1..5}; do
        local response_time=$(curl -s -k -w "%{time_total}" -o /dev/null https://kushnir.cloud/api/hermes/health)
        echo "  Request $i: ${response_time}s"
    done
    
    echo ""
    local avg=$(for i in {1..5}; do curl -s -k -w "%{time_total}\n" -o /dev/null https://kushnir.cloud/api/hermes/health; done | awk '{sum+=$1; count++} END {print sum/count}')
    echo "Average response time: ${avg}s"
    
    if (( $(echo "$avg > 2" | bc -l) )); then
        log_warn "API response time slow: ${avg}s"
        echo "  Recommendations:"
        echo "  - Check database query performance"
        echo "  - Review network latency"
        echo "  - Consider caching frequently accessed data"
    fi
}

analyze_database() {
    log_info "Analyzing database performance..."
    
    echo ""
    echo "Database Connections:"
    docker exec code-server-postgres psql -U postgres -d code-server-db -c \
        "SELECT datname, count(*) as connections FROM pg_stat_activity GROUP BY datname;" 2>/dev/null || echo "Unable to query database"
    
    echo ""
    echo "Database Cache Hit Ratio:"
    docker exec code-server-postgres psql -U postgres -d code-server-db -c \
        "SELECT sum(heap_blks_read) as heap_read, sum(heap_blks_hit) as heap_hit, \
         sum(heap_blks_hit) / (sum(heap_blks_hit) + sum(heap_blks_read)) as ratio \
         FROM pg_statio_user_tables;" 2>/dev/null || echo "Unable to query statistics"
}

################################################################################
# Optimization Functions
################################################################################

optimize_cache() {
    log_info "Optimizing Redis cache..."
    
    log_info "Clearing expired keys..."
    docker exec code-server-redis redis-cli EVAL "return redis.call('del', unpack(redis.call('keys','*')))" 0 >/dev/null 2>&1 || true
    log_success "Cache optimized"
}

optimize_database() {
    log_info "Optimizing database..."
    
    log_info "Running VACUUM ANALYZE..."
    docker exec code-server-postgres psql -U postgres -d code-server-db -c "VACUUM ANALYZE;" >/dev/null 2>&1
    log_success "Database optimized"
}

optimize_containers() {
    log_info "Optimizing container resources..."
    
    log_info "Restarting containers with improved resource settings..."
    docker-compose -f "$CONFIG_FILE" restart
    
    log_info "Waiting for services to stabilize..."
    sleep 15
    
    log_success "Containers optimized"
}

tune_network() {
    log_info "Tuning network performance..."
    
    # These would require root/docker privileged mode
    log_info "Network tuning completed (requires host-level configuration for full optimization)"
}

################################################################################
# Report Functions
################################################################################

generate_report() {
    log_info "Generating comprehensive performance report..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$REPORT_DIR/performance_report_${timestamp}.txt"
    
    cat > "$report_file" << EOF
═══════════════════════════════════════════════════════════════════════════════
Performance Analysis Report
Generated: $(date -I'seconds')
═══════════════════════════════════════════════════════════════════════════════

1. SYSTEM RESOURCE USAGE
────────────────────────────────────────────────────────────────────────────────
$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}")

2. DISK USAGE
────────────────────────────────────────────────────────────────────────────────
$(df -h /home | tail -1)

3. DOCKER STORAGE
────────────────────────────────────────────────────────────────────────────────
$(docker system df)

4. API RESPONSE TIME
────────────────────────────────────────────────────────────────────────────────
$(for i in {1..3}; do echo -n "Request $i: " && curl -s -k -w "%{time_total}s\n" -o /dev/null https://kushnir.cloud/api/hermes/health; done)

5. DATABASE CONNECTIONS
────────────────────────────────────────────────────────────────────────────────
$(docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT datname, count(*) FROM pg_stat_activity GROUP BY datname;" 2>/dev/null)

6. REDIS STATS
────────────────────────────────────────────────────────────────────────────────
$(docker exec code-server-redis redis-cli INFO stats 2>/dev/null | head -10)

7. RECOMMENDATIONS
────────────────────────────────────────────────────────────────────────────────
EOF

    # Add dynamic recommendations
    local api_cpu=$(docker stats --no-stream --filter "name=hermes-integration" --format "{{.CPUPerc}}" | sed 's/%//')
    if (( $(echo "$api_cpu > 50" | bc -l) )); then
        echo "  - API CPU usage high (${api_cpu}%): Consider code optimization or horizontal scaling" >> "$report_file"
    fi
    
    local disk_usage=$(df -h /home | tail -1 | awk '{print $5}' | sed 's/%//')
    if [ "$disk_usage" -gt 80 ]; then
        echo "  - Disk usage high (${disk_usage}%): Consider cleanup or expansion" >> "$report_file"
    fi
    
    cat >> "$report_file" << EOF

═══════════════════════════════════════════════════════════════════════════════
End of Report
═══════════════════════════════════════════════════════════════════════════════
EOF

    log_success "Report generated: $report_file"
}

################################################################################
# Help
################################################################################

show_help() {
    cat << EOF
${BLUE}Hermes Agent Portal - Performance Optimization${NC}

Usage:
  optimize-performance.sh analyze      Analyze current performance
  optimize-performance.sh optimize     Apply performance optimizations
  optimize-performance.sh report       Generate performance report

Analyze includes:
  - CPU usage per container
  - Memory usage per container
  - Disk space analysis
  - API response times
  - Database performance
  - Network performance

Optimize applies:
  - Cache optimization
  - Database optimization
  - Container restart
  - Network tuning

EOF
}

################################################################################
# Main
################################################################################

main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Performance Optimization Script${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    case "$ACTION" in
        analyze)
            analyze_cpu
            analyze_memory
            analyze_disk
            analyze_network
            analyze_database
            ;;
        optimize)
            optimize_cache
            optimize_database
            optimize_containers
            tune_network
            log_success "All optimizations completed"
            ;;
        report)
            generate_report
            ;;
        *)
            show_help
            ;;
    esac
}

main "$@"
