#!/usr/bin/env bash
###############################################################################
# ENTERPRISE GITHUB OPERATIONS SCRIPT
# 
# Purpose: Reliable GitHub API operations with full PAT scopes
# Usage: ./scripts/github-ops.sh <command> [args...]
# 
# Features:
#   - Full authentication (PAT with repo+admin scopes)
#   - Batch operations (close multiple issues/PRs at once)
#   - Audit logging (who, when, what, why)
#   - Retry logic with exponential backoff
#   - Error handling and validation
#   - Structured JSON output
#   - Consistent across all sessions
###############################################################################

set -euo pipefail

# Configuration
readonly REPO="${GH_REPO:-kushin77/code-server}"
readonly GH_HOST="${GH_HOST:-github.com}"
readonly LOG_FILE="${LOG_FILE:-.github/operations.log}"
readonly RETRY_ATTEMPTS=3
readonly RETRY_DELAY=2
readonly REQUIRED_SCOPES="${REQUIRED_SCOPES:-repo}"
readonly ENFORCE_GSM_PAT="${ENFORCE_GSM_PAT:-true}"
readonly GSM_PROJECT="${GSM_PROJECT:-}"
readonly GSM_SECRET_CANDIDATES="${GSM_SECRET_CANDIDATES:-code-server-enterprise-github-token,github-token,github-pat,prod-github-token,prod-github-pat}"
readonly GSM_FETCH_TIMEOUT_SECONDS="${GSM_FETCH_TIMEOUT_SECONDS:-8}"

AUTH_TOKEN=""
AUTH_SOURCE=""

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

###############################################################################
# LOGGING & OUTPUT
###############################################################################

log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${msg}" >> "${LOG_FILE}"
}

info() {
    echo -e "${BLUE}ℹ${NC} $*"
    log "INFO" "$*"
}

success() {
    echo -e "${GREEN}✓${NC} $*"
    log "SUCCESS" "$*"
}

error() {
    echo -e "${RED}✗${NC} $*" >&2
    log "ERROR" "$*"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $*"
    log "WARN" "$*"
}

###############################################################################
# AUTH & VALIDATION
###############################################################################

validate_auth() {
    load_auth_token

    if ! gh_cmd api user >/dev/null 2>&1; then
        error "GitHub API authentication failed for ${GH_HOST} (source: ${AUTH_SOURCE})"
        exit 1
    fi

    success "GitHub authentication verified for ${GH_HOST} (source: ${AUTH_SOURCE})"
}

get_token() {
    gh_cmd auth token 2>/dev/null || {
        error "Unable to retrieve GitHub token"
        exit 1
    }
}

gh_cmd() {
    GH_TOKEN="${AUTH_TOKEN}" \
    GITHUB_TOKEN="${AUTH_TOKEN}" \
    GH_HOST="${GH_HOST}" \
    gh "$@"
}

resolve_gsm_project() {
    if [ -n "${GSM_PROJECT}" ]; then
        echo "${GSM_PROJECT}"
        return 0
    fi

    gcloud config get-value project 2>/dev/null | tr -d '[:space:]'
}

fetch_gsm_token() {
    if ! command -v gcloud >/dev/null 2>&1; then
        return 1
    fi

    local project
    project="$(resolve_gsm_project)"
    if [ -z "${project}" ]; then
        return 1
    fi

    local secret_name
    IFS=',' read -r -a candidate_names <<< "${GSM_SECRET_CANDIDATES}"
    for secret_name in "${candidate_names[@]}"; do
        secret_name="$(echo "${secret_name}" | xargs)"
        [ -z "${secret_name}" ] && continue

        if command -v timeout >/dev/null 2>&1; then
            token_value="$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 timeout "${GSM_FETCH_TIMEOUT_SECONDS}" gcloud --quiet secrets versions access latest --secret="${secret_name}" --project="${project}" 2>/dev/null || true)"
        else
            token_value="$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud --quiet secrets versions access latest --secret="${secret_name}" --project="${project}" 2>/dev/null || true)"
        fi

        if [ -n "${token_value}" ]; then
            AUTH_TOKEN="${token_value}"
            AUTH_SOURCE="gsm:${project}/${secret_name}"
            return 0
        fi
    done

    return 1
}

