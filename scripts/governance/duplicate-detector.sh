#!/bin/bash
# scripts/governance/duplicate-detector.sh
# Purpose: Detect and report configuration duplicates across IaC layers
# Scope: terraform, docker-compose, scripts, environment files
# Authority: #326 - IaC-010: Enforce immutable/idempotent on-prem IaC
# Exit Code: 0 if no duplicates, 1 if duplicates found, 2 if fatal error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Result tracking
declare -A DUPLICATE_CHECKS
FOUND_DUPLICATES=0
FATAL_ERRORS=0

log_header() {
  echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${CYAN}$1${NC}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
}

log_error() {
  echo -e "${RED}❌ $1${NC}" >&2
}

log_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

log_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. DETECT DUPLICATE ENVIRONMENT VARIABLES
# ─────────────────────────────────────────────────────────────────────────────
check_env_duplicates() {
  log_header "CHECK 1: Environment Variable Duplicates"
  
  if [[ ! -f ".env" && ! -f "config/_base-config.env" ]]; then
    log_warning "No .env files found - skipping env check"
    return 0
  fi
  
  echo "Scanning: .env and config/_base-config.env"
  
  declare -A env_vars
  local duplicate_found=0
  
  # Check .env
  if [[ -f ".env" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ ]] && continue
      [[ -z "$key" ]] && continue
      key_name="${key%%=*}"
      if [[ -n "${env_vars[$key_name]:-}" ]]; then
        log_error "DUPLICATE ENV VAR: $key_name defined in both files"
        duplicate_found=1
        ((FOUND_DUPLICATES++))
      else
        env_vars[$key_name]=".env"
      fi
    done < .env
  fi
  
  # Check config/_base-config.env
  if [[ -f "config/_base-config.env" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ ]] && continue
      [[ -z "$key" ]] && continue
      key_name="${key%%=*}"
      if [[ -n "${env_vars[$key_name]:-}" ]]; then
        log_error "DUPLICATE ENV VAR: $key_name defined in ${env_vars[$key_name]} and config/_base-config.env"
        duplicate_found=1
        ((FOUND_DUPLICATES++))
      else
        env_vars[$key_name]="config/_base-config.env"
      fi
    done < config/_base-config.env
  fi
  
  if [[ $duplicate_found -eq 0 ]]; then
    log_success "No duplicate environment variables"
  fi
  
  return $duplicate_found
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. DETECT DUPLICATE SERVICE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
check_service_duplicates() {
  log_header "CHECK 2: Docker Compose Service Duplicates"
  
  if [[ ! -f "docker-compose.yml" ]]; then
    log_warning "docker-compose.yml not found"
    return 0
  fi
  
  echo "Scanning: docker-compose.yml"
  
  local duplicate_found=0
  declare -A services
  
  # Extract service names (lines starting with "servicename:")
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*([a-z0-9_-]+):[[:space:]]*$ ]]; then
      service_name="${BASH_REMATCH[1]}"
      # Skip global keys
      [[ "$service_name" =~ ^(version|services|networks|volumes)$ ]] && continue
      
      if [[ -n "${services[$service_name]:-}" ]]; then
        log_error "DUPLICATE SERVICE: '$service_name' defined multiple times"
        duplicate_found=1
        ((FOUND_DUPLICATES++))
      else
        services[$service_name]="docker-compose.yml"
      fi
    fi
  done < docker-compose.yml
  
  if [[ $duplicate_found -eq 0 ]]; then
    log_success "No duplicate services in docker-compose.yml (${#services[@]} services found)"
  fi
  
  return $duplicate_found
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. DETECT DUPLICATE TERRAFORM RESOURCES
# ─────────────────────────────────────────────────────────────────────────────
check_terraform_duplicates() {
  log_header "CHECK 3: Terraform Resource Duplicates"
  
  if [[ ! -d "terraform" ]]; then
    log_warning "terraform/ directory not found"
    return 0
  fi
  
  echo "Scanning: terraform/*.tf files"
  
  local duplicate_found=0
  declare -A resources
  
  # Find all resource definitions: resource "type" "name"
  for tf_file in terraform/*.tf terraform/modules/**/*.tf 2>/dev/null; do
    [[ ! -f "$tf_file" ]] && continue
    
    while IFS= read -r line; do
      if [[ $line =~ ^resource[[:space:]]\"([^\"]+)\"[[:space:]]\"([^\"]+)\" ]]; then
        res_type="${BASH_REMATCH[1]}"
        res_name="${BASH_REMATCH[2]}"
        res_id="${res_type}.${res_name}"
        
        if [[ -n "${resources[$res_id]:-}" ]]; then
          log_error "DUPLICATE RESOURCE: resource \"$res_type\" \"$res_name\" in $tf_file and ${resources[$res_id]}"
          duplicate_found=1
          ((FOUND_DUPLICATES++))
        else
          resources[$res_id]="$tf_file"
        fi
      fi
    done < "$tf_file"
  done
  
  if [[ $duplicate_found -eq 0 ]]; then
    log_success "No duplicate terraform resources (${#resources[@]} resources found)"
  fi
  
  return $duplicate_found
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. DETECT HARDCODED SECRETS
# ─────────────────────────────────────────────────────────────────────────────
check_hardcoded_secrets() {
  log_header "CHECK 4: Hardcoded Secrets Detection"
  
  echo "Scanning: terraform, docker-compose, scripts"
  
  local duplicate_found=0
  local secret_patterns=(
    'password[[:space:]]*=[[:space:]]*["\x27][^"]*["\x27]'
    'secret[[:space:]]*=[[:space:]]*["\x27][^"]*["\x27]'
    'api[_-]?key[[:space:]]*=[[:space:]]*["\x27][^"]*["\x27]'
    'token[[:space:]]*=[[:space:]]*["\x27][^"]*["\x27]'
  )
  
  for pattern in "${secret_patterns[@]}"; do
    files_with_secrets=$(grep -r --include="*.tf" --include="*.yml" --include="*.sh" \
      -n "$pattern" . 2>/dev/null | grep -v "node_modules\|.git" || true)
    
    if [[ -n "$files_with_secrets" ]]; then
      log_error "HARDCODED SECRET PATTERN: $pattern"
      echo "$files_with_secrets" | sed 's/^/  /'
      duplicate_found=1
      ((FOUND_DUPLICATES++))
    fi
  done
  
  if [[ $duplicate_found -eq 0 ]]; then
    log_success "No obvious hardcoded secrets detected"
  fi
  
  return $duplicate_found
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. DETECT DUPLICATE CONFIGURATION SOURCES
# ─────────────────────────────────────────────────────────────────────────────
check_duplicate_sources() {
  log_header "CHECK 5: Duplicate Configuration Sources"
  
  echo "Checking for single source of truth violations..."
  
  local duplicate_found=0
  
  # Rule: allowed-emails.txt should ONLY be sourced from terraform, not manual edits
  if grep -r "allowed-emails\.txt" terraform/ > /dev/null 2>&1 || \
     grep -r "allowed-emails\.txt" scripts/ > /dev/null 2>&1; then
    # Check if file is also modified manually outside terraform
    if git status --short 2>/dev/null | grep -q "allowed-emails.txt"; then
      log_warning "allowed-emails.txt has uncommented changes - should be terraform-managed only"
    fi
  fi
  
  # Rule: Caddyfile should come from template, not manual edits
  if [[ -f "Caddyfile" ]] && [[ -f "Caddyfile.tpl" ]]; then
    if ! diff -q <(sed 's/${[^}]*}/PLACEHOLDER/g' Caddyfile) \
                 <(sed 's/${[^}]*}/PLACEHOLDER/g' Caddyfile.tpl) > /dev/null 2>&1; then
      log_warning "Caddyfile and Caddyfile.tpl may be out of sync (manual edits?)"
    fi
  fi
  
  if [[ $duplicate_found -eq 0 ]]; then
    log_success "No obvious duplicate configuration sources detected"
  fi
  
  return $duplicate_found
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN EXECUTION
# ─────────────────────────────────────────────────────────────────────────────

main() {
  echo ""
  log_header "IaC DUPLICATE DETECTION - Comprehensive Scan"
  echo ""
  
  # Run all checks, collect results
  check_env_duplicates || true
  check_service_duplicates || true
  check_terraform_duplicates || true
  check_hardcoded_secrets || true
  check_duplicate_sources || true
  
  echo ""
  log_header "SCAN RESULTS"
  echo ""
  
  if [[ $FOUND_DUPLICATES -eq 0 ]]; then
    log_success "✅ NO DUPLICATES FOUND - IaC is clean"
    echo ""
    log_success "Governance Status: PASSED"
    exit 0
  else
    log_error "❌ $FOUND_DUPLICATES DUPLICATE(S) FOUND"
    echo ""
    log_error "Governance Status: FAILED"
    exit 1
  fi
}

main "$@"
