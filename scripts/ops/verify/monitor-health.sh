#!/bin/bash

################################################################################
# Hermes Agent Portal - Automated Health Monitoring Script
# Purpose: Real-time health monitoring for all services
# Usage: ./monitor-health.sh [interval] [duration]
#        ./monitor-health.sh 5 3600  # Monitor every 5 seconds for 1 hour
# Date: April 30, 2026
################################################################################

set -e

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/monitor_*.tmp 2>/dev/null || true' EXIT

# Configuration
INTERVAL=${1:-30}  # Check interval in seconds (default: 30)
DURATION=${2:-0}   # Total duration (0 = infinite, default)
CONFIG_FILE="docker-compose.enterprise.yml"
LOG_DIR="monitoring-logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="$LOG_DIR/health_monitor_${TIMESTAMP}.log"
ALERT_FILE="$LOG_DIR/alerts_${TIMESTAMP}.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize
mkdir -p "$LOG_DIR"

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARN: $*${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $*${NC}" | tee -a "$LOG_FILE" "$ALERT_FILE"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] OK: $*${NC}" | tee -a "$LOG_FILE"
}

log_debug() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] DEBUG: $*" >> "$LOG_FILE"
}

################################################################################
# Health Check Functions
################################################################################

check_containers() {
    log_info "Checking container status..."
    
    local status_ok=true
    docker-compose -f "$CONFIG_FILE" ps | grep -E "appsmith|hermes-integration|code-server|postgres|redis" | while read line; do
        if echo "$line" | grep -q "Up (healthy)"; then
            local container_name=$(echo "$line" | awk '{print $1}')
            log_success "Container healthy: $container_name"
        elif echo "$line" | grep -q "Up"; then
            local container_name=$(echo "$line" | awk '{print $1}')
            log_warn "Container running but not healthy: $container_name"
            status_ok=false
        else
            local container_name=$(echo "$line" | awk '{print $1}')
            log_error "Container not running: $container_name"
            status_ok=false
        fi
    done
    
    return $([ "$status_ok" = true ] && echo 0 || echo 1)
}

