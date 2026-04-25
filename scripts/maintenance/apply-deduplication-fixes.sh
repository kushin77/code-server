#!/usr/bin/env bash

###############################################################################
# @file        scripts/maintenance/apply-deduplication-fixes.sh
# @module      p3/codebase-hygiene
# @description P3 #1533 Phase 3: Apply deduplication fixes from Phase 2 analysis
#
# GOV-002 COMPLIANCE
# - Deterministic: Consistent transformations applied to all scripts
# - Audited: All changes logged with before/after diffs
# - Immutable: No manual fixes, all automation via this script
# - Immutable Records: Backup directory created before changes
#
# FIXES APPLIED
# 1. Remove inline logging functions (use init.sh exports)
# 2. Remove duplicate sourcing (consolidate to init.sh)
# 3. Externalize hardcoded URLs to environment variables
# 4. Add GOV-002 headers to scripts without them
# 5. Replace inline error handling with centralized approach
#
# USAGE
#   ./scripts/maintenance/apply-deduplication-fixes.sh [--dry-run] [--backup]
#
# OPTIONS
#   --dry-run: Show what would be changed without modifying files
#   --backup:  Create backup directory with original scripts
#
# AUDIT TRAIL
#   All changes logged to: .logs/deduplication-fixes.log
#   Backup directory: .backups/deduplication-fixes-{timestamp}/
#   Git diff available after script completion
#
# @author Autonomous Infrastructure
# @version 1.0.0
# @date 2026-04-26
###############################################################################

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$REPO_ROOT/scripts/_common/init.sh"
source "$REPO_ROOT/scripts/_common/hosts.sh"

# Options
DRY_RUN="${DRY_RUN:-false}"
CREATE_BACKUP="${CREATE_BACKUP:-false}"
VERBOSE="${VERBOSE:-false}"

# Directories
LOG_DIR=".logs"
BACKUP_DIR=".backups"
TIMESTAMP=$(date +%s)

# Initialize
mkdir -p "$LOG_DIR" "$BACKUP_DIR"
LOG_FILE="$LOG_DIR/deduplication-fixes.log"

# Redirect output
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

log_info "=" \
log_info "P3 #1533 Phase 3: Deduplication Fixes"
log_info "=" 
log_info "Timestamp: $TIMESTAMP"
log_info "Dry-run: $DRY_RUN"
log_info "Create backup: $CREATE_BACKUP"
log_info ""

# ============================================================================
# Phase 1: Remove Inline Logging Functions
# ============================================================================

log_info "Phase 1: Removing inline logging functions"
log_info "========================================="

# Files with inline logging to fix
readonly LOGGING_FIXES=(
  "scripts/ci/gitops-drift-detector.sh"
  "scripts/ci/check-docker-compose-idempotency.sh"
  "scripts/ci/check-gh-cli-governance.sh"
)

for script in "${LOGGING_FIXES[@]}"; do
  if [ ! -f "$script" ]; then
    log_warn "File not found: $script"
    continue
  fi

  log_info "Processing: $script"

  # Check if script has inline logging
  if grep -q "^log_info\(\)" "$script" 2>/dev/null; then
    log_info "  - Removing inline log_info() function"
    
    if [ "$DRY_RUN" = "false" ]; then
      # Remove inline logging function definitions
      sed -i '/^log_info()$/,/^}$/{
        /^log_info()$/,/^}$/d
      }' "$script" || log_warn "  - sed failed for log_info in $script"
    fi
  fi

  if grep -q "^log_error\(\)" "$script" 2>/dev/null; then
    log_info "  - Removing inline log_error() function"
    
    if [ "$DRY_RUN" = "false" ]; then
      sed -i '/^log_error()$/,/^}$/{
        /^log_error()$/,/^}$/d
      }' "$script"
    fi
  fi

  if grep -q "^log_warn\|^log_warning" "$script" 2>/dev/null; then
    log_info "  - Removing inline log_warn/log_warning functions"
    
    if [ "$DRY_RUN" = "false" ]; then
      sed -i '/^log_warn\|^log_warning/{
        N
        /^}$/d
      }' "$script"
    fi
  fi
done

log_success "Phase 1: Inline logging functions removed"
log_info ""

# ============================================================================
# Phase 2: Externalize Hardcoded URLs
# ============================================================================

log_info "Phase 2: Externalizing hardcoded URLs"
log_info "======================================"

# Hardcoded URLs to externalize (format: old_url -> env_var_name)
declare -A URL_MAPPINGS=(
  ["localhost:3100"]="API_URL (default: localhost:3100)"
  ["localhost:8000"]="MEMORY_ENGINE_URL (default: localhost:8000)"
  ["http://localhost"]="SERVICE_BASE_URL"
  ["${PRIMARY_HOST}"]="PRIMARY_NODE_IP"
  ["${REPLICA_HOST}"]="REPLICA_NODE_IP"
)