load_auth_token() {
    if [ -n "${AUTH_TOKEN}" ]; then
        return 0
    fi

    if [ "${ENFORCE_GSM_PAT}" = "true" ]; then
        if fetch_gsm_token; then
            return 0
        fi

        error "GSM PAT retrieval failed. Reauthenticate gcloud and ensure one of these secrets exists: ${GSM_SECRET_CANDIDATES}"
        exit 1
    fi

    if [ -n "${GITHUB_TOKEN:-}" ]; then
        AUTH_TOKEN="${GITHUB_TOKEN}"
        AUTH_SOURCE="env:GITHUB_TOKEN"
        return 0
    fi

    if fetch_gsm_token; then
        return 0
    fi

    if fallback_token="$(gh auth token 2>/dev/null)" && [ -n "${fallback_token}" ]; then
        AUTH_TOKEN="${fallback_token}"
        AUTH_SOURCE="gh-auth"
        return 0
    fi

    error "Unable to load GitHub PAT from GSM or gh auth"
    exit 1
}

check_repo_access() {
    if ! gh_cmd repo view "${REPO}" &>/dev/null; then
        error "Repository ${REPO} not accessible"
        exit 1
    fi
    success "Repository access confirmed: ${REPO}"
}

validate_scopes() {
    local status_output
    status_output="$(gh_cmd api -i / 2>&1 || true)"

    if [ -z "${status_output}" ]; then
        error "Unable to inspect auth scopes for ${GH_HOST}"
        exit 1
    fi

    local missing=0
    local required_scope
    IFS=',' read -r -a scopes <<< "${REQUIRED_SCOPES}"
    for required_scope in "${scopes[@]}"; do
        required_scope="$(echo "${required_scope}" | xargs)"
        if [ -n "${required_scope}" ] && ! echo "${status_output}" | grep -qi "x-oauth-scopes:.*${required_scope}"; then
            error "Missing required token scope: ${required_scope}"
            missing=1
        fi
    done

    if [ "${missing}" -ne 0 ]; then
        error "Token scopes are insufficient. Required scopes: ${REQUIRED_SCOPES}"
        exit 1
    fi

    success "Token scopes validated (${REQUIRED_SCOPES})"
}

###############################################################################
# ISSUE OPERATIONS
###############################################################################

close_issue() {
    local issue_number="$1"
    local reason="${2:-completed}"

    if [ -z "${issue_number}" ]; then
        error "Issue number is required"
        return 1
    fi

    local state
    state="$(gh_cmd issue view "${issue_number}" --repo "${REPO}" --json state --template '{{.state}}' 2>/dev/null || echo "UNKNOWN")"
    if [ "${state}" = "CLOSED" ]; then
        success "Issue #${issue_number} is already closed"
        return 0
    fi
    
    info "Closing issue #${issue_number} (reason: ${reason})"

    if gh_cmd issue close "${issue_number}" \
        --repo "${REPO}" \
        --reason "${reason}" >/dev/null 2>&1; then
        success "Issue #${issue_number} closed"
        return 0
    fi

    error "Failed to close issue #${issue_number}"
    return 1
}

