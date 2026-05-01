#!/bin/bash
# ============================================================================
# CLEANUP PHASE 1 - LOW RISK ARCHIVAL
# April 29, 2026 - Workspace Sanitization
# ============================================================================

set -e
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Cleanup complete"; true' EXIT

log_info() { echo "[INFO] $1"; }
log_success() { echo "[✓] $1"; }
log_warn() { echo "[⚠] $1"; }

log_info "========================================================="
log_info "CLEANUP PHASE 1 - LOW RISK ARCHIVAL"
log_info "========================================================="

# Create archive directory structure
log_info "STEP 1: Creating archive directory structure"
mkdir -p docs/archive/completed
mkdir -p docs/archive/docker-compose-variants
mkdir -p docs/archive/phase-reports
mkdir -p docs/archive/bootstrap-state
log_success "✓ Archive directories created"

# =========================================================================
# STEP 2: Archive Status/Completion Documents (200+ files)
# =========================================================================
log_info "STEP 2: Archiving status and completion documents"

# Count files before
COUNT_BEFORE=$(find . -maxdepth 1 -name "*COMPLETE*" -o -name "*COMPLETION*" -o -name "*STATUS*" -o -name "*REPORT*" -o -name "*SUMMARY*" 2>/dev/null | grep -E "\.md$" | wc -l || echo "0")
log_info "  → Found ${COUNT_BEFORE} status/completion documents"

# Archive them (safely, keeping in git history)
find . -maxdepth 1 -type f -name "*COMPLETE*.md" -o -name "*COMPLETION*.md" -o -name "*STATUS*.md" 2>/dev/null | while read file; do
    if [ -f "$file" ]; then
        mv "$file" "docs/archive/completed/" 2>/dev/null || log_warn "Could not move $file"
    fi
done

log_success "✓ Status/completion documents archived"

# =========================================================================
# STEP 3: Archive Phase-Specific Reports
# =========================================================================
log_info "STEP 3: Archiving phase-specific reports"

find . -maxdepth 1 -type f -name "PHASE*.md" 2>/dev/null | while read file; do
    if [ -f "$file" ]; then
        mv "$file" "docs/archive/phase-reports/" 2>/dev/null || log_warn "Could not move $file"
    fi
done

log_success "✓ Phase reports archived"

# =========================================================================
# STEP 4: Archive Docker Compose Variants
# =========================================================================
log_info "STEP 4: Archiving redundant docker-compose files"

# Keep: docker-compose.yml (main), docker-compose.prod.yml, docker-compose.enterprise.yml
# Archive: All others

find . -maxdepth 1 -type f -name "docker-compose*.yml" ! -name "docker-compose.yml" ! -name "docker-compose.prod.yml" ! -name "docker-compose.enterprise.yml" 2>/dev/null | while read file; do
    if [ -f "$file" ]; then
        log_info "  → Archiving $file"
        mv "$file" "docs/archive/docker-compose-variants/" 2>/dev/null || log_warn "Could not move $file"
    fi
done

log_success "✓ Docker Compose variants archived"

# =========================================================================
# STEP 5: Clean Bootstrap & Deployment State
# =========================================================================
log_info "STEP 5: Archiving bootstrap and deployment state"

if [ -d ".bootstrap-state" ]; then
    log_info "  → Moving .bootstrap-state to archive"
    mkdir -p docs/archive/bootstrap-state
    mv .bootstrap-state/* docs/archive/bootstrap-state/ 2>/dev/null || true
    rmdir .bootstrap-state 2>/dev/null || true
fi

if [ -d ".deployments" ]; then
    log_info "  → Moving .deployments to archive"
    mkdir -p docs/archive/bootstrap-state
    mv .deployments/* docs/archive/bootstrap-state/ 2>/dev/null || true
    rmdir .deployments 2>/dev/null || true
fi

log_success "✓ Bootstrap/deployment state archived"

# =========================================================================
# STEP 6: Count Results
# =========================================================================
log_info "STEP 6: Documenting cleanup results"

COUNT_AFTER=$(find . -maxdepth 1 -name "*.md" -type f | wc -l)
ARCHIVE_SIZE=$(du -sh docs/archive 2>/dev/null | awk '{print $1}')

log_info ""
log_success "CLEANUP PHASE 1 - COMPLETE"
log_info ""
log_info "Results:"
log_info "  ✓ Root-level .md files: ~${COUNT_BEFORE} → ~${COUNT_AFTER} (archived)"
log_info "  ✓ Archive size: ${ARCHIVE_SIZE}"
log_info "  ✓ Bootstrap/deployment state cleaned"
log_info "  ✓ Docker Compose variants consolidated"
log_info ""
log_info "Files Archived:"
ls -1 docs/archive/*/  2>/dev/null | wc -l | xargs echo "  ✓ Total files in archive:"
log_info ""
log_info "Next Steps:"
log_info "  1. Review archived files: ls -la docs/archive/"
log_info "  2. Verify no critical files were moved"
log_info "  3. Commit changes to git"
log_info "  4. Proceed to Cleanup Phase 2 (script consolidation)"
log_info ""

exit 0
