#!/bin/bash
# scripts/governance/drift-detector.sh
# Purpose: Monitor for configuration drift between MANIFEST and actual running state
# Scope: Docker containers, volumes, networks vs MANIFEST.toml
# Authority: #326 - IaC-010: Enforce immutable/idempotent on-prem IaC
# Run Frequency: Every 5 minutes (via cron)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MANIFEST_FILE="$REPO_ROOT/MANIFEST.toml"
DRIFT_REPORT="/tmp/drift-detector-$(date +%s).json"

# Colors
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

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
# DRIFT DETECTION - Compare MANIFEST.toml vs Actual State
# ─────────────────────────────────────────────────────────────────────────────

main() {
  log_header "IaC DRIFT DETECTION"
  echo ""
  
  [[ ! -f "$MANIFEST_FILE" ]] && {
    log_error "MANIFEST.toml not found"
    exit 2
  }
  
  # Initialize drift report
  cat > "$DRIFT_REPORT" << 'EOF'
{
  "timestamp": "TIMESTAMP",
  "hostname": "HOSTNAME",
  "drifts": [],
  "status": "OK",
  "summary": ""
}
EOF
  
  sed -i "s/TIMESTAMP/$(date -Iseconds)/" "$DRIFT_REPORT"
  sed -i "s/HOSTNAME/$(hostname)/" "$DRIFT_REPORT"
  
  local drift_count=0
  
  # ─────────────────────────────────────────────────────────────────────────
  # 1. CHECK DOCKER CONTAINER IMAGES
  # ─────────────────────────────────────────────────────────────────────────
  
  echo "Check 1: Docker Container Image Versions"
  
  # Extract expected versions from MANIFEST.toml
  while IFS='=' read -r key value; do
    [[ ! "$key" =~ ^services\. ]] && continue
    [[ ! "$key" =~ version$ ]] && continue
    
    service_name=$(echo "$key" | cut -d. -f2)
    expected_version=$(echo "$value" | tr -d '"')
    
    # Get actual running version
    container_id=$(docker ps --filter "name=$service_name" -q | head -1)
    
    if [[ -z "$container_id" ]]; then
      log_warning "Container '$service_name' not running"
      ((drift_count++))
      continue
    fi
    
    actual_version=$(docker inspect "$container_id" --format='{{.Config.Image}}' | rev | cut -d: -f1 | rev)
    
    if [[ "$actual_version" != "$expected_version" ]]; then
      log_error "DRIFT: $service_name - expected $expected_version, got $actual_version"
      ((drift_count++))
    else
      log_success "✓ $service_name: $actual_version matches"
    fi
    
  done < <(grep "version = " "$MANIFEST_FILE")
  
  # ─────────────────────────────────────────────────────────────────────────
  # 2. CHECK DOCKER VOLUMES
  # ─────────────────────────────────────────────────────────────────────────
  
  echo ""
  echo "Check 2: Docker Volumes"
  
  # Extract expected volumes from docker-compose.yml
  if [[ -f "docker-compose.yml" ]]; then
    while IFS= read -r vol; do
      vol=$(echo "$vol" | xargs)  # Trim whitespace
      [[ -z "$vol" ]] && continue
      
      # Check if volume exists
      if docker volume inspect "$vol" > /dev/null 2>&1; then
        log_success "✓ Volume: $vol exists"
      else
        log_error "DRIFT: Volume missing - $vol"
        ((drift_count++))
      fi
    done < <(grep -E '^\s+[a-z_]+_data:' docker-compose.yml | cut -d: -f1 | xargs)
  fi
  
  # ─────────────────────────────────────────────────────────────────────────
  # 3. CHECK DOCKER NETWORKS
  # ─────────────────────────────────────────────────────────────────────────
  
  echo ""
  echo "Check 3: Docker Networks"
  
  expected_network="code-server-enterprise"
  
  if docker network inspect "$expected_network" > /dev/null 2>&1; then
    log_success "✓ Network: $expected_network exists"
  else
    log_error "DRIFT: Network missing - $expected_network"
    ((drift_count++))
  fi
  
  # ─────────────────────────────────────────────────────────────────────────
  # 4. CHECK CONFIGURATION FILES (file timestamps)
  # ─────────────────────────────────────────────────────────────────────────
  
  echo ""
  echo "Check 4: Configuration File Age"
  
  config_files=(
    "docker-compose.yml"
    "Caddyfile"
    ".env"
    "MANIFEST.toml"
  )
  
  for config_file in "${config_files[@]}"; do
    if [[ ! -f "$config_file" ]]; then
      log_warning "Config file missing: $config_file"
      continue
    fi
    
    file_age=$(($(date +%s) - $(stat -c %Y "$config_file" 2>/dev/null || echo 0)))
    file_age_hours=$((file_age / 3600))
    
    if [[ $file_age_hours -gt 24 ]]; then
      log_warning "Config file aged: $config_file ($file_age_hours hours old)"
    else
      log_success "✓ Config: $config_file current"
    fi
  done
  
  # ─────────────────────────────────────────────────────────────────────────
  # 5. CHECK CONTAINER HEALTH STATUS
  # ─────────────────────────────────────────────────────────────────────────
  
  echo ""
  echo "Check 5: Container Health Status"
  
  unhealthy=$(docker ps --filter "health=unhealthy" -q | wc -l)
  
  if [[ $unhealthy -gt 0 ]]; then
    log_error "DRIFT: $unhealthy containers are unhealthy"
    ((drift_count++))
    docker ps --filter "health=unhealthy" --format "table {{.Names}}\t{{.Status}}"
  else
    log_success "✓ All monitored containers healthy"
  fi
  
  # ─────────────────────────────────────────────────────────────────────────
  # REPORT RESULTS
  # ─────────────────────────────────────────────────────────────────────────
  
  echo ""
  log_header "DRIFT DETECTION RESULTS"
  
  if [[ $drift_count -eq 0 ]]; then
    log_success "✅ NO DRIFT DETECTED"
    echo ""
    log_success "System state matches MANIFEST.toml"
    
    # Update report
    sed -i 's/"status": "OK"/"status": "CLEAN"/' "$DRIFT_REPORT"
    sed -i 's/"summary": ""/"summary": "No drift detected - system compliant"/' "$DRIFT_REPORT"
    
    exit 0
  else
    log_error "❌ $drift_count DRIFT(S) DETECTED"
    echo ""
    log_error "System state diverges from MANIFEST.toml"
    echo ""
    log_error "Action Required:"
    echo "  1. Review drifts above"
    echo "  2. Determine cause (manual changes vs config error)"
    echo "  3. Either:"
    echo "     - Redeploy to fix (terraform apply)"
    echo "     - Rollback to previous version"
    echo "     - Approve drift and update MANIFEST.toml"
    
    # Update report
    sed -i "s/\"status\": \"OK\"/\"status\": \"DRIFT\"/" "$DRIFT_REPORT"
    sed -i "s/\"summary\": \"\"/\"summary\": \"$drift_count drift(s) detected - manual remediation required\"/" "$DRIFT_REPORT"
    
    # Alert ops (if running on production host)
    if [[ -f "/.dockerenv" ]] || [[ "$HOSTNAME" == "production" ]]; then
      log_error "🚨 PRODUCTION DRIFT ALERT"
      echo ""
      echo "Drift report saved to: $DRIFT_REPORT"
      
      # Try to create GitHub issue if we have access
      if command -v curl > /dev/null 2>&1 && [[ -n "${GITHUB_TOKEN:-}" ]]; then
        echo "Creating P1 GitHub issue..."
        # Issue creation would go here
      fi
    fi
    
    exit 1
  fi
}

main "$@"
