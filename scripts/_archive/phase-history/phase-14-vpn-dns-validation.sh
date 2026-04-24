#!/bin/bash
# phase-14-vpn-dns-validation.sh
# VPN-aware DNS and TLS testing for ide.kushnir.cloud
# Ensures tests see exactly what end-users will see through VPN
# IaC-compliant: idempotent, immutable, audited

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/phase-14-vpn-dns-validation.log}"
DOMAIN="${DOMAIN:-ide.kushnir.cloud}"
TARGET_IP="${TARGET_IP:-192.168.168.31}"
VPN_CHECK_TIMEOUT=10

# Logging
log() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] ❌ ERROR: $*" | tee -a "$LOG_FILE"
    return 1
}

success() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] ✅ $*" | tee -a "$LOG_FILE"
}

warning() {
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] ⚠️  $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# 1. VPN STATUS CHECK
# ============================================================================
check_vpn_status() {
    log "=== VPN STATUS CHECK ==="
    
    local vpn_status="unknown"
    local vpn_ip="none"
    
    # Check common VPN indicators
    if ip link show | grep -q "tun"; then
        vpn_status="active (tun interface detected)"
        vpn_ip=$(ip addr show | grep -E '10\.' | awk '{print $2}' | head -1)
    elif ip link show | grep -q "wg"; then
        vpn_status="active (wireguard interface detected)"
        vpn_ip=$(ip addr show | grep -E '10\.' | awk '{print $2}' | head -1)
    elif netstat -rn 2>/dev/null | grep -q "tun\|wg"; then
        vpn_status="active (routing table shows VPN)"
        vpn_ip=$(hostname -I | awk '{print $1}')
    else
        warning "VPN status unknown - tests may not match user experience"
        vpn_status="unknown"
    fi
    
    log "VPN Status: $vpn_status"
    log "Local IP: $vpn_ip"
    
    echo "status:$vpn_status|ip:$vpn_ip"
}

# ============================================================================
# 2. DNS RESOLUTION TEST (VPN-aware)
# ============================================================================
test_dns_resolution() {
    log "=== DNS RESOLUTION TEST (VPN-aware) ==="
    
    local resolved_ip=""
    local dns_server=""
    
    # Get current DNS servers (respects VPN DNS settings)
    dns_server=$(grep -m1 "^nameserver" /etc/resolv.conf 2>/dev/null || echo "system-default")
    log "Using DNS server: $dns_server"
    
    # Test DNS resolution (this will use VPN DNS if VPN is active)
    if resolved_ip=$(timeout $VPN_CHECK_TIMEOUT dig +short "$DOMAIN" A @"$dns_server" 2>/dev/null | head -1); then
        if [ -z "$resolved_ip" ]; then
            error "DNS query returned empty - domain may not be propagated yet"
            return 1
        fi
        
        log "Resolved: $DOMAIN → $resolved_ip"
        
        # Verify it matches expected IP
        if [ "$resolved_ip" = "$TARGET_IP" ]; then
            success "DNS resolution correct: $DOMAIN → $TARGET_IP"
            echo "resolved:true|ip:$resolved_ip"
            return 0
        else
            warning "DNS resolved to $resolved_ip, expected $TARGET_IP"
            echo "resolved:true|ip:$resolved_ip"
            return 1
        fi
    else
        error "DNS resolution failed (timeout or invalid response)"
        return 1
    fi
}

# ============================================================================
# 3. CONNECTIVITY TEST (Through VPN routing)
# ============================================================================
test_connectivity() {
    log "=== CONNECTIVITY TEST (VPN routing) ==="
    
    # Test ICMP (ping) - respects VPN routing
    if ping -c 1 -W 5 "$DOMAIN" &>/dev/null || ping -c 1 -W 5 "$TARGET_IP" &>/dev/null; then
        success "Ping successful to $DOMAIN / $TARGET_IP"
        echo "ping:success"
        return 0
    else
        warning "Ping failed (may be blocked by firewall, continuing with other tests)"
        echo "ping:blocked-or-failed"
        return 0  # Don't fail - firewall may block ICMP
    fi
}

# ============================================================================
# 4. TLS HANDSHAKE TEST (VPN-aware)
# ============================================================================
test_tls_handshake() {
    log "=== TLS HANDSHAKE TEST (VPN routing, permitting self-signed) ==="
    
    local tls_result=""
    local cert_cn=""
    local issuer=""
    
    # Test TLS handshake - uses VPN routing, accepts self-signed temporarily
    tls_result=$(timeout 10 openssl s_client -connect "$DOMAIN:443" \
        -servername "$DOMAIN" \
        -showcerts \
        </dev/null 2>&1 || echo "CONNECT_FAILED")
    
    if echo "$tls_result" | grep -q "Verify return code: 0"; then
        success "TLS handshake successful (CA-verified certificate)"
        echo "tls:success|cert-type:ca-signed"
        return 0
        
    elif echo "$tls_result" | grep -q "Verify return code: 19\|self signed"; then
        warning "TLS handshake successful with self-signed certificate (TEMPORARY)"
        cert_cn=$(echo "$tls_result" | grep "Subject:" | sed 's/.*CN=\([^,/]*\).*/\1/' | head -1)
        log "Self-signed certificate CN: $cert_cn"
        
        if [ "$cert_cn" == "$DOMAIN" ]; then
            success "Self-signed certificate CN matches domain ($DOMAIN)"
            echo "tls:success|cert-type:self-signed|cn-match:true"
            return 0
        else
            error "Self-signed certificate CN mismatch: got $cert_cn, expected $DOMAIN"
            echo "tls:success|cert-type:self-signed|cn-match:false"
            return 1
        fi
        
    elif echo "$tls_result" | grep -q "CONNECT_FAILED\|Connection refused\|No such file"; then
        error "TLS connection failed - cannot reach $DOMAIN:443"
        echo "tls:failed|reason:connection-refused"
        return 1
    else
        error "TLS handshake failed with unknown error"
        echo "$tls_result" >> "$LOG_FILE"
        return 1
    fi
}

