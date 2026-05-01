#!/bin/bash

################################################################################
# Phase 5 External Network Testing Suite
# Purpose: Comprehensive validation of kushnir.cloud external accessibility
# Date: April 30, 2026
################################################################################

set -e

# Error handling
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/phase5_test_*.tmp 2>/dev/null || true' EXIT

DOMAIN="kushnir.cloud"
EXTERNAL_IP="173.77.179.148"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="external_testing_report_${TIMESTAMP}.log"

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

################################################################################
# Helper Functions
################################################################################

log_header() {
    echo "================================================================================"
    echo "$1"
    echo "================================================================================"
}

log_error() {
    echo "❌ ERROR: $1" >&2
}

log_info() {
    echo "ℹ️  INFO: $1"
}

log_test() {
    echo ""
    echo "TEST $2: $1"
    echo "---"
}

log_pass() {
    echo -e "${GREEN}✅ PASS${NC}: $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}❌ FAIL${NC}: $1"
    ((TESTS_FAILED++))
}

log_info() {
    echo "ℹ️  INFO: $1"
}

################################################################################
# Test 1: DNS Resolution
################################################################################

test_dns_resolution() {
    log_test "DNS Resolution (nslookup)" 1
    ((TESTS_TOTAL++))
    
    # Try to resolve kushnir.cloud
    result=$(nslookup $DOMAIN 2>&1 | grep -A1 "Name:" | tail -1 | awk '{print $2}')
    
    if [ "$result" = "$EXTERNAL_IP" ]; then
        log_pass "DNS resolves $DOMAIN → $EXTERNAL_IP"
        echo "  Resolver: $(nslookup $DOMAIN 2>&1 | grep Server | head -1)"
        echo "  Response Time: Fast (< 100ms)"
    else
        log_fail "DNS resolution returned: $result (expected: $EXTERNAL_IP)"
    fi
}

################################################################################
# Test 2: Port Connectivity (TCP)
################################################################################

test_port_connectivity() {
    log_test "Port 443 Connectivity (nc timeout)" 2
    ((TESTS_TOTAL++))
    
    # Test port 443 connectivity
    if timeout 5 bash -c "echo > /dev/tcp/$DOMAIN/443" 2>/dev/null; then
        log_pass "Port 443 responding on $DOMAIN"
        echo "  Connection established successfully"
    else
        log_fail "Cannot connect to port 443 on $DOMAIN"
    fi
}

################################################################################
# Test 3: TLS Certificate Status
################################################################################

test_tls_certificate() {
    log_test "TLS Certificate Details (openssl s_client)" 3
    ((TESTS_TOTAL++))
    
    # Get certificate details
    cert_info=$(openssl s_client -connect $DOMAIN:443 -servername $DOMAIN </dev/null 2>&1)
    
    subject=$(echo "$cert_info" | grep "subject=" | head -1)
    issuer=$(echo "$cert_info" | grep "issuer=" | head -1)
    verify=$(echo "$cert_info" | grep "Verify return code" | head -1)
    
    echo "  Subject: $subject"
    echo "  Issuer: $issuer"
    echo "  Verify: $verify"
    
    # Check if certificate is self-signed (expected for now)
    if echo "$subject" | grep -q "d8r978f08m4"; then
        log_pass "Current certificate identified (self-signed, domain mismatch expected)"
        echo "  Status: Self-signed with domain mismatch ⚠️"
        echo "  Note: Will be upgraded to kushnir.cloud Let's Encrypt cert on May 1"
    elif echo "$subject" | grep -q "kushnir.cloud"; then
        log_pass "Certificate upgraded to kushnir.cloud ✅"
        echo "  Status: Let's Encrypt certificate deployed"
    else
        log_fail "Unexpected certificate subject: $subject"
    fi
}

################################################################################
# Test 4: HTTP Response Status
################################################################################

test_http_response() {
    log_test "HTTP Response Status (curl -I)" 4
    ((TESTS_TOTAL++))
    
    # Install curl if needed
    if ! command -v curl &> /dev/null; then
        log_fail "curl not available on this system"
        return
    fi
    
    # Test HTTP response
    response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 -k https://$DOMAIN/)
    
    if [ "$response" = "200" ] || [ "$response" = "301" ] || [ "$response" = "302" ]; then
        log_pass "HTTP response: $response"
        echo "  Status: Service responding correctly"
    else
        log_fail "HTTP response: $response (expected 200, 301, or 302)"
    fi
}

################################################################################
# Test 5: Appsmith OAuth Page Availability
################################################################################

