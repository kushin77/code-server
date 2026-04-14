#!/usr/bin/env bash
################################################################################
# common-functions.sh
# ⚠️  DEPRECATED — Use scripts/_common/init.sh instead.
#
# This file is a compatibility shim. It will be removed in a future release.
# Migration: replace
#   source ./scripts/common-functions.sh
# with:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/_common/init.sh"
#
# Status: DEPRECATED
# Deprecated-By: scripts/_common/utils.sh + scripts/_common/error-handler.sh
################################################################################

# Emit deprecation warning (visible in CI log, does not break caller)
echo "⚠️  DEPRECATION WARNING: sourcing scripts/common-functions.sh is deprecated." >&2
echo "   Migrate to: source \"\$SCRIPT_DIR/_common/init.sh\"" >&2

# Forward to canonical implementations where possible
_SHIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_SHIM_DIR/_common/logging.sh" ]] && [[ -f "$_SHIM_DIR/_common/utils.sh" ]]; then
    source "$_SHIM_DIR/_common/logging.sh"
    source "$_SHIM_DIR/_common/utils.sh"
    unset _SHIM_DIR
    return 0
fi
unset _SHIM_DIR

# Fallback: original implementation below (kept intact for safety)


# Color codes for terminal output
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[0;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'

# ─────────────────────────────────────────────────────────────────────────────
# FORMATTING & OUTPUT
# ─────────────────────────────────────────────────────────────────────────────

write_success() {
    local message="$1"
    echo -e "${COLOR_GREEN}✅ ${message}${COLOR_RESET}"
}

write_error() {
    local message="$1"
    echo -e "${COLOR_RED}❌ ${message}${COLOR_RESET}" >&2
}

write_warning() {
    local message="$1"
    echo -e "${COLOR_YELLOW}⚠️  ${message}${COLOR_RESET}"
}

write_info() {
    local message="$1"
    echo -e "${COLOR_CYAN}ℹ️  ${message}${COLOR_RESET}"
}

write_section() {
    local title="$1"
    echo -e "\n${COLOR_CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "▶ ${title}"
    echo -e "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}\n"
}

# ─────────────────────────────────────────────────────────────────────────────
# GITHUB API OPERATIONS (Consolidated)
# ─────────────────────────────────────────────────────────────────────────────

invoke_github_api() {
    local method="${1:-GET}"
    local endpoint="$2"
    local data="${3:-}"
    local raw="${4:-false}"

    local gh_args=("api" "-X" "$method" "$endpoint")

    if [[ -n "$data" ]]; then
        gh_args+=("-d" "$data")
    fi

    if [[ "$raw" == "true" ]]; then
        gh "${gh_args[@]}" --raw
    else
        gh "${gh_args[@]}" --jq '.'
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# UI UTILITIES
# ─────────────────────────────────────────────────────────────────────────────

prompt_yn() {
    local prompt="$1"
    local response

    while true; do
        read -p "$prompt (y/n): " response
        case "$response" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "Please answer y or n" ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# ERROR HANDLING
# ─────────────────────────────────────────────────────────────────────────────

die() {
    local message="${1:-Unknown error}"
    write_error "$message"
    exit 1
}

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        die "Required command not found: $cmd"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# GITHUB PR/ISSUE OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

get_pr_status() {
    local pr_number="$1"
    local repo="${2:-kushin77/code-server}"

    gh pr view "$pr_number" --repo "$repo" --json mergeStateStatus,state,statusCheckRollup \
        --jq '{state: .state, mergeState: .mergeStateStatus, checks: .statusCheckRollup}'
}

get_pr_check_status() {
    local pr_number="$1"
    local repo="${2:-kushin77/code-server}"

    gh pr checks "$pr_number" --repo "$repo"
}

merge_pr() {
    local pr_number="$1"
    local repo="${2:-kushin77/code-server}"
    local method="${3:-merge}"

    gh pr merge "$pr_number" --repo "$repo" --"$method"
}

# ─────────────────────────────────────────────────────────────────────────────
# BRANCH PROTECTION OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

get_branch_protection() {
    local owner="$1"
    local repo="$2"
    local branch="${3:-main}"

    gh api repos/"$owner"/"$repo"/branches/"$branch"/protection --jq '.'
}

update_branch_protection() {
    local owner="$1"
    local repo="$2"
    local branch="${3:-main}"
    local protection_json="$4"

    gh api -X PUT repos/"$owner"/"$repo"/branches/"$branch"/protection -d "$protection_json"
}

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION
# ─────────────────────────────────────────────────────────────────────────────

require_github_auth() {
    if ! gh auth status &> /dev/null; then
        die "GitHub CLI not authenticated. Run: gh auth login"
    fi
    write_success "GitHub CLI authenticated"
}

require_github_cli() {
    require_command "gh"
    require_github_auth
}

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

wait_for_service_healthy() {
    local service="$1"
    local timeout="${2:-180}"  # seconds
    local check_interval="${3:-5}"

    local elapsed=0
    while (( elapsed < timeout )); do
        if docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" "$service" 2>/dev/null | grep -q "healthy"; then
            write_success "Service $service is healthy"
            return 0
        fi
        sleep "$check_interval"
        elapsed=$((elapsed + check_interval))
    done

    write_error "Timeout waiting for service $service to be healthy"
    return 1
}

# ─────────────────────────────────────────────────────────────────────────────
# UTILITY FUNCTIONS
# ─────────────────────────────────────────────────────────────────────────────

get_repo_root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}

ensure_in_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        die "Not in a git repository"
    fi
}

get_timestamp() {
    date "+%Y%m%d_%H%M%S"
}

log_to_file() {
    local log_file="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$log_file"
}