check_api_health() {
    log_info "Checking API health endpoint..."
    
    local response=$(curl -s -k -m 5 https://kushnir.cloud/api/hermes/health 2>/dev/null || echo '{"error":"timeout"}')
    
    if echo "$response" | grep -q '"status":"healthy"'; then
        log_success "API health check passed"
        return 0
    elif echo "$response" | grep -q '"error"'; then
        log_error "API health check failed: $response"
        return 1
    else
        log_warn "API health check returned unexpected response: $response"
        return 1
    fi
}

check_database() {
    log_info "Checking database connectivity..."
    
    local result=$(docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT 1;" 2>&1)
    
    if echo "$result" | grep -q "(1 row)"; then
        log_success "Database connectivity OK"
        return 0
    else
        log_error "Database connectivity failed: $result"
        return 1
    fi
}

check_redis() {
    log_info "Checking Redis connectivity..."
    
    local result=$(docker exec code-server-redis redis-cli ping 2>&1)
    
    if [ "$result" = "PONG" ]; then
        log_success "Redis connectivity OK"
        return 0
    else
        log_error "Redis connectivity failed: $result"
        return 1
    fi
}

check_disk_space() {
    log_info "Checking disk space..."
    
    local usage=$(df -h /home | tail -1 | awk '{print $5}' | sed 's/%//')
    
    if [ "$usage" -lt 80 ]; then
        log_success "Disk usage OK: ${usage}%"
        return 0
    elif [ "$usage" -lt 90 ]; then
        log_warn "Disk usage warning: ${usage}%"
        return 1
    else
        log_error "Disk usage critical: ${usage}%"
        return 1
    fi
}

check_memory() {
    log_info "Checking memory usage..."
    
    docker stats --no-stream | tail -n +2 | while read line; do
        local container=$(echo "$line" | awk '{print $1}')
        local mem_percent=$(echo "$line" | awk '{print $6}' | sed 's/%//')
        
        if [ -z "$mem_percent" ] || [ "$mem_percent" = "MEM" ]; then
            continue
        fi
        
        if [ "${mem_percent%.*}" -lt 50 ]; then
            log_debug "Container $container memory OK: ${mem_percent}%"
        elif [ "${mem_percent%.*}" -lt 80 ]; then
            log_warn "Container $container memory warning: ${mem_percent}%"
        else
            log_error "Container $container memory critical: ${mem_percent}%"
        fi
    done
}

check_dns() {
    log_info "Checking DNS resolution..."
    
    local result=$(nslookup kushnir.cloud 2>&1 | grep "192.168.168.31")
    
    if [ -n "$result" ]; then
        log_success "DNS resolution OK"
        return 0
    else
        log_error "DNS resolution failed"
        return 1
    fi
}

check_ssl_certificate() {
    log_info "Checking SSL certificate validity..."
    
    local expiry=$(echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | openssl x509 -noout -enddate | cut -d= -f2)
    
    if [ -n "$expiry" ]; then
        log_success "SSL certificate valid until: $expiry"
        return 0
    else
        log_error "SSL certificate check failed"
        return 1
    fi
}

################################################################################
# Monitoring Summary
################################################################################

generate_summary() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Health Monitoring Summary - $(date +'%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    
    local total=0
    local passed=0
    
    echo ""
    echo "Container Status:"
    docker-compose -f "$CONFIG_FILE" ps | grep -E "appsmith|hermes-integration|code-server|postgres|redis"
    
    echo ""
    echo "Quick Checks:"
    total=$((total + 1))
    curl -s -k https://kushnir.cloud/api/hermes/health >/dev/null 2>&1 && { echo -e "${GREEN}✓${NC} API responsive"; passed=$((passed + 1)); } || echo -e "${RED}✗${NC} API not responsive"
    
    total=$((total + 1))
    docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT 1;" >/dev/null 2>&1 && { echo -e "${GREEN}✓${NC} Database responsive"; passed=$((passed + 1)); } || echo -e "${RED}✗${NC} Database not responsive"
    
    total=$((total + 1))
    docker exec code-server-redis redis-cli ping >/dev/null 2>&1 && { echo -e "${GREEN}✓${NC} Redis responsive"; passed=$((passed + 1)); } || echo -e "${RED}✗${NC} Redis not responsive"
    
    echo ""
    echo "Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    
    echo ""
    echo -e "Summary: ${GREEN}$passed/$total${NC} critical services OK"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

################################################################################
# Main Monitoring Loop
################################################################################

main() {
    log_info "Starting health monitoring (interval: ${INTERVAL}s, duration: ${DURATION}s)"
    log_info "Configuration file: $CONFIG_FILE"
    log_info "Logs: $LOG_FILE"
    log_info "Alerts: $ALERT_FILE"
    
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Hermes Agent Portal - Health Monitor${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo "Check Interval: ${INTERVAL} seconds"
    echo "Total Duration: $([ $DURATION -eq 0 ] && echo "Infinite" || echo "${DURATION}s")"
    echo "Start Time: $(date +'%Y-%m-%d %H:%M:%S')"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    local start_time=$(date +%s)
    local iteration=0
    
    while true; do
        iteration=$((iteration + 1))
        
        echo -e "${BLUE}[Iteration $iteration]${NC} Checking health at $(date +'%H:%M:%S')..."
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Run all health checks
        check_containers || true
        check_api_health || true
        check_database || true
        check_redis || true
        check_disk_space || true
        check_memory || true
        check_dns || true
        check_ssl_certificate || true
        
        # Generate summary
        generate_summary
        
        # Check if we should stop
        if [ $DURATION -ne 0 ]; then
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            
            if [ $elapsed -ge $DURATION ]; then
                log_info "Monitoring duration reached. Stopping."
                break
            fi
        fi
        
        # Wait for next interval
        sleep "$INTERVAL"
    done
    
    log_info "Health monitoring completed at $(date +'%Y-%m-%d %H:%M:%S')"
    log_info "Total iterations: $iteration"
    log_info "Full logs saved to: $LOG_FILE"
    
    if [ -s "$ALERT_FILE" ]; then
        log_warn "Alerts were recorded - see $ALERT_FILE"
    else
        log_success "No alerts recorded"
    fi
}

# Execute main function
main "$@"