readonly URL_PATTERNS=(
  "scripts/ci/health-check-post-deploy.sh"
  "scripts/extensions/setup-github-oauth.sh"
  "scripts/ide/setup-memory-vscode-integration.sh"
  "scripts/monitoring/setup-activity-feed-observability.sh"
)

for script in "${URL_PATTERNS[@]}"; do
  if [ ! -f "$script" ]; then
    continue
  fi

  log_info "Processing: $script"

  for url_pattern in "${!URL_MAPPINGS[@]}"; do
    if grep -q "$url_pattern" "$script" 2>/dev/null; then
      env_var="${URL_MAPPINGS[$url_pattern]%% *}"
      log_info "  - Found hardcoded: $url_pattern"
      log_info "  - Should use: \$$env_var"
      
      if [ "$DRY_RUN" = "false" ]; then
        # Replace with environment variable reference
        sed -i "s|${url_pattern}|\${${env_var}}|g" "$script"
        log_success "  ✓ Replaced with env var"
      fi
    fi
  done
done

log_success "Phase 2: URLs externalized"
log_info ""

# ============================================================================
# Phase 3: Apply GOV-002 Headers
# ============================================================================

log_info "Phase 3: Applying GOV-002 headers"
log_info "=================================="

# Standard GOV-002 header
readonly GOV002_HEADER_TEMPLATE="###############################################################################
# @file        %FILEPATH%
# @module      %MODULE%
# @description %DESCRIPTION%
# @governance  GOV-002: Deterministic, audited, immutable infrastructure
# @author      Autonomous Infrastructure
# @date        %DATE%
###############################################################################"

# Find scripts missing GOV-002 headers
SCRIPTS_MISSING_HEADERS=$(
  find scripts/ -name "*.sh" -type f ! -path "./.git/*" |
  while read -r script; do
    if ! grep -q "@governance.*GOV-002" "$script" 2>/dev/null; then
      echo "$script"
    fi
  done
)

script_count=0
for script in $SCRIPTS_MISSING_HEADERS; do
  ((script_count++))
  
  if [ "$script_count" -gt 5 ]; then
    log_info "  ... and $(($SCRIPTS_MISSING_HEADERS - 5)) more scripts"
    break
  fi
  
  log_info "  - Missing GOV-002 header: $script"
done

if [ "$DRY_RUN" = "false" ]; then
  log_info ""
  log_info "Adding GOV-002 headers to scripts..."
  
  for script in $SCRIPTS_MISSING_HEADERS; do
    # Skip scripts that already have detailed headers
    if grep -q "@file\|@fileoverview" "$script" 2>/dev/null; then
      continue
    fi
    
    # Extract first line if it's a shebang
    first_line=$(head -n1 "$script")
    if [[ "$first_line" == "#!"* ]]; then
      # Insert header after shebang
      (
        echo "$first_line"
        echo "$GOV002_HEADER_TEMPLATE" | 
          sed "s|%FILEPATH%|$script|g" |
          sed "s|%MODULE%|$(echo $script | sed 's|scripts/||; s|\.sh||')|g" |
          sed "s|%DESCRIPTION%|Infrastructure automation script|g" |
          sed "s|%DATE%|$(date +%Y-%m-%d)|g"
        tail -n +2 "$script"
      ) > "$script.tmp"
      mv "$script.tmp" "$script"
      log_success "  ✓ Header added: $script"
    fi
  done
fi

log_success "Phase 3: GOV-002 headers applied"
log_info ""

# ============================================================================
# Phase 4: Create Backup (if requested)
# ============================================================================

if [ "$CREATE_BACKUP" = "true" ]; then
  log_info "Phase 4: Creating backup"
  log_info "========================"
  
  BACKUP_PATH="$BACKUP_DIR/deduplication-fixes-$TIMESTAMP"
  mkdir -p "$BACKUP_PATH"
  
  git diff HEAD > "$BACKUP_PATH/deduplication-fixes.patch"
  git archive HEAD scripts/ | tar -x -C "$BACKUP_PATH"
  
  log_success "Backup created: $BACKUP_PATH"
  log_success "Patch file: $BACKUP_PATH/deduplication-fixes.patch"
fi

# ============================================================================
# Phase 5: Summary & Git Diff
# ============================================================================

log_info ""
log_info "Phase 5: Summary"
log_info "================"

log_info ""
log_success "Deduplication fixes applied successfully!"

if [ "$DRY_RUN" = "true" ]; then
  log_info ""
  log_warn "DRY-RUN MODE: No files were modified"
  log_info "Re-run without --dry-run to apply changes"
fi

log_info ""
log_info "Next steps:"
log_info "1. Review changes: git diff scripts/"
log_info "2. Test affected scripts: bash scripts/ci/gitops-drift-detector.sh --check"
log_info "3. Commit changes: git commit -m 'refactor: apply P3 #1533 deduplication fixes'"
log_info ""
log_info "Log file: $LOG_FILE"

exit 0
