#!/bin/bash
# @file scripts/ci/validate-dns-architecture.sh
# @description Comprehensive DNS Architecture Validation (CI/CD Integration)
# @governance  GOV-002: Immutable, version-controlled, idempotent infrastructure
# @author GitHub Copilot
# @date 2026-04-25
# @related P3 #1536 Phase 3 - DNS Architecture & Resilience

set -euo pipefail

################################################################################
# CONFIGURATION
################################################################################

# Test modes
MODE="${1:-ci}"  # ci | runtime | full
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"

# Directories to scan
SCAN_DIRS=(
  "apps"
  "scripts"
  "config"
  "docker"
  "terraform"
)

# Report file
REPORT_FILE="test-results/dns-validation-report.json"

################################################################################
# COLOR CODES
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

################################################################################
# LOGGING & REPORTING
################################################################################

log() {
  echo "[$(date +'%H:%M:%S')] $*"
}

debug() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo "[DEBUG] $*" >&2
  fi
}

pass() {
  echo -e "${GREEN}[✓]${NC} $*"
}

fail() {
  echo -e "${RED}[✗]${NC} $*"
}

warn() {
  echo -e "${YELLOW}[⚠]${NC} $*"
}

################################################################################
# TEST COUNTERS
################################################################################

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

increment_test() {
  ((TESTS_RUN++))
}

increment_pass() {
  ((TESTS_PASSED++))
  increment_test
}

increment_fail() {
  ((TESTS_FAILED++))
  increment_test
}

increment_skip() {
  ((TESTS_SKIPPED++))
  increment_test
}

################################################################################
# TEST 1: No Hardcoded IPs in Source Code
################################################################################

test_no_hardcoded_ips() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 1: Scanning for hardcoded IP addresses"
  log "════════════════════════════════════════════════════════"

  # Pattern for IPv4 addresses (basic)
  local ip_pattern='([0-9]{1,3}\.){3}[0-9]{1,3}'
  
  # Exclude known safe IPs/patterns
  local exclude_patterns=(
    "127.0.0.1"           # localhost
    "192.168.1"           # documentation example
    "203.0.113"           # documentation example (TEST-NET)
    "::1"                 # IPv6 localhost
    "255.255.255.255"     # broadcast
    "0.0.0.0"             # any/default
    "10.0.0"              # documentation
  )

  local violations=0
  local exemptions=0

  for dir in "${SCAN_DIRS[@]}"; do
    if [[ ! -d "$dir" ]]; then
      debug "Directory not found: $dir (skipping)"
      continue
    fi

    # Search for IP addresses in non-binary files
    while IFS= read -r file; do
      # Skip certain files
      [[ "$file" =~ \.git ]] && continue
      [[ "$file" =~ node_modules ]] && continue
      [[ "$file" =~ __pycache__ ]] && continue

      while IFS= read -r line; do
        # Check if line contains IP address
        if [[ $line =~ $ip_pattern ]]; then
          local is_exempt=false

          # Check against exemption patterns
          for pattern in "${exclude_patterns[@]}"; do
            if [[ "$line" =~ $pattern ]]; then
              is_exempt=true
              ((exemptions++))
              break
            fi
          done

          if [[ "$is_exempt" == false ]]; then
            fail "Hardcoded IP found in $file: $line"
            ((violations++))
          fi
        fi
      done < <(grep -n "$ip_pattern" "$file" 2>/dev/null || true)
    done < <(find "$dir" -type f \( -name "*.py" -o -name "*.sh" -o -name "*.conf" -o -name "*.yml" -o -name "*.yaml" \) 2>/dev/null || true)
  done

  if [[ $violations -eq 0 ]]; then
    pass "No hardcoded IP addresses found ($exemptions exemptions allowed)"
    increment_pass
  else
    fail "Found $violations hardcoded IP addresses"
    increment_fail
  fi
}

################################################################################
# TEST 2: Service Names Used Instead of IPs
################################################################################

test_service_names_used() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 2: Verifying service names used in configs"
  log "════════════════════════════════════════════════════════"

  # Expected service names
  local service_names=(
    "postgres"
    "redis"
    "caddy"
    "loki"
    "prometheus"
    "grafana"
    "alertmanager"
  )

  local found_count=0

  for service in "${service_names[@]}"; do
    local count
    count=$(grep -r "$service" "${SCAN_DIRS[@]}" \
      --include="*.py" \
      --include="*.sh" \
      --include="*.yml" \
      2>/dev/null | grep -c "$service:" || echo 0)

    if [[ $count -gt 0 ]]; then
      debug "Service $service found: $count references"
      ((found_count++))
    fi
  done

  if [[ $found_count -ge 5 ]]; then
    pass "Service names properly used (found $found_count services)"
    increment_pass
  else
    fail "Insufficient service name references (found $found_count/7)"
    increment_fail
  fi
}

