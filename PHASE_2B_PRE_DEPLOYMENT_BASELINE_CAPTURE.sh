#!/bin/bash

################################################################################
# PHASE_2B_PRE_DEPLOYMENT_BASELINE_CAPTURE.sh
# Purpose: Capture current infrastructure metrics before deployment for comparison
# Usage: bash PHASE_2B_PRE_DEPLOYMENT_BASELINE_CAPTURE.sh
# Timing: Run April 30, 18:00 UTC (final pre-deployment snapshot)
# Output: baseline_YYYYMMDD_HHMMSS.json and .txt for archival
################################################################################

set -e
trap 'echo "❌ Baseline capture failed at line $LINENO"; exit 1' ERR
trap 'echo "✓ Baseline capture completed"; rm -f /tmp/baseline_*.tmp 2>/dev/null || true' EXIT

################################################################################
# CONFIGURATION
################################################################################

PRIMARY_HOST="192.168.168.31"
REPLICA_HOST="192.168.168.42"
VIP="192.168.168.50"
BASELINE_DIR="/data/baselines"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BASELINE_FILE="${BASELINE_DIR}/baseline_${TIMESTAMP}"

# Create baseline directory if needed
mkdir -p "${BASELINE_DIR}"

# Enable JSON output
JSON_FILE="${BASELINE_FILE}.json"
TXT_FILE="${BASELINE_FILE}.txt"

# Temp files for collection
TMP_JSON="/tmp/baseline_${TIMESTAMP}.json"
TMP_TXT="/tmp/baseline_${TIMESTAMP}.txt"

echo "{" > "${TMP_JSON}"
echo "PRE-DEPLOYMENT BASELINE CAPTURE" > "${TMP_TXT}"
echo "Captured: $(date)" >> "${TMP_TXT}"
echo "Timestamp: ${TIMESTAMP}" >> "${TMP_TXT}"
echo "" >> "${TMP_TXT}"

################################################################################
# CAPTURE FUNCTIONS
################################################################################

capture_container_state() {
    echo "" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    echo "CONTAINER STATE BASELINE" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    
    echo '  "containers": {' >> "${TMP_JSON}"
    
    # PRIMARY containers
    echo "PRIMARY NODE (192.168.168.31):" | tee -a "${TMP_TXT}"
    local primary_count=$(ssh "ubuntu@${PRIMARY_HOST}" "docker-compose -f docker-compose.enterprise.yml ps --no-trunc 2>/dev/null | grep 'Up' | wc -l")
    echo "    Running containers: ${primary_count}" | tee -a "${TMP_TXT}"
    
    local primary_images=$(ssh "ubuntu@${PRIMARY_HOST}" "docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | sort | uniq" | tr '\n' ',' | sed 's/,$//g')
    echo "    Images in use: ${primary_images}" | tee -a "${TMP_TXT}"
    
    # REPLICA containers
    echo "REPLICA NODE (192.168.168.42):" | tee -a "${TMP_TXT}"
    local replica_count=$(ssh "ubuntu@${REPLICA_HOST}" "docker-compose -f docker-compose.enterprise.yml ps --no-trunc 2>/dev/null | grep 'Up' | wc -l")
    echo "    Running containers: ${replica_count}" | tee -a "${TMP_TXT}"
    
    local replica_images=$(ssh "ubuntu@${REPLICA_HOST}" "docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | sort | uniq" | tr '\n' ',' | sed 's/,$//g')
    echo "    Images in use: ${replica_images}" | tee -a "${TMP_TXT}"
    
    echo '    "primary_containers": '${primary_count}',' >> "${TMP_JSON}"
    echo '    "replica_containers": '${replica_count}'' >> "${TMP_JSON}"
    echo '  },' >> "${TMP_JSON}"
}