close_issues_batch() {
    local -a issues=("$@")
    local failed=0
    local total=${#issues[@]}
    local succeeded=0
    
    info "Closing ${total} issues in batch mode..."
    
    for issue in "${issues[@]}"; do
        if retry_with_backoff close_issue "${issue}" "completed"; then
            succeeded=$((succeeded + 1))
        else
            failed=$((failed + 1))
        fi
        sleep 0.5  # Rate limiting
    done
    
    info "Batch summary: ${succeeded} succeeded, ${failed} failed, ${total} total"

    if [ $failed -eq 0 ]; then
        success "All ${total} issues closed successfully"
    else
        warn "${failed}/${total} issues failed to close"
        return 1
    fi
}

add_comment() {
    local issue_number="$1"
    local comment="$2"
    
    info "Adding comment to issue #${issue_number}"
    
    if gh_cmd issue comment "${issue_number}" \
        --repo "${REPO}" \
        --body "${comment}" >/dev/null 2>&1; then
        success "Comment added to #${issue_number}"
        return 0
    fi

    error "Failed to add comment to #${issue_number}"
    return 1
}

get_issue_status() {
    local issue_number="$1"
    
    gh_cmd issue view "${issue_number}" \
        --repo "${REPO}" \
        --json state,title,labels \
        --template '{{.state}} - {{.title}}'
}

list_issues_by_label() {
    local label="$1"
    
    gh_cmd issue list \
        --repo "${REPO}" \
        --label "${label}" \
        --state all \
        --limit 100 \
        --json number,title,state
}

###############################################################################
# PULL REQUEST OPERATIONS
###############################################################################

close_pr() {
    local pr_number="$1"
    
    info "Closing PR #${pr_number}"
    
    if gh_cmd pr close "${pr_number}" \
        --repo "${REPO}" >/dev/null 2>&1; then
        success "PR #${pr_number} closed"
        return 0
    fi

    error "Failed to close PR #${pr_number}"
    return 1
}

merge_pr() {
    local pr_number="$1"
    local merge_method="${2:-squash}"
    
    info "Merging PR #${pr_number} (method: ${merge_method})"
    
    if gh_cmd pr merge "${pr_number}" \
        --repo "${REPO}" \
        --"${merge_method}" \
        --delete-branch >/dev/null 2>&1; then
        success "PR #${pr_number} merged"
        return 0
    fi

    error "Failed to merge PR #${pr_number}"
    return 1
}

###############################################################################
# BATCH OPERATIONS
###############################################################################

close_completed_issues() {
    # Enterprise default batch: 17 issues marked complete across P0/P1/P2/P3
    local -a issues=(
        412 413 414 415  # P0 Security
        416 417 431      # P1 Operational
        363 364 366 374 365 373 418  # P2 Infrastructure
        410 422 423      # P3 Performance + completed consolidation items
    )
    
    close_issues_batch "${issues[@]}"
}

update_issue_labels() {
    local issue_number="$1"
    local -a labels=("$@")
    labels=("${labels[@]:1}")  # Remove issue number from array
    
    info "Updating labels for issue #${issue_number}"
    
    local labels_arg=$(printf '%s,' "${labels[@]}" | sed 's/,$//')
    
    if gh_cmd issue edit "${issue_number}" \
        --repo "${REPO}" \
        --add-label "${labels_arg}" >/dev/null 2>&1; then
        success "Labels updated for #${issue_number}"
        return 0
    fi

    error "Failed to update labels for #${issue_number}"
    return 1
}

###############################################################################
# VALIDATION & REPORTING
###############################################################################

validate_issue_closure() {
    local issue_number="$1"
    local state
    
    state=$(gh_cmd issue view "${issue_number}" \
        --repo "${REPO}" \
        --json state \
        --template '{{.state}}' 2>/dev/null || echo "unknown")
    
    if [ "${state}" = "CLOSED" ]; then
        success "Issue #${issue_number} confirmed closed"
        return 0
    else
        error "Issue #${issue_number} is still ${state}"
        return 1
    fi
}

generate_closure_report() {
    local -a issues=("$@")
    local report_file="${REPO%/*}-closure-report-$(date +%s).txt"
    
    {
        echo "============================================================"
        echo "GitHub Issues Closure Report"
        echo "Repository: ${REPO}"
        echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "============================================================"
        echo ""
        
        for issue in "${issues[@]}"; do
            echo "Issue #${issue}:"
            gh_cmd issue view "${issue}" \
                --repo "${REPO}" \
                --json number,title,state,labels \
                --template 'State: {{.state}} | Title: {{.title}} | Labels: {{range .labels}}{{.name}} {{end}}\n'
            echo ""
        done
    } | tee "${report_file}"
    
    success "Closure report saved to ${report_file}"
}

###############################################################################
# RETRY LOGIC
###############################################################################

retry_with_backoff() {
    local attempt=1
    until "$@"; do
        if [ $attempt -ge $RETRY_ATTEMPTS ]; then
            return 1
        fi
        warn "Attempt $attempt failed, retrying in ${RETRY_DELAY}s..."
        sleep $((RETRY_DELAY * attempt))
        attempt=$((attempt + 1))
    done
    return 0
}

###############################################################################
# CLI INTERFACE
###############################################################################

usage() {
    cat << 'EOF'
ENTERPRISE GITHUB OPERATIONS

Usage: ./scripts/github-ops.sh <command> [args...]

COMMANDS:

  close-issue <number> [reason]
    Close a single issue
    
  close-issues <number> [number] [number] ...
    Close multiple issues (space-separated)
    
  close-completed
    Close all 17 completed P0/P1/P2/P3 issues
    
  close-pr <number>
    Close a pull request
    
  merge-pr <number> [method]
    Merge PR (method: squash|merge|rebase, default: squash)
    
  comment <number> <text>
    Add comment to issue
    
  status <number>
    Get issue status
    
  list-by-label <label>
    List all issues with label
    
  update-labels <number> <label> [label] ...
    Update issue labels
    
  validate-closure <number> [number] ...
    Verify issues are closed
    
  report <number> [number] ...
    Generate closure report

EXAMPLES:

  # Close single issue
  ./scripts/github-ops.sh close-issue 412
  
  # Close multiple issues
  ./scripts/github-ops.sh close-issues 412 413 414 415
  
  # Close all 17 completed issues
  ./scripts/github-ops.sh close-completed
  
  # Validate closure
  ./scripts/github-ops.sh validate-closure 412 413 414 415
  
  # Generate report
  ./scripts/github-ops.sh report 412 413 414 415

AUTHENTICATION:

    Default: GSM PAT (ENFORCE_GSM_PAT=true)
    Scopes needed: repo, admin:org, workflow

    Required env:
        GSM_PROJECT=<gcp-project-id>
        GSM_SECRET_CANDIDATES=code-server-enterprise-github-token,github-token,github-pat

    Optional fallback (not recommended):
        ENFORCE_GSM_PAT=false
        gh auth login

EOF
}

###############################################################################
# MAIN
###############################################################################

main() {
    local command="${1:-}"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "${LOG_FILE}")"
    
    case "${command}" in
        validate-auth)
            validate_auth
            validate_scopes
            check_repo_access
            ;;
        close-issue)
            validate_auth
            validate_scopes
            check_repo_access
            close_issue "${2:-}" "${3:-completed}"
            ;;
        close-issues)
            validate_auth
            validate_scopes
            check_repo_access
            shift  # Remove command
            close_issues_batch "$@"
            ;;
        close-completed)
            validate_auth
            validate_scopes
            check_repo_access
            close_completed_issues
            ;;
        close-pr)
            validate_auth
            validate_scopes
            check_repo_access
            close_pr "${2:-}"
            ;;
        merge-pr)
            validate_auth
            validate_scopes
            check_repo_access
            merge_pr "${2:-}" "${3:-squash}"
            ;;
        comment)
            validate_auth
            validate_scopes
            check_repo_access
            add_comment "${2:-}" "${3:-}"
            ;;
        status)
            validate_auth
            validate_scopes
            check_repo_access
            get_issue_status "${2:-}"
            ;;
        list-by-label)
            validate_auth
            validate_scopes
            check_repo_access
            list_issues_by_label "${2:-}"
            ;;
        update-labels)
            validate_auth
            validate_scopes
            check_repo_access
            shift  # Remove command
            update_issue_labels "$@"
            ;;
        validate-closure)
            validate_auth
            validate_scopes
            check_repo_access
            shift  # Remove command
            for issue in "$@"; do
                validate_issue_closure "$issue"
            done
            ;;
        report)
            validate_auth
            validate_scopes
            check_repo_access
            shift  # Remove command
            generate_closure_report "$@"
            ;;
        -h|--help|help)
            usage
            ;;
        *)
            error "Unknown command: ${command}"
            usage
            exit 1
            ;;
    esac
}

# Run if sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
