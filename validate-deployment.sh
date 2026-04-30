#!/bin/bash

################################################################################
# Hermes Agent Portal - Deployment Validation Script
# Purpose: Comprehensive post-deployment validation with detailed reporting
# Usage: ./validate-deployment.sh [report-format]
#        ./validate-deployment.sh json    # Output as JSON
#        ./validate-deployment.sh html    # Output as HTML
# Date: April 30, 2026
################################################################################

set -e

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/validate_*.tmp 2>/dev/null || true' EXIT

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FORMAT=${1:-text}  # text, json, or html
REPORT_DIR="deployment-reports"
REPORT_FILE="$REPORT_DIR/validation_${TIMESTAMP}.${REPORT_FORMAT}"
CONFIG_FILE="docker-compose.enterprise.yml"

# Counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

mkdir -p "$REPORT_DIR"

################################################################################
# Report Functions
################################################################################

report_header() {
    if [ "$REPORT_FORMAT" = "json" ]; then
        echo "{" > "$REPORT_FILE"
        echo "  \"deployment_validation\": {" >> "$REPORT_FILE"
        echo "    \"timestamp\": \"$(date -I'seconds')\","  >> "$REPORT_FILE"
        echo "    \"results\": [" >> "$REPORT_FILE"
    elif [ "$REPORT_FORMAT" = "html" ]; then
        cat > "$REPORT_FILE" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Deployment Validation Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        h1 { color: #333; }
        .container { background-color: white; padding: 20px; border-radius: 5px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #4CAF50; color: white; }
        tr:hover { background-color: #f5f5f5; }
        .pass { color: green; font-weight: bold; }
        .fail { color: red; font-weight: bold; }
        .summary { margin-top: 20px; padding: 10px; background-color: #f0f0f0; border-radius: 5px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Deployment Validation Report</h1>
        <p>Generated: $(date)</p>
        <table>
            <tr>
                <th>Check</th>
                <th>Category</th>
                <th>Result</th>
                <th>Details</th>
            </tr>
EOF
    else
        cat > "$REPORT_FILE" << EOF
═══════════════════════════════════════════════════════════════════════════════
Deployment Validation Report
Generated: $(date)
═══════════════════════════════════════════════════════════════════════════════

EOF
    fi
}

record_check() {
    local check_name="$1"
    local category="$2"
    local status="$3"
    local details="$4"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if [ "$status" = "PASS" ]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        status_symbol="✓"
        status_color="$GREEN"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        status_symbol="✗"
        status_color="$RED"
    fi
    
    if [ "$REPORT_FORMAT" = "json" ]; then
        local json_status=$([ "$status" = "PASS" ] && echo "true" || echo "false")
        echo "    {\"check\": \"$check_name\", \"category\": \"$category\", \"passed\": $json_status, \"details\": \"$details\"}," >> "$REPORT_FILE"
    elif [ "$REPORT_FORMAT" = "html" ]; then
        local html_status=$([ "$status" = "PASS" ] && echo "<span class=\"pass\">PASS</span>" || echo "<span class=\"fail\">FAIL</span>")
        echo "            <tr><td>$check_name</td><td>$category</td><td>$html_status</td><td>$details</td></tr>" >> "$REPORT_FILE"
    else
        echo -e "[$status_symbol] $check_name ($category)" >> "$REPORT_FILE"
        echo "    Details: $details" >> "$REPORT_FILE"
    fi
    
    echo -e "${status_color}[$status_symbol]${NC} $check_name ($category): $details"
}

report_footer() {
    local pass_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    
    if [ "$REPORT_FORMAT" = "json" ]; then
        # Remove last comma
        sed -i '$ s/,$//' "$REPORT_FILE"
        echo "    ]," >> "$REPORT_FILE"
        echo "    \"summary\": {" >> "$REPORT_FILE"
        echo "      \"total_checks\": $TOTAL_CHECKS," >> "$REPORT_FILE"
        echo "      \"passed\": $PASSED_CHECKS," >> "$REPORT_FILE"
        echo "      \"failed\": $FAILED_CHECKS," >> "$REPORT_FILE"
        echo "      \"pass_rate\": \"${pass_rate}%\"" >> "$REPORT_FILE"
        echo "    }" >> "$REPORT_FILE"
        echo "  }" >> "$REPORT_FILE"
        echo "}" >> "$REPORT_FILE"
    elif [ "$REPORT_FORMAT" = "html" ]; then
        cat >> "$REPORT_FILE" << EOF
        </table>
        <div class="summary">
            <h2>Summary</h2>
            <p><strong>Total Checks:</strong> $TOTAL_CHECKS</p>
            <p><strong>Passed:</strong> $PASSED_CHECKS</p>
            <p><strong>Failed:</strong> $FAILED_CHECKS</p>
            <p><strong>Pass Rate:</strong> ${pass_rate}%</p>
        </div>
    </div>
</body>
</html>
EOF
    else
        cat >> "$REPORT_FILE" << EOF

═══════════════════════════════════════════════════════════════════════════════
Summary
═══════════════════════════════════════════════════════════════════════════════
Total Checks:  $TOTAL_CHECKS
Passed:        $PASSED_CHECKS
Failed:        $FAILED_CHECKS
Pass Rate:     ${pass_rate}%
═══════════════════════════════════════════════════════════════════════════════
EOF
    fi
}

################################################################################
# Validation Checks
################################################################################

validate_containers() {
    echo ""
    echo -e "${BLUE}Validating Containers...${NC}"
    
    for container in appsmith hermes-integration code-server-ide code-server-postgres code-server-redis; do
        local status=$(docker ps --filter "name=$container" --format "{{.State}}")
        
        if [ "$status" = "running" ]; then
            local health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "unknown")
            if [ "$health" = "healthy" ] || [ "$health" = "unknown" ]; then
                record_check "Container: $container" "Containers" "PASS" "Running"
            else
                record_check "Container: $container" "Containers" "FAIL" "Running but unhealthy"
            fi
        else
            record_check "Container: $container" "Containers" "FAIL" "Not running"
        fi
    done
}

validate_api() {
    echo ""
    echo -e "${BLUE}Validating API...${NC}"
    
    # Health endpoint
    local health=$(curl -s -k -m 5 https://kushnir.cloud/api/hermes/health | jq -r '.status' 2>/dev/null)
    [ "$health" = "healthy" ] && record_check "API Health" "API" "PASS" "Health endpoint responding" || record_check "API Health" "API" "FAIL" "Health endpoint not responding"
    
    # Metrics endpoint
    local metrics=$(curl -s -k -m 5 https://kushnir.cloud/api/hermes/metrics | jq -r '.platform_phases' 2>/dev/null)
    [ "$metrics" = "250" ] && record_check "API Metrics" "API" "PASS" "All 250 phases available" || record_check "API Metrics" "API" "FAIL" "Metrics endpoint issue"
}

validate_database() {
    echo ""
    echo -e "${BLUE}Validating Database...${NC}"
    
    local result=$(docker exec code-server-postgres psql -U postgres -d code-server-db -c "SELECT 1;" 2>&1)
    [ -n "$(echo "$result" | grep '(1 row)')" ] && record_check "Database Connection" "Database" "PASS" "PostgreSQL responsive" || record_check "Database Connection" "Database" "FAIL" "PostgreSQL not responsive"
}

validate_security() {
    echo ""
    echo -e "${BLUE}Validating Security...${NC}"
    
    # TLS version
    local tls=$(echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | grep "Protocol" | awk '{print $NF}')
    [[ "$tls" =~ TLSv1.2|TLSv1.3 ]] && record_check "TLS Version" "Security" "PASS" "$tls enabled" || record_check "TLS Version" "Security" "FAIL" "Weak TLS version"
    
    # SSL certificate
    local cert_valid=$(echo | openssl s_client -connect kushnir.cloud:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null)
    [ -n "$cert_valid" ] && record_check "SSL Certificate" "Security" "PASS" "Valid certificate" || record_check "SSL Certificate" "Security" "FAIL" "Invalid certificate"
    
    # Security headers
    local hsts=$(curl -s -k -I https://kushnir.cloud | grep -i "strict-transport-security")
    [ -n "$hsts" ] && record_check "HSTS Header" "Security" "PASS" "HSTS enabled" || record_check "HSTS Header" "Security" "FAIL" "HSTS not found"
}

validate_dns() {
    echo ""
    echo -e "${BLUE}Validating DNS...${NC}"
    
    local dns=$(nslookup kushnir.cloud 2>&1 | grep "192.168.168.31")
    [ -n "$dns" ] && record_check "DNS Resolution" "Network" "PASS" "kushnir.cloud resolves correctly" || record_check "DNS Resolution" "Network" "FAIL" "DNS resolution issue"
}

validate_resources() {
    echo ""
    echo -e "${BLUE}Validating Resources...${NC}"
    
    # Disk space
    local disk=$(df -h /home | tail -1 | awk '{print $5}' | sed 's/%//')
    [ "$disk" -lt 80 ] && record_check "Disk Space" "Resources" "PASS" "${disk}% used" || record_check "Disk Space" "Resources" "FAIL" "${disk}% used - running low"
}

################################################################################
# Main
################################################################################

main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}Deployment Validation Script${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Report Format: $REPORT_FORMAT"
    echo "Report File: $REPORT_FILE"
    echo ""
    
    report_header
    
    validate_containers
    validate_api
    validate_database
    validate_security
    validate_dns
    validate_resources
    
    report_footer
    
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "Report saved to: ${BLUE}$REPORT_FILE${NC}"
    echo -e "Pass Rate: ${GREEN}${PASSED_CHECKS}/${TOTAL_CHECKS}${NC} ($(( PASSED_CHECKS * 100 / TOTAL_CHECKS ))%)"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    [ $FAILED_CHECKS -eq 0 ] && exit 0 || exit 1
}

main "$@"