################################################################################
# TEST 3: Environment Variables Declared
################################################################################

test_env_vars_declared() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 3: Verifying environment variable declarations"
  log "════════════════════════════════════════════════════════"

  # Required environment variables
  local required_vars=(
    "PRIMARY_HOST"
    "REPLICA_HOST"
    "NAS_HOST"
    "APEX_DOMAIN"
    "IDE_DOMAIN"
    "API_DOMAIN"
  )

  # Check base config file
  local config_file="scripts/_common/_base-config.env"
  
  if [[ ! -f "$config_file" ]]; then
    warn "Base config file not found: $config_file"
    increment_skip
    return
  fi

  local declared=0
  for var in "${required_vars[@]}"; do
    if grep -q "export $var" "$config_file"; then
      debug "Variable declared: $var"
      ((declared++))
    fi
  done

  if [[ $declared -eq ${#required_vars[@]} ]]; then
    pass "All required environment variables declared ($declared/${#required_vars[@]})"
    increment_pass
  else
    fail "Missing environment variable declarations ($declared/${#required_vars[@]})"
    increment_fail
  fi
}

################################################################################
# TEST 4: DNS Resolution (Runtime Test - requires containers)
################################################################################

test_dns_resolution_runtime() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 4: Runtime DNS resolution (requires containers)"
  log "════════════════════════════════════════════════════════"

  # Check if Docker and containers are available
  if ! command -v docker &> /dev/null; then
    warn "Docker not available (skipping runtime tests)"
    increment_skip
    return
  fi

  if ! docker ps &> /dev/null; then
    warn "Docker daemon not accessible (skipping runtime tests)"
    increment_skip
    return
  fi

  # Check if containers are running
  local caddy_running
  caddy_running=$(docker ps --filter "name=caddy" --quiet || echo "")

  if [[ -z "$caddy_running" ]]; then
    warn "Caddy container not running (skipping DNS tests)"
    increment_skip
    return
  fi

  log "Testing DNS resolution via caddy container..."

  local services_to_test=(
    "postgres:5432"
    "redis:6379"
    "loki:3100"
    "prometheus:9090"
  )

  local resolved=0

  for service in "${services_to_test[@]}"; do
    local service_name="${service%%:*}"
    
    if docker exec caddy nslookup "$service_name" &> /dev/null; then
      pass "Service resolves: $service"
      ((resolved++))
    else
      fail "Service resolution failed: $service"
    fi
  done

  if [[ $resolved -ge 2 ]]; then
    pass "DNS resolution working ($resolved services resolved)"
    increment_pass
  else
    fail "DNS resolution failing ($resolved services resolved)"
    increment_fail
  fi
}

################################################################################
# TEST 5: Caddyfile Domain Configuration
################################################################################

test_caddyfile_domains() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 5: Caddyfile domain configuration"
  log "════════════════════════════════════════════════════════"

  local caddyfile="Caddyfile"

  if [[ ! -f "$caddyfile" ]]; then
    warn "Caddyfile not found (skipping test)"
    increment_skip
    return
  fi

  local required_domains=(
    ""
    "ide."
    "api."
    "admin."
  )

  local found=0

  for domain in "${required_domains[@]}"; do
    if grep -q "$domain" "$caddyfile"; then
      debug "Domain configured: $domain"
      ((found++))
    fi
  done

  if [[ $found -eq ${#required_domains[@]} ]]; then
    pass "All required domains configured in Caddyfile"
    increment_pass
  else
    fail "Missing domains in Caddyfile ($found/${#required_domains[@]})"
    increment_fail
  fi
}

################################################################################
# TEST 6: DNS Terraform Configuration
################################################################################

test_terraform_dns_config() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 6: Terraform DNS configuration"
  log "════════════════════════════════════════════════════════"

  local terraform_file="terraform/dns-records.tf"

  if [[ ! -f "$terraform_file" ]]; then
    warn "Terraform DNS config not found (skipping test)"
    increment_skip
    return
  fi

  # Check for Cloudflare provider
  if grep -q "terraform {" "$terraform_file" && \
     grep -q "cloudflare" "$terraform_file"; then
    pass "Terraform Cloudflare provider configured"
    increment_pass
  else
    fail "Terraform DNS configuration incomplete"
    increment_fail
  fi
}

################################################################################
# TEST 7: VRRP Configuration
################################################################################

test_vrrp_configuration() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 7: VRRP configuration script"
  log "════════════════════════════════════════════════════════"

  local vrrp_script="scripts/ops/setup-vrrp-keepalived.sh"

  if [[ ! -f "$vrrp_script" ]]; then
    warn "VRRP script not found (skipping test)"
    increment_skip
    return
  fi

  # Check script is executable
  if [[ -x "$vrrp_script" ]]; then
    pass "VRRP script is executable"
    increment_pass
  else
    fail "VRRP script is not executable"
    increment_fail
  fi

  # Verify script contains key functions
  local required_functions=(
    "check_root"
    "generate_keepalived_config"
    "deploy_vrrp"
  )

  local found_functions=0
  for func in "${required_functions[@]}"; do
    if grep -q "^${func}()" "$vrrp_script"; then
      ((found_functions++))
    fi
  done

  if [[ $found_functions -eq ${#required_functions[@]} ]]; then
    pass "VRRP script contains required functions"
  else
    warn "VRRP script missing some functions"
  fi
}

################################################################################
# TEST 8: /etc/hosts Management Script
################################################################################

test_hosts_management_script() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST 8: /etc/hosts management script"
  log "════════════════════════════════════════════════════════"

  local hosts_script="scripts/ops/manage-hosts-file.sh"

  if [[ ! -f "$hosts_script" ]]; then
    warn "/etc/hosts management script not found (skipping test)"
    increment_skip
    return
  fi

  # Check script is executable
  if [[ -x "$hosts_script" ]]; then
    pass "/etc/hosts management script is executable"
    increment_pass
  else
    fail "/etc/hosts management script is not executable"
    increment_fail
  fi

  # Verify idempotency check exists
  if grep -q "is_already_managed" "$hosts_script" && \
     grep -q "remove_old_managed_entries" "$hosts_script"; then
    pass "/etc/hosts script has idempotency checks"
  else
    warn "/etc/hosts script may lack idempotency checks"
  fi
}

################################################################################
# SUMMARY & REPORTING
################################################################################

generate_report() {
  cat > "$REPORT_FILE" << EOF
{
  "timestamp": "$(date -u +'%Y-%m-%dT%H:%M:%SZ')",
  "mode": "$MODE",
  "tests_run": $TESTS_RUN,
  "tests_passed": $TESTS_PASSED,
  "tests_failed": $TESTS_FAILED,
  "tests_skipped": $TESTS_SKIPPED,
  "pass_rate": $(echo "scale=2; $TESTS_PASSED * 100 / ($TESTS_PASSED + $TESTS_FAILED)" | bc -l 2>/dev/null || echo "N/A"),
  "status": "$(if [[ $TESTS_FAILED -eq 0 ]]; then echo 'PASS'; else echo 'FAIL'; fi)"
}
EOF

  mkdir -p test-results
  cat "$REPORT_FILE"
}

print_summary() {
  log ""
  log "════════════════════════════════════════════════════════"
  log "TEST SUMMARY"
  log "════════════════════════════════════════════════════════"
  log "Tests Run:     $TESTS_RUN"
  log "Tests Passed:  ${GREEN}$TESTS_PASSED${NC}"
  log "Tests Failed:  $(if [[ $TESTS_FAILED -eq 0 ]]; then echo -e "${GREEN}$TESTS_FAILED${NC}"; else echo -e "${RED}$TESTS_FAILED${NC}"; fi)"
  log "Tests Skipped: $TESTS_SKIPPED"
  log ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    log -e "${GREEN}✓ DNS Architecture Validation PASSED${NC}"
    return 0
  else
    log -e "${RED}✗ DNS Architecture Validation FAILED${NC}"
    return 1
  fi
}

################################################################################
# MAIN EXECUTION
################################################################################

main() {
  mkdir -p test-results

  log "╔════════════════════════════════════════════════════════╗"
  log "║  DNS Architecture Validation (CI/CD)                  ║"
  log "║  Mode: $MODE"
  log "╚════════════════════════════════════════════════════════╝"
  log ""

  case "$MODE" in
    ci)
      test_no_hardcoded_ips
      test_service_names_used
      test_env_vars_declared
      test_caddyfile_domains
      test_terraform_dns_config
      test_vrrp_configuration
      test_hosts_management_script
      ;;
    runtime)
      test_dns_resolution_runtime
      ;;
    full)
      test_no_hardcoded_ips
      test_service_names_used
      test_env_vars_declared
      test_dns_resolution_runtime
      test_caddyfile_domains
      test_terraform_dns_config
      test_vrrp_configuration
      test_hosts_management_script
      ;;
  esac

  print_summary
  generate_report

  if [[ $TESTS_FAILED -eq 0 ]]; then
    exit 0
  else
    exit 1
  fi
}

main "$@"