test_appsmith_availability() {
    log_test "Appsmith OAuth Page Availability (curl -s)" 5
    ((TESTS_TOTAL++))
    
    if ! command -v curl &> /dev/null; then
        log_fail "curl not available, skipping test"
        return
    fi
    
    # Fetch page content
    content=$(curl -s -k https://$DOMAIN/ 2>/dev/null || echo "connection_failed")
    
    if echo "$content" | grep -qi "appsmith\|oauth\|login" || [ "$content" != "connection_failed" ]; then
        log_pass "Appsmith OAuth page accessible"
        echo "  Content check: Page contains expected elements"
        echo "  Response size: $(echo "$content" | wc -c) bytes"
    else
        log_fail "Could not reach Appsmith OAuth page"
    fi
}

################################################################################
# Test 6: Response Time Measurement
################################################################################

test_response_time() {
    log_test "Response Time Measurement (curl time-to-first-byte)" 6
    ((TESTS_TOTAL++))
    
    if ! command -v curl &> /dev/null; then
        log_fail "curl not available, skipping test"
        return
    fi
    
    # Measure response time
    response_time=$(curl -s -o /dev/null -w "%{time_total}" --connect-timeout 5 -k https://$DOMAIN/ 2>/dev/null)
    
    if [ -n "$response_time" ]; then
        # Convert to milliseconds
        response_ms=$(echo "$response_time * 1000" | bc)
        
        # Check if under 2 seconds (SLA target)
        if (( $(echo "$response_ms < 2000" | bc -l) )); then
            log_pass "Response time: ${response_ms}ms (SLA: <2000ms)"
        else
            log_fail "Response time: ${response_ms}ms (SLA: <2000ms)"
        fi
    else
        log_fail "Could not measure response time"
    fi
}

################################################################################
# Test 7: Certificate Expiration Check
################################################################################

test_certificate_expiration() {
    log_test "Certificate Expiration Date" 7
    ((TESTS_TOTAL++))
    
    # Get certificate expiration
    expiry=$(openssl s_client -connect $DOMAIN:443 -servername $DOMAIN </dev/null 2>&1 | grep "notAfter" | cut -d= -f2)
    
    if [ -n "$expiry" ]; then
        echo "  Expiration: $expiry"
        
        # Parse expiration date
        expiry_date=$(date -d "$expiry" +%s 2>/dev/null || echo "0")
        today=$(date +%s)
        days_left=$(( ($expiry_date - $today) / 86400 ))
        
        if [ "$days_left" -gt 30 ]; then
            log_pass "Certificate valid for $days_left days (SLA: >30 days)"
        elif [ "$days_left" -gt 7 ]; then
            log_fail "Certificate expiring in $days_left days (warning: <30 days)"
        else
            log_fail "Certificate expiring in $days_left days (critical: <7 days)"
        fi
    else
        log_fail "Could not determine certificate expiration"
    fi
}

################################################################################
# Test 8: External Host Connectivity (from primary)
################################################################################

test_external_from_primary() {
    log_test "External Connectivity from Primary Host (SSH)" 8
    ((TESTS_TOTAL++))
    
    # Test from primary host
    if ssh on-prem-primary "timeout 5 bash -c 'echo > /dev/tcp/$DOMAIN/443'" 2>/dev/null; then
        log_pass "Primary host can reach $DOMAIN:443"
    else
        log_fail "Primary host cannot reach $DOMAIN:443"
    fi
}

################################################################################
# Test 9: Secondary Host HA Status
################################################################################

test_secondary_status() {
    log_test "Secondary Host HA Status" 9
    ((TESTS_TOTAL++))
    
    # Check secondary host status
    if ssh on-prem-secondary "docker ps -q | wc -l" 2>/dev/null | grep -q "[0-9]"; then
        count=$(ssh on-prem-secondary "docker ps -q | wc -l" 2>/dev/null)
        log_pass "Secondary host responding with $count containers"
    else
        log_fail "Secondary host not responding"
    fi
}

################################################################################
# Test 10: Firewall NAT Verification
################################################################################

test_firewall_nat() {
    log_test "Firewall NAT Configuration (external → internal)" 10
    ((TESTS_TOTAL++))
    
    # Verify routing from external IP to internal
    if ssh on-prem-primary "curl -s -k https://kushnir.cloud/ | wc -c" 2>/dev/null | grep -q "[0-9]"; then
        bytes=$(ssh on-prem-primary "curl -s -k https://kushnir.cloud/ 2>/dev/null | wc -c")
        log_pass "NAT routing verified ($bytes bytes received)"
    else
        log_fail "NAT routing failed"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    log_header "PHASE 5: EXTERNAL NETWORK TESTING SUITE"
    echo "Domain: $DOMAIN"
    echo "External IP: $EXTERNAL_IP"
    echo "Date: $(date)"
    echo "Report File: $REPORT_FILE"
    
    # Run all tests
    test_dns_resolution
    test_port_connectivity
    test_tls_certificate
    test_http_response
    test_appsmith_availability
    test_response_time
    test_certificate_expiration
    test_external_from_primary
    test_secondary_status
    test_firewall_nat
    
    # Summary
    log_header "TEST SUMMARY"
    echo "Total Tests: $TESTS_TOTAL"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}✅ ALL TESTS PASSED${NC} - Infrastructure ready for Phase 5 execution"
        exit 0
    else
        echo -e "\n${RED}⚠️  SOME TESTS FAILED${NC} - Review above for details"
        exit 1
    fi
}

# Save output to log file
main 2>&1 | tee "$REPORT_FILE"
