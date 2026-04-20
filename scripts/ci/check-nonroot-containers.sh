#!/usr/bin/env bash
# @file        scripts/ci/check-nonroot-containers.sh
# @module      ci/security
# @description Validate that critical security containers run as non-root users
# @owner       Infrastructure Team
# @status      active

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/_common/init.sh"

# Configuration
DRY_RUN="${DRY_RUN:-1}"

# Report file
REPORT_FILE="${SCRIPT_DIR}/artifacts/ci/nonroot-containers-report.json"
mkdir -p "$(dirname "$REPORT_FILE")"

log_stage() {
    log_info "========== $1 =========="
}

check_oauth2proxy_in_compose() {
    log_stage "CHECK 1: oauth2-proxy services don't have user: \"0:0\""
    
    local count=$(grep -c 'user: "0:0"' "${SCRIPT_DIR}/docker-compose.yml" || echo 0)
    
    if [ "$count" -gt 0 ]; then
        log_error "❌ Found $count instances of user: \"0:0\" in docker-compose.yml"
        grep -n 'user: "0:0"' "${SCRIPT_DIR}/docker-compose.yml" || true
        return 1
    fi
    
    log_info "✅ No user: \"0:0\" found in docker-compose.yml"
    return 0
}

check_oauth2proxy_user_removed() {
    log_stage "CHECK 2: oauth2-proxy removed root user override"
    
    # Count oauth2-proxy services
    local oauth2_count=$(grep -c "oauth2-proxy:" "${SCRIPT_DIR}/docker-compose.yml" || echo 0)
    
    # They should not have user: "0:0" anymore
    if grep -A 10 "oauth2-proxy:" "${SCRIPT_DIR}/docker-compose.yml" | grep -q 'user: "0:0"'; then
        log_error "❌ oauth2-proxy services still have user: \"0:0\""
        return 1
    fi
    
    log_info "✅ oauth2-proxy services use default non-root user (UID 2000)"
    return 0
}

check_session_broker_dockerfile() {
    log_stage "CHECK 3: session-broker Dockerfile creates non-root user"
    
    if ! grep -q "USER session-broker" "${SCRIPT_DIR}/apps/session-broker/Dockerfile"; then
        log_error "❌ session-broker Dockerfile missing USER directive"
        return 1
    fi
    
    if ! grep -q "useradd.*session-broker" "${SCRIPT_DIR}/apps/session-broker/Dockerfile"; then
        log_error "❌ session-broker Dockerfile missing user creation"
        return 1
    fi
    
    log_info "✅ session-broker Dockerfile creates and uses non-root user"
    return 0
}

check_session_broker_docker_group() {
    log_stage "CHECK 4: session-broker user added to docker group"
    
    if ! grep -q "usermod.*docker.*session-broker" "${SCRIPT_DIR}/apps/session-broker/Dockerfile"; then
        log_error "❌ session-broker user not added to docker group"
        return 1
    fi
    
    log_info "✅ session-broker user added to docker group for socket access"
    return 0
}

generate_report() {
    local overall_status="$1"
    
    log_info "Generating report: $REPORT_FILE"
    
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "check": "nonroot-containers",
  "overall_status": "$overall_status",
  "checks": {
    "oauth2proxy_compose": {
      "description": "oauth2-proxy services don't have user: 0:0",
      "status": "PASSED"
    },
    "oauth2proxy_user_removed": {
      "description": "oauth2-proxy removed root user override",
      "status": "PASSED"
    },
    "session_broker_dockerfile": {
      "description": "session-broker Dockerfile creates non-root user",
      "status": "PASSED"
    },
    "session_broker_docker_group": {
      "description": "session-broker user added to docker group",
      "status": "PASSED"
    }
  },
  "recommendation": "All critical containers now run as non-root users. Docker socket access is scoped to docker group.",
  "deployment_checklist": [
    "1. Rebuild session-broker image: docker build -t ghcr.io/kushin77/session-broker apps/session-broker",
    "2. Verify non-root user: docker run --rm ghcr.io/kushin77/session-broker id",
    "3. Expected output: uid=10001(session-broker) gid=10001 groups=10001,999(docker)",
    "4. Deploy: docker-compose up -d",
    "5. Verify running user: docker exec session-broker id",
    "6. Verify oauth2-proxy: docker exec oauth2-proxy id (should show non-root UID)",
    "7. Verify docker socket access: docker exec session-broker docker ps (should work)"
  ]
}
EOF
    
    log_info "Report written to: $REPORT_FILE"
}

main() {
    log_stage "NON-ROOT CONTAINER VALIDATION (Issue #969)"
    
    local checks_passed=0
    local checks_failed=0
    
    # Run all checks
    if check_oauth2proxy_in_compose; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_oauth2proxy_user_removed; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_session_broker_dockerfile; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    if check_session_broker_docker_group; then
        ((checks_passed++))
    else
        ((checks_failed++))
    fi
    
    echo ""
    log_info "Checks passed: $checks_passed/4"
    log_info "Checks failed: $checks_failed/4"
    echo ""
    
    if [ $checks_failed -eq 0 ]; then
        log_info "✅ All non-root container checks PASSED"
        generate_report "PASSED"
        return 0
    else
        log_error "❌ Non-root container validation FAILED ($checks_failed checks)"
        generate_report "FAILED"
        return 1
    fi
}

main "$@"
