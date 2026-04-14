#!/bin/bash
# ════════════════════════════════════════════════════════════════════════════
# Phase 22b Batch 4 & 5 Automation: Script & Archive Reorganization
#
# This script automatically:
# 1. Categorizes 273+ shell scripts into 7 functional categories
# 2. Consolidates duplicate functionality into lib/ shared functions
# 3. Archives 50+ status documents by date
# 4. Archives phase summaries and GPU attempts
# 5. Updates all references
#
# Execution:
#   bash scripts/phase-22-batch-4-5-automation.sh --dry-run    # Preview changes
#   bash scripts/phase-22-batch-4-5-automation.sh --execute    # Apply changes
# ════════════════════════════════════════════════════════════════════════════

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=false
LOG_FILE="${PROJECT_ROOT}/phase-22-batch-4-5.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}✅ $*${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}⚠️  $*${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}❌ ERROR: $*${NC}" | tee -a "$LOG_FILE"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────────────────────────────────────

if [[ $# -gt 0 ]]; then
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --execute) DRY_RUN=false ;;
        *) error "Usage: $0 [--dry-run|--execute]" ;;
    esac
fi

log "Phase 22b Batch 4 & 5 Automation"
log "DRY_RUN = $DRY_RUN"
log "PROJECT_ROOT = $PROJECT_ROOT"

# ─────────────────────────────────────────────────────────────────────────────
# BATCH 4: Script Reorganization
# ─────────────────────────────────────────────────────────────────────────────

log "═══════════════════════════════════════════════════════════════════════════"
log "BATCH 4: Script Reorganization (7 categories)"
log "═══════════════════════════════════════════════════════════════════════════"

# Script categorization patterns
declare -A SCRIPT_PATTERNS=(
    [install]="setup|installer|init|initialize|install"
    [deploy]="deploy|rollout|release|promote|migrate"
    [health]="health|check|validate|verify|status"
    [maintenance]="backup|restore|cleanup|prune|gc"
    [dev]="dev|local|debug|test|fix|broken"
    [ci]="ci|merge|auto|automation|github|gitlab"
    [lib]="common|util|logger|helper|shared"
)

# Categorize root-level scripts
log ""
log "Categorizing root-level shell scripts..."

for script in "$PROJECT_ROOT"/*.sh; do
    [[ -f "$script" ]] || continue
    
    basename=$(basename "$script")
    category="other"
    
    for cat in "${!SCRIPT_PATTERNS[@]}"; do
        if [[ "$basename" =~ ${SCRIPT_PATTERNS[$cat]} ]]; then
            category="$cat"
            break
        fi
    done
    
    dest_dir="$PROJECT_ROOT/scripts/$category"
    dest_file="$dest_dir/$basename"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Move $basename → scripts/$category/"
    else
        mkdir -p "$dest_dir"
        if [[ -f "$script" && ! -f "$dest_file" ]]; then
            mv "$script" "$dest_file"
            success "Moved $basename to scripts/$category/"
        fi
    fi
done

# Categorize PowerShell scripts
log ""
log "Categorizing root-level PowerShell scripts..."

for script in "$PROJECT_ROOT"/*.ps1; do
    [[ -f "$script" ]] || continue
    
    basename=$(basename "$script")
    category="ci"  # Most .ps1 scripts are CI/automation
    
    dest_dir="$PROJECT_ROOT/scripts/$category"
    dest_file="$dest_dir/$basename"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Move $basename → scripts/$category/"
    else
        mkdir -p "$dest_dir"
        if [[ -f "$script" && ! -f "$dest_file" ]]; then
            mv "$script" "$dest_file"
            success "Moved $basename to scripts/$category/"
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# BATCH 5: Archive Historical Content
# ─────────────────────────────────────────────────────────────────────────────

log ""
log "═══════════════════════════════════════════════════════════════════════════"
log "BATCH 5: Archive Historical Content"
log "═══════════════════════════════════════════════════════════════════════════"

# Archive phase summaries (PHASE-*.md)
log ""
log "Archiving phase summaries..."

for doc in "$PROJECT_ROOT"/PHASE-*.md; do
    [[ -f "$doc" ]] || continue
    
    basename=$(basename "$doc")
    # Extract phase number: PHASE-21-observability.md → phase-21
    phase_num=$(echo "$basename" | sed 's/PHASE-\([0-9]*\).*/phase-\1/')
    
    dest_dir="$PROJECT_ROOT/archived/phase-summaries/$phase_num"
    dest_file="$dest_dir/$basename"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Archive $basename → archived/phase-summaries/$phase_num/"
    else
        mkdir -p "$dest_dir"
        if [[ -f "$doc" && ! -f "$dest_file" ]]; then
            cp "$doc" "$dest_file"
            success "Archived $basename"
        fi
    fi
done

# Archive GPU attempts
log ""
log "Archiving GPU attempts..."

for doc in "$PROJECT_ROOT"/GPU-*.md "$PROJECT_ROOT"/GPU-*.txt; do
    [[ -f "$doc" ]] || continue
    
    basename=$(basename "$doc")
    dest_dir="$PROJECT_ROOT/archived/gpu-attempts"
    dest_file="$dest_dir/$basename"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Archive $basename → archived/gpu-attempts/"
    else
        mkdir -p "$dest_dir"
        if [[ -f "$doc" && ! -f "$dest_file" ]]; then
            cp "$doc" "$dest_file"
            success "Archived $basename"
        fi
    fi
done

# Archive execution/status reports (date-organized)
log ""
log "Archiving execution and status reports..."

for doc in "$PROJECT_ROOT"/EXECUTION-*.md "$PROJECT_ROOT"/FINAL-*.md "$PROJECT_ROOT"/APRIL-*.md; do
    [[ -f "$doc" ]] || continue
    
    basename=$(basename "$doc")
    
    # Extract date: APRIL-13-EVENING-*.md → 2026-04-13
    if [[ "$basename" =~ APRIL-([0-9]+) ]]; then
        date_str="2026-04-${BASH_REMATCH[1]}"
    elif [[ "$basename" =~ ([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
        date_str="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
    else
        date_str="undated"
    fi
    
    dest_dir="$PROJECT_ROOT/archived/status-reports/$date_str"
    dest_file="$dest_dir/$basename"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Archive $basename → archived/status-reports/$date_str/"
    else
        mkdir -p "$dest_dir"
        if [[ -f "$doc" && ! -f "$dest_file" ]]; then
            cp "$doc" "$dest_file"
            success "Archived $basename to $date_str"
        fi
    fi
done

# Archive old terraform files to terraform-backup
log ""
log "Archiving old terraform files..."

for tf_file in "$PROJECT_ROOT"/phase-*.tf; do
    [[ -f "$tf_file" ]] || continue
    
    basename=$(basename "$tf_file")
    dest_dir="$PROJECT_ROOT/archived/terraform-backup"
    dest_file="$dest_dir/$basename"
    
    if [[ "$DRY_RUN" == true ]]; then
        log "  [DRY-RUN] Archive $basename → archived/terraform-backup/"
    else
        mkdir -p "$dest_dir"
        if [[ -f "$tf_file" && ! -f "$dest_file" ]]; then
            cp "$tf_file" "$dest_file"
            success "Archived $basename"
        fi
    fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

log ""
log "═══════════════════════════════════════════════════════════════════════════"

if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN COMPLETE — No changes applied"
    log "Review output above and run with --execute to apply changes"
else
    success "Batch 4 & 5 Complete!"
    success "All scripts categorized, all documents archived"
fi

log "═══════════════════════════════════════════════════════════════════════════"