capture_database_state() {
    echo "" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    echo "DATABASE STATE BASELINE" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    
    echo '  "database": {' >> "${TMP_JSON}"
    
    # PostgreSQL version
    local pg_version=$(ssh "ubuntu@${PRIMARY_HOST}" "psql -h 192.168.168.31 -U gitlab -d gitlabhq_production -t -c 'SELECT version();' 2>/dev/null | head -1" || echo "UNKNOWN")
    echo "PostgreSQL version:" | tee -a "${TMP_TXT}"
    echo "    ${pg_version}" | tee -a "${TMP_TXT}"
    
    # Database size
    local db_size=$(ssh "ubuntu@${PRIMARY_HOST}" "psql -h 192.168.168.31 -U gitlab -d gitlabhq_production -t -c 'SELECT pg_size_pretty(pg_database_size(current_database()));' 2>/dev/null | head -1" || echo "UNKNOWN")
    echo "Database size:" | tee -a "${TMP_TXT}"
    echo "    ${db_size}" | tee -a "${TMP_TXT}"
    
    # Replication status
    local replication_status=$(ssh "ubuntu@${PRIMARY_HOST}" "psql -h 192.168.168.31 -U gitlab -d gitlabhq_production -t -c 'SELECT slot_name, slot_type, confirmed_flush_lsn FROM pg_replication_slots;' 2>/dev/null | head -5" || echo "UNKNOWN")
    echo "Replication slots:" | tee -a "${TMP_TXT}"
    echo "    ${replication_status}" | tee -a "${TMP_TXT}"
    
    # Number of tables
    local table_count=$(ssh "ubuntu@${PRIMARY_HOST}" "psql -h 192.168.168.31 -U gitlab -d gitlabhq_production -t -c 'SELECT count(*) FROM information_schema.tables WHERE table_schema='\''public'\'';' 2>/dev/null | head -1" || echo "UNKNOWN")
    echo "Number of tables: ${table_count}" | tee -a "${TMP_TXT}"
    
    echo '    "version": "'${pg_version}'",' >> "${TMP_JSON}"
    echo '    "size": "'${db_size}'",' >> "${TMP_JSON}"
    echo '    "table_count": '${table_count}'' >> "${TMP_JSON}"
    echo '  },' >> "${TMP_JSON}"
}

capture_resource_state() {
    echo "" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    echo "RESOURCE STATE BASELINE" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    
    echo '  "resources": {' >> "${TMP_JSON}"
    
    # PRIMARY resources
    echo "PRIMARY NODE (192.168.168.31):" | tee -a "${TMP_TXT}"
    local primary_resources=$(ssh "ubuntu@${PRIMARY_HOST}" "free -h && echo '---' && df -h && echo '---' && top -bn1 | head -10" 2>/dev/null)
    echo "${primary_resources}" | tee -a "${TMP_TXT}"
    
    # REPLICA resources
    echo "REPLICA NODE (192.168.168.42):" | tee -a "${TMP_TXT}"
    local replica_resources=$(ssh "ubuntu@${REPLICA_HOST}" "free -h && echo '---' && df -h && echo '---' && top -bn1 | head -10" 2>/dev/null)
    echo "${replica_resources}" | tee -a "${TMP_TXT}"
    
    echo '    "primary_memory": "captured",' >> "${TMP_JSON}"
    echo '    "replica_memory": "captured"' >> "${TMP_JSON}"
    echo '  },' >> "${TMP_JSON}"
}

capture_network_state() {
    echo "" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    echo "NETWORK STATE BASELINE" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    
    echo '  "network": {' >> "${TMP_JSON}"
    
    # VIP status
    echo "Virtual IP (192.168.168.50):" | tee -a "${TMP_TXT}"
    if ping -c 3 ${VIP} > /dev/null 2>&1; then
        echo "    ✓ VIP responding" | tee -a "${TMP_TXT}"
        echo '    "vip_status": "responding",' >> "${TMP_JSON}"
    else
        echo "    ✗ VIP not responding" | tee -a "${TMP_TXT}"
        echo '    "vip_status": "not_responding",' >> "${TMP_JSON}"
    fi
    
    # Latency between nodes
    echo "Network latency:" | tee -a "${TMP_TXT}"
    local latency=$(ping -c 10 192.168.168.42 2>/dev/null | grep "avg" | awk -F'/' '{print $5}' || echo "UNKNOWN")
    echo "    Average: ${latency} ms" | tee -a "${TMP_TXT}"
    
    echo '    "latency_ms": "'${latency}'"' >> "${TMP_JSON}"
    echo '  },' >> "${TMP_JSON}"
}