# ============================================================================
# 5. HTTPS RESPONSE TEST (VPN routing)
# ============================================================================
test_https_response() {
    log "=== HTTPS RESPONSE TEST (VPN routing) ==="
    
    local http_code=""
    local response_time=""
    
    # Test actual HTTPS request through VPN
    if ! command -v curl &>/dev/null; then
        warning "curl not available, skipping HTTP response test"
        return 0
    fi
    
    # Use curl with VPN routing, accept self-signed temporarily
    http_code=$(timeout 10 curl -kI -w "%{http_code}" "$DOMAIN:443/" 2>/dev/null | tail -1)
    
    if [ -z "$http_code" ]; then
        error "No HTTP response from $DOMAIN:443"
        return 1
    fi
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        success "HTTPS response OK (HTTP $http_code)"
        echo "https:success|code:$http_code"
        return 0
    else
        warning "Unexpected HTTP response code: $http_code"
        echo "https:response|code:$http_code"
        return 1
    fi
}

# ============================================================================
# 6. OAUTH2 FLOW TEST (VPN-aware)
# ============================================================================
test_oauth2_flow() {
    log "=== OAUTH2 FLOW TEST (VPN routing) ==="
    
    if ! command -v curl &>/dev/null; then
        warning "curl not available, skipping OAuth2 flow test"
        return 0
    fi
    
    # Test OAuth2 start endpoint - should redirect to Google OAuth
    local oauth_response=""
    oauth_response=$(timeout 10 curl -kL -w "%{http_code}" "$DOMAIN/oauth2/start?rd=%2F" 2>/dev/null | tail -1)
    
    if [ "$oauth_response" = "200" ] || [ "$oauth_response" = "302" ]; then
        success "OAuth2 flow redirect working (HTTP $oauth_response)"
        echo "oauth2:working|code:$oauth_response"
        return 0
    else
        warning "OAuth2 flow response: $oauth_response"
        echo "oauth2:response|code:$oauth_response"
        return 1
    fi
}

# ============================================================================
# 7. COMPREHENSIVE REPORT
# ============================================================================
generate_report() {
    log "=== Phase 14 VPN-Aware Validation Report ==="
    log ""
    log "Domain: $DOMAIN"
    log "Target IP: $TARGET_IP"
    log "Test Timestamp: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    log "Environment: VPN-aware (using system DNS and routing)"
    log ""
    log "=== Test Results ==="
    
    # Run all tests and collect results
    local vpn_result=$(check_vpn_status)
    local dns_result=$(test_dns_resolution || echo "resolved:false")
    local connectivity=$(test_connectivity || echo "ping:failed")
    local tls_result=$(test_tls_handshake || echo "tls:failed")
    local https_result=$(test_https_response || echo "https:failed")
    local oauth2_result=$(test_oauth2_flow || echo "oauth2:failed")
    
    log ""
    log "=== Test Summary ==="
    log "VPN Status: $(echo "$vpn_result" | cut -d'|' -f1)"
    log "DNS Resolution: $(echo "$dns_result" | cut -d'|' -f1)"
    log "Connectivity: $(echo "$connectivity" | cut -d'|' -f1)"
    log "TLS Handshake: $(echo "$tls_result" | cut -d'|' -f1)"
    log "HTTPS Response: $(echo "$https_result" | cut -d'|' -f1)"
    log "OAuth2 Flow: $(echo "$oauth2_result" | cut -d'|' -f1)"
    
    log ""
    log "=== Critical Requirements Check ==="
    
    # Determine pass/fail
    local dns_ok=$(echo "$dns_result" | grep -q "resolved:true" && echo "✅" || echo "❌")
    local tls_ok=$(echo "$tls_result" | grep -q "tls:success" && echo "✅" || echo "❌")
    local https_ok=$(echo "$https_result" | grep -q "https:success" && echo "✅" || echo "❌")
    
    log "$dns_ok DNS Resolution: $DOMAIN resolves to IP"
    log "$tls_ok TLS Handshake: Certificate loads without fatal errors"
    log "$https_ok HTTPS Response: Web server responds on port 443"
    
    # Final verdict
    if [[ "$dns_ok" == "✅" ]] && [[ "$tls_ok" == "✅" ]] && [[ "$https_ok" == "✅" ]]; then
        success "Phase 14 VPN-aware validation PASSED ✅"
        log "All critical requirements met - safe to proceed with launch"
        return 0
    else
        error "Phase 14 VPN-aware validation FAILED ❌"
        log "One or more critical requirements not met"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    log "=== Phase 14 VPN-Aware DNS Validation Script ==="
    log "Script: phase-14-vpn-dns-validation.sh"
    log "Purpose: Validate DNS and TLS from end-user perspective (via VPN)"
    log "Log File: $LOG_FILE"
    log ""
    
    generate_report
}

main "$@"
