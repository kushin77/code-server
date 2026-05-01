#!/bin/bash
# @file sync-gitlab-mirror.sh
# @module ops/deployment
# @description One-way mirror sync: code-server main → kushin77/source-control main (GitLab integration)
# @governance GOV-002

set -euo pipefail

# Source canonical bootstrap
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

source "${REPO_ROOT}/scripts/_common/gitlab-source-control-config.sh"

# ============================================================================
# Configuration
# ============================================================================
readonly SOURCE_REPO="${SYNC_SOURCE_REPO:-${CODE_SERVER_REPO}}"
readonly TARGET_REPO="${SYNC_TARGET_REPO:-${GITLAB_REPO}}"
readonly SOURCE_BRANCH="${SYNC_SOURCE_BRANCH:-main}"
readonly TARGET_BRANCH="${SYNC_TARGET_BRANCH:-main}"
readonly SYNC_LOG_FILE="artifacts/gitlab-mirror-sync.log"
readonly SYNC_REPORT_FILE="artifacts/gitlab-mirror-sync-report.json"
readonly MIRROR_TEMP_DIR="/tmp/code-server-mirror-sync-$$"

# ============================================================================
# Logging & Utilities
# ============================================================================

log_info() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [INFO] $*" | tee -a "$SYNC_LOG_FILE"
}

log_error() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [ERROR] $*" | tee -a "$SYNC_LOG_FILE" >&2
}

log_success() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [SUCCESS] $*" | tee -a "$SYNC_LOG_FILE"
}

cleanup() {
    log_info "Cleaning up temporary directory: $MIRROR_TEMP_DIR"
    rm -rf "$MIRROR_TEMP_DIR" || true
}

trap cleanup EXIT

# ============================================================================
# Validation
# ============================================================================

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check git
    if ! command -v git &>/dev/null; then
        log_error "git not found in PATH"
        return 1
    fi
    
    # Check GitHub token
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN not set"
        return 1
    fi
    
    # Check network connectivity to both repos
    log_info "Verifying GitHub connectivity..."
    if ! git ls-remote "$SOURCE_REPO" HEAD >/dev/null 2>&1; then
        log_error "Cannot connect to source repo: $SOURCE_REPO"
        return 1
    fi
    
    if ! git ls-remote "$TARGET_REPO" HEAD >/dev/null 2>&1; then
        log_error "Cannot connect to target repo: $TARGET_REPO"
        return 1
    fi
    
    log_success "Prerequisites validated"
    return 0
}

# ============================================================================
# Mirror Sync Implementation
# ============================================================================

perform_mirror_sync() {
    log_info "Starting mirror sync..."
    log_info "Source: $SOURCE_REPO ($SOURCE_BRANCH)"
    log_info "Target: $TARGET_REPO ($TARGET_BRANCH)"
    
    # Create temporary work directory
    mkdir -p "$MIRROR_TEMP_DIR"
    cd "$MIRROR_TEMP_DIR"
    
    # Clone source repo bare (for speed)
    log_info "Fetching source repository..."
    if ! git clone --bare "$SOURCE_REPO" source-bare.git 2>>"$SYNC_LOG_FILE"; then
        log_error "Failed to clone source repository"
        return 1
    fi
    
    cd source-bare.git
    
    # Get commit info before push
    local source_commit
    source_commit=$(git rev-parse "$SOURCE_BRANCH" 2>/dev/null || echo "unknown")
    local source_author
    source_author=$(git log -1 --format="%an <%ae>" "$SOURCE_BRANCH" 2>/dev/null || echo "unknown")
    local source_message
    source_message=$(git log -1 --oneline "$SOURCE_BRANCH" 2>/dev/null || echo "unknown")
    
    log_info "Source HEAD: $source_commit"
    log_info "Latest commit: $source_message"
    log_info "Author: $source_author"
    
    # Push to target repo (force to ensure mirror is exact copy)
    log_info "Pushing to target repository..."
    if ! git push --mirror "$TARGET_REPO" 2>>"$SYNC_LOG_FILE"; then
        log_error "Failed to push mirror to target repository"
        return 1
    fi
    
    # Verify push
    log_info "Verifying mirror sync..."
    local target_commit
    target_commit=$(git ls-remote "$TARGET_REPO" "$TARGET_BRANCH" 2>/dev/null | awk '{print $1}' || echo "unknown")
    
    if [[ "$source_commit" == "$target_commit" ]]; then
        log_success "Mirror sync verified: commits match ($source_commit)"
    else
        log_error "Mirror sync verification failed: commits differ"
        log_error "  Source: $source_commit"
        log_error "  Target: $target_commit"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Report Generation
# ============================================================================

generate_report() {
    local status="$1"
    local source_commit="$2"
    local target_commit="$3"
    local sync_message="$4"
    
    cat > "$SYNC_REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "status": "$status",
  "source_repo": "$SOURCE_REPO",
  "source_branch": "$SOURCE_BRANCH",
  "source_commit": "$source_commit",
  "target_repo": "$TARGET_REPO",
  "target_branch": "$TARGET_BRANCH",
  "target_commit": "$target_commit",
  "message": "$sync_message",
  "log_file": "$SYNC_LOG_FILE"
}
EOF
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_info "=========================================="
    log_info "GitLab Mirror Sync Initiated"
    log_info "=========================================="
    
    # Validate
    if ! validate_prerequisites; then
        log_error "Validation failed - aborting sync"
        generate_report "FAILED" "unknown" "unknown" "Prerequisites validation failed"
        return 1
    fi
    
    # Perform sync
    if perform_mirror_sync; then
        log_success "=========================================="
        log_success "Mirror sync COMPLETE"
        log_success "=========================================="
        log_success "code-server main branch mirrored to kushin77/source-control"
        
        local source_commit
        source_commit=$(git -C "$MIRROR_TEMP_DIR/source-bare.git" rev-parse "$SOURCE_BRANCH")
        
        generate_report "SUCCESS" "$source_commit" "$source_commit" "Mirror sync successful"
        return 0
    else
        log_error "=========================================="
        log_error "Mirror sync FAILED"
        log_error "=========================================="
        
        generate_report "FAILED" "unknown" "unknown" "Mirror sync failed - see log for details"
        return 1
    fi
}

# Execute
main "$@"