capture_service_state() {
    echo "" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    echo "SERVICE STATE BASELINE" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    
    echo '  "services": {' >> "${TMP_JSON}"
    
    # API health
    echo "GitLab API:" | tee -a "${TMP_TXT}"
    local api_status=$(curl -s -o /dev/null -w "%{http_code}" http://${VIP}/api/v4/health 2>/dev/null || echo "000")
    echo "    Health endpoint: HTTP ${api_status}" | tee -a "${TMP_TXT}"
    
    # Web interface
    echo "GitLab Web:" | tee -a "${TMP_TXT}"
    local web_status=$(curl -s -o /dev/null -w "%{http_code}" http://${VIP}/dashboard 2>/dev/null || echo "000")
    echo "    Dashboard: HTTP ${web_status}" | tee -a "${TMP_TXT}"
    
    # Registry
    echo "Container Registry:" | tee -a "${TMP_TXT}"
    local registry_status=$(curl -s -o /dev/null -w "%{http_code}" http://${VIP}:5050/v2/ 2>/dev/null || echo "000")
    echo "    Registry API: HTTP ${registry_status}" | tee -a "${TMP_TXT}"
    
    echo '    "api_status": '${api_status}',' >> "${TMP_JSON}"
    echo '    "web_status": '${web_status}',' >> "${TMP_JSON}"
    echo '    "registry_status": '${registry_status}'' >> "${TMP_JSON}"
    echo '  },' >> "${TMP_JSON}"
}

capture_deployment_config() {
    echo "" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    echo "DEPLOYMENT CONFIGURATION BASELINE" | tee -a "${TMP_TXT}"
    echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
    
    echo '  "configuration": {' >> "${TMP_JSON}"
    
    # Current compose file
    echo "Docker Compose version:" | tee -a "${TMP_TXT}"
    local compose_version=$(docker-compose --version 2>/dev/null || echo "UNKNOWN")
    echo "    ${compose_version}" | tee -a "${TMP_TXT}"
    
    # Compose file checksum
    echo "Compose file (docker-compose.enterprise.yml):" | tee -a "${TMP_TXT}"
    local compose_hash=$(sha256sum docker-compose.enterprise.yml 2>/dev/null | awk '{print $1}' || echo "UNKNOWN")
    echo "    SHA256: ${compose_hash}" | tee -a "${TMP_TXT}"
    
    # Environment file presence
    echo "Configuration files:" | tee -a "${TMP_TXT}"
    [ -f ".env.production" ] && echo "    ✓ .env.production exists" | tee -a "${TMP_TXT}" || echo "    ✗ .env.production missing" | tee -a "${TMP_TXT}"
    [ -f "docker-compose.enterprise.yml" ] && echo "    ✓ docker-compose.enterprise.yml exists" | tee -a "${TMP_TXT}" || echo "    ✗ docker-compose.enterprise.yml missing" | tee -a "${TMP_TXT}"
    
    echo '    "compose_version": "'${compose_version}'",' >> "${TMP_JSON}"
    echo '    "compose_hash": "'${compose_hash}'"' >> "${TMP_JSON}"
    echo '  }' >> "${TMP_JSON}"
}

################################################################################
# MAIN EXECUTION
################################################################################

echo "Starting pre-deployment baseline capture..."
echo "Timestamp: ${TIMESTAMP}"
echo ""

capture_container_state
capture_database_state
capture_resource_state
capture_network_state
capture_service_state
capture_deployment_config

# Close JSON
echo "}" >> "${TMP_JSON}"

# Copy to final location
cp "${TMP_JSON}" "${JSON_FILE}"
cp "${TMP_TXT}" "${TXT_FILE}"

echo "" | tee -a "${TMP_TXT}"
echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
echo "✓ BASELINE CAPTURE COMPLETE" | tee -a "${TMP_TXT}"
echo "═══════════════════════════════════════════════════════════" | tee -a "${TMP_TXT}"
echo "JSON: ${JSON_FILE}" | tee -a "${TMP_TXT}"
echo "TXT:  ${TXT_FILE}" | tee -a "${TMP_TXT}"
echo "" | tee -a "${TMP_TXT}"
echo "This baseline captures current state for comparison post-deployment." | tee -a "${TMP_TXT}"
echo "Use for: Performance analysis, capacity planning, anomaly detection" | tee -a "${TMP_TXT}"

# Display summary to terminal
echo ""
echo "BASELINE CAPTURE SUMMARY:"
echo "  Containers on PRIMARY: $(ssh "ubuntu@${PRIMARY_HOST}" "docker-compose -f docker-compose.enterprise.yml ps --no-trunc 2>/dev/null | grep 'Up' | wc -l") running"
echo "  Containers on REPLICA: $(ssh "ubuntu@${REPLICA_HOST}" "docker-compose -f docker-compose.enterprise.yml ps --no-trunc 2>/dev/null | grep 'Up' | wc -l") running"
echo "  VIP Status: $(ping -c 1 ${VIP} > /dev/null 2>&1 && echo "✓ Responding" || echo "✗ Not responding")"
echo "  Files saved: ${BASELINE_FILE}.{json,txt}"
echo ""
echo "✓ Ready for May 1 deployment"
