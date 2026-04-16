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
  echo "Rule: Both files CAN have overlapping vars - .env overrides config/_base-config.env"
  
  local duplicate_found=0
  declare -A env_vars
  
  # Check config/_base-config.env first (base layer)
  if [[ -f "config/_base-config.env" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
      key_name="${key%%=*}"
      [[ -z "$key_name" ]] && continue
      env_vars["${key_name}"]="config/_base-config.env"
    done < config/_base-config.env
  fi
  
  # Check .env second (override layer) - duplicates here are ALLOWED
  if [[ -f ".env" ]]; then
    local env_overrides=0
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
      key_name="${key%%=*}"
      [[ -z "$key_name" ]] && continue
      
      if [[ -n "${env_vars["$key_name"]:-}" ]]; then
        ((env_overrides++))
      fi
      env_vars["${key_name}"]="override"
    done < .env
    
    log_success ".env overrides $env_overrides base config variables (allowed)"
  fi
  
  # Check for INTERNAL duplicates within .env itself
  local .env_internal_dupes=0
  declare -A env_check
  if [[ -f ".env" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
      key_name="${key%%=*}"
      [[ -z "$key_name" ]] && continue
      
      if [[ -n "${env_check[$key_name]:-}" ]]; then
        log_error "DUPLICATE within .env: $key_name defined multiple times"
        duplicate_found=1
        ((.env_internal_dupes++))
        ((FOUND_DUPLICATES++))
      fi
      env_check["$key_name"]=1
    done < .env
  fi
  
  if [[ $duplicate_found -eq 0 ]]; then
    log_success "No duplicate environment variables within single files"
  fi
  
  return $duplicate_found
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. DETECT DUPLICATE SERVICE DEFINITIONS
# ─────────────────────────────────────────────────────────────────────────────
check_service_duplicates() {
  log_header "CHECK 2: Docker Compose Service Definitions"
  
  if [[ ! -f "docker-compose.yml" ]]; then
    log_warning "docker-compose.yml not found"
    return 0
  fi
  
  echo "Scanning: docker-compose.yml"
  
  local duplicate_found=0
  declare -A services
  local in_services=0
  local indent_level=0
  
  # Extract only top-level service names (2-space indent under services:)
  while IFS= read -r line; do
    # Check if we're entering services section
    if [[ $line =~ ^services:[[:space:]]*$ ]]; then
      in_services=1
      continue
    fi
    
    # Check if we're leaving services section
    if [[ $in_services -eq 1 ]] && [[ $line =~ ^[a-z] ]]; then
      in_services=0
    fi
    
    # Only process lines while in services section
    if [[ $in_services -eq 1 ]]; then
      # Match lines with exactly 2-space indent followed by service name
      if [[ $line =~ ^[[:space:]]{2}([a-z0-9_-]+):[[:space:]]*$ ]]; then
        service_name="${BASH_REMATCH[1]}"
        
        if [[ -n "${services[$service_name]:-}" ]]; then
          log_error "DUPLICATE SERVICE: '$service_name' defined multiple times"
          duplicate_found=1
          ((FOUND_DUPLICATES++))
        else
          services[$service_name]="docker-compose.yml"
        fi
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
  local temp_resources=$(mktemp)
  
  # Find all resource definitions: resource "type" "name"
  find terraform -name "*.tf" -type f 2>/dev/null | while read tf_file; do
    [[ ! -f "$tf_file" ]] && continue
    
    grep -n '^resource[[:space:]]"[^"]*"[[:space:]]"[^"]*"' "$tf_file" >> "$temp_resources" || true
  done
  
  # Check for duplicates
  if [[ -f "$temp_resources" ]]; then
    local resource_id=""
    declare -A res_seen
    
    while IFS=: read -r tf_file line content; do
      if [[ $content =~ ^resource[[:space:]]\"([^\"]+)\"[[:space:]]\"([^\"]+)\" ]]; then
        res_type="${BASH_REMATCH[1]}"
        res_name="${BASH_REMATCH[2]}"
        res_id="${res_type}.${res_name}"
        
        # Store in associative array - this will fail in subshell so just report from temp file
        echo "$res_id:$tf_file" >> "$temp_resources.check"
      fi
    done < "$temp_resources"
    
    # Check for duplicates in the check file
    if [[ -f "$temp_resources.check" ]]; then
      sort "$temp_resources.check" | uniq -d | while read dup_entry; do
        res_id="${dup_entry%%:*}"
        log_error "DUPLICATE TERRAFORM RESOURCE: $res_id"
        grep "^$dup_entry" "$temp_resources.check" | sed 's/^/  /'
        duplicate_found=1
        ((FOUND_DUPLICATES++))
      done
    fi
    
    rm -f "$temp_resources" "$temp_resources.check"
  fi
  
  if [[ $duplicate_found -eq 0 ]]; then
    log_success "No duplicate terraform resources detected"
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
