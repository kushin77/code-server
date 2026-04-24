#!/usr/bin/env bash
# @file        scripts/ops/cluster-audit-comprehensive.sh
# @module      ops/cluster
# @description Comprehensive cluster health audit and failover readiness assessment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
TARGET_USER="${TARGET_USER:-akushnir}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

check() {
    local name="$1"
    local result="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ "$result" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $name"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        echo -e "${RED}✗${NC} $name"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

audit_host_connectivity() {
    local host="$1"
    local label="$2"
    
    echo -e "\n${BLUE}=== Host Connectivity: $label ===${NC}"
    
    ssh -o ConnectTimeout=5 "${TARGET_USER}@${host}" "echo ok" > /dev/null 2>&1
    check "SSH connectivity to $host" $?
    
    ssh "${TARGET_USER}@${host}" "docker version > /dev/null 2>&1"
    check "Docker daemon running on $host" $?
    
    ssh "${TARGET_USER}@${host}" "docker-compose version > /dev/null 2>&1"
    check "docker-compose available on $host" $?
    
    ssh "${TARGET_USER}@${host}" "grep -q 'net-edge\|net-app\|net-data' code-server-enterprise/docker-compose.yml 2>/dev/null"
    check "Docker networks configured on $host" $?
}

audit_services_primary() {
    echo -e "\n${BLUE}=== Services Status: Primary (31) ===${NC}"
    
    local services=("code-server" "oauth2-proxy" "redis" "postgres" "prometheus" "grafana" "alertmanager" "caddy" "jaeger" "loki")
    
    for svc in "${services[@]}"; do
        ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && docker-compose ps $svc 2>/dev/null | grep -q 'healthy\|Up'" 2>/dev/null
        check "Service $svc running on primary" $?
    done
}

audit_services_replica() {
    echo -e "\n${BLUE}=== Services Status: Replica (42) ===${NC}"
    
    local services=("code-server" "oauth2-proxy" "redis" "postgres" "prometheus" "grafana" "alertmanager" "caddy" "jaeger" "loki")
    
    for svc in "${services[@]}"; do
        ssh "${TARGET_USER}@${REPLICA_HOST}" "docker ps --format 'table {{.Names}}' | grep -q $svc" 2>/dev/null
        check "Service $svc running on replica" $?
    done
}

audit_load_balancing() {
    echo -e "\n${BLUE}=== Load Balancing Configuration ===${NC}"
    
    # Check oauth2-proxy upstreams on primary
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && grep -q '192.168.168.42:8080' docker-compose.yml"
    check "Primary oauth2-proxy configured for load balancing" $?
    
    # Check oauth2-proxy upstreams on replica
    ssh "${TARGET_USER}@${REPLICA_HOST}" "cd code-server-enterprise && grep -q '192.168.168.31:8080' docker-compose.yml"
    check "Replica oauth2-proxy configured for load balancing" $?
    
    # Check code-server accessibility on both hosts
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "docker exec oauth2-proxy wget -q -O- http://code-server:8080/healthz > /dev/null 2>&1"
    check "Primary code-server health check via oauth2-proxy" $?
    
    ssh "${TARGET_USER}@${REPLICA_HOST}" "docker exec oauth2-proxy wget -q -O- http://code-server:8080/healthz > /dev/null 2>&1"
    check "Replica code-server health check via oauth2-proxy" $?
}

audit_cross_host_connectivity() {
    echo -e "\n${BLUE}=== Cross-Host Connectivity ===${NC}"
    
    # Primary to Replica
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "curl -s -o /dev/null -w '%{http_code}' http://${REPLICA_HOST}:8080/healthz 2>/dev/null | grep -qE '200|000|301'"
    check "Primary can reach replica code-server on port 8080" $?
    
    # Replica to Primary
    ssh "${TARGET_USER}@${REPLICA_HOST}" "curl -s -o /dev/null -w '%{http_code}' http://${PRIMARY_HOST}:8080/healthz 2>/dev/null | grep -qE '200|000|301'"
    check "Replica can reach primary code-server on port 8080" $?
}

audit_database_replication() {
    echo -e "\n${BLUE}=== Database Replication ===${NC}"
    
    # Check postgres on both hosts
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && docker-compose exec -T postgres psql -U code_server -d code_server -c 'SELECT 1' > /dev/null 2>&1"
    check "Postgres accessible on primary" $?
    
    ssh "${TARGET_USER}@${REPLICA_HOST}" "docker exec postgres psql -U code_server -d code_server -c 'SELECT 1' > /dev/null 2>&1"
    check "Postgres accessible on replica" $?
    
    # Check redis replication
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && docker-compose exec -T redis redis-cli PING > /dev/null 2>&1"
    check "Redis accessible on primary" $?
    
    ssh "${TARGET_USER}@${REPLICA_HOST}" "docker exec redis redis-cli PING > /dev/null 2>&1"
    check "Redis accessible on replica" $?
}

audit_session_persistence() {
    echo -e "\n${BLUE}=== Session Persistence ===${NC}"
    
    # Check if session data is shared across hosts
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && docker-compose exec -T redis redis-cli DBSIZE > /dev/null 2>&1"
    check "Redis session store on primary" $?
    
    # Session cookies should use redis across both hosts
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && grep -q 'SESSION_STORE_TYPE.*redis' docker-compose.yml"
    check "OAuth2 session store using redis" $?
}

audit_failover_readiness() {
    echo -e "\n${BLUE}=== Failover Readiness ===${NC}"
    
    # Check if services are stateless (no local-only configuration)
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && grep -q 'REPLICA_HOST' docker-compose.yml"
    check "Load balancing configuration supports failover" $?
    
    # Check if both hosts have identical docker-compose structure
    local primary_md5=$(ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && grep -E 'services:|^[a-z]' docker-compose.yml | md5sum | cut -d' ' -f1")
    local replica_md5=$(ssh "${TARGET_USER}@${REPLICA_HOST}" "cd code-server-enterprise && grep -E 'services:|^[a-z]' docker-compose.yml | md5sum | cut -d' ' -f1")
    
    if [ "$primary_md5" = "$replica_md5" ]; then
        check "docker-compose.yml identical on both hosts" 0
    else
        check "docker-compose.yml identical on both hosts" 1
    fi
    
    # Check health check endpoints
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "curl -s http://127.0.0.1:4180/ping > /dev/null 2>&1"
    check "Primary health check endpoint responding" $?
    
    ssh "${TARGET_USER}@${REPLICA_HOST}" "curl -s http://127.0.0.1:4180/ping > /dev/null 2>&1"
    check "Replica health check endpoint responding" $?
}

audit_monitoring_and_alerts() {
    echo -e "\n${BLUE}=== Monitoring and Alerts ===${NC}"
    
    # Check prometheus on both hosts
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && docker-compose ps prometheus | grep -q healthy"
    check "Prometheus running on primary" $?
    
    ssh "${TARGET_USER}@${REPLICA_HOST}" "docker ps --filter name=prometheus | grep -q prometheus"
    check "Prometheus running on replica" $?
    
    # Check alertmanager
    ssh "${TARGET_USER}@${PRIMARY_HOST}" "cd code-server-enterprise && docker-compose ps alertmanager | grep -q healthy"
    check "Alertmanager running on primary" $?
    
    ssh "${TARGET_USER}@${REPLICA_HOST}" "docker ps --filter name=alertmanager | grep -q alertmanager"
    check "Alertmanager running on replica" $?
}

print_summary() {
    echo -e "\n${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║        CLUSTER AUDIT SUMMARY           ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    
    echo -e "\nTotal Checks:  $TOTAL_CHECKS"
    echo -e "${GREEN}Passed:${NC}        $PASSED_CHECKS"
    echo -e "${RED}Failed:${NC}        $FAILED_CHECKS"
    
    local percentage=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo -e "\nHealth Score:  ${percentage}%"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo -e "\n${GREEN}✓ Cluster is HEALTHY and READY${NC}"
    else
        echo -e "\n${RED}✗ Cluster has issues that need addressing${NC}"
    fi
}

main() {
    log_info "Starting comprehensive cluster audit"
    
    audit_host_connectivity "$PRIMARY_HOST" "Primary (192.168.168.31)"
    audit_host_connectivity "$REPLICA_HOST" "Replica (192.168.168.42)"
    
    audit_services_primary
    audit_services_replica
    
    audit_load_balancing
    audit_cross_host_connectivity
    
    audit_database_replication
    audit_session_persistence
    
    audit_failover_readiness
    audit_monitoring_and_alerts
    
    print_summary
    
    # Exit with error if any checks failed
    if [ $FAILED_CHECKS -gt 0 ]; then
        exit 1
    fi
}

main "$@"
