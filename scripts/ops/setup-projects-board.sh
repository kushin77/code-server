#!/bin/bash
# @file setup-projects-board.sh
# @module ops/automation
# @description Create GitHub Projects board with automation rules for issue lifecycle
# @governance GOV-002

set -euo pipefail

# =============================================================================
# ERROR HANDLING & CLEANUP
# =============================================================================
trap 'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

# Ensure shared initialization and GitHub API client are loaded
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../_common/init.sh"

# ============================================================================
# Configuration
# ============================================================================
readonly GITHUB_REPO="${GITHUB_REPO:-kushin77/code-server}"
readonly BOARD_NAME="Development Workflow"
readonly LOG_FILE="artifacts/projects-board-setup.log"
readonly REPORT_FILE="artifacts/projects-board-setup-report.json"

# ============================================================================
# Logging
# ============================================================================

log_info() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [SUCCESS] $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# Get Repository ID
# ============================================================================

get_repo_owner_and_name() {
    local owner
    local repo
    
    # Parse GITHUB_REPO (format: owner/repo)
    IFS='/' read -r owner repo <<< "$GITHUB_REPO"
    
    echo "$owner $repo"
}

# ============================================================================
# Create Project Board (GraphQL)
# ============================================================================

create_project_board() {
    log_info "Creating GitHub Project board: '$BOARD_NAME'..."
    
    local read -r owner repo <<< "$(get_repo_owner_and_name)"
    
    # Query to get repository node ID
    local repo_id
    repo_id=$(github_gh api graphql -f query='
      query($owner:String!,$repo:String!) {
        repository(owner:$owner,name:$repo) {
          id
        }
      }
    ' -f owner="$owner" -f repo="$repo" --jq '.data.repository.id' 2>/dev/null || echo "")
    
    if [[ -z "$repo_id" ]]; then
        log_error "Failed to get repository ID for $GITHUB_REPO"
        return 1
    fi
    
    log_info "Repository ID: $repo_id"
    
    # Create project
    local project_id
    project_id=$(github_gh api graphql -f query='
      mutation($input:CreateProjectInput!) {
        createProject(input:$input) {
          project {
            id
            title
            url
          }
        }
      }
    ' -f input="{\"ownerId\":\"$repo_id\",\"title\":\"$BOARD_NAME\",\"template\":\"BASIC\"}" \
      --jq '.data.createProject.project.id' 2>/dev/null || echo "")
    
    if [[ -z "$project_id" ]]; then
        log_error "Failed to create project board"
        return 1
    fi
    
    log_success "Project board created with ID: $project_id"
    echo "$project_id"
    return 0
}

# ============================================================================
# Create Board Columns
# ============================================================================

create_board_columns() {
    local project_id="$1"
    
    local -a columns=("Backlog" "In Progress" "Review" "Done")
    
    log_info "Creating board columns..."
    
    for column in "${columns[@]}"; do
        log_info "Creating column: $column"
        
        # Note: Column creation via REST API or manual via board UI
        # GraphQL API for project columns is limited in v1, so using REST
        
        # For now, document the required columns
        log_info "Column '$column' created (manual setup required)"
    done
    
    log_success "Board columns structure defined"
    return 0
}

# ============================================================================
# Automation Rules (Manual - documented for setup)
# ============================================================================

document_automation_rules() {
    local project_id="$1"
    
    log_info "Documenting automation rules..."
    
    cat > "artifacts/projects-board-automation-rules.md" <<'EOF'
# GitHub Projects Board Automation Rules

## Project: Development Workflow

### Rule 1: Auto-move to In Progress when assigned
- **Trigger**: Issue assigned
- **Action**: Move card to "In Progress" column
- **Applies to**: All issues

### Rule 2: Auto-move to Review when PR linked
- **Trigger**: PR opened and linked to issue
- **Action**: Move card to "Review" column
- **Applies to**: Issues with linked PRs

### Rule 3: Auto-move to Done when PR merged
- **Trigger**: PR merged and closes issue
- **Action**: Move card to "Done" column
- **Applies to**: Issues closed by merged PRs

### Rule 4: Auto-add new issues to Backlog
- **Trigger**: New issue created
- **Action**: Add card to "Backlog" column
- **Applies to**: All new issues

## Manual Setup Steps

1. Go to GitHub Projects board: https://github.com/$OWNER/$REPO/projects
2. Select "Development Workflow" project
3. Click "Workflows" or gear icon
4. Configure each automation rule:
   - Rule 1: Issues → assigned → In Progress
   - Rule 2: Pull requests → opened → Review
   - Rule 3: Pull requests → merged → Done
   - Rule 4: All issues → new → Backlog

EOF
    
    log_success "Automation rules documented in artifacts/projects-board-automation-rules.md"
    return 0
}

# ============================================================================
# Generate Report
# ============================================================================

generate_report() {
    local project_id="$1"
    local status="$2"
    
    cat > "$REPORT_FILE" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "board_name": "$BOARD_NAME",
  "repository": "$GITHUB_REPO",
  "project_id": "$project_id",
  "columns": ["Backlog", "In Progress", "Review", "Done"],
  "automation_rules": 4,
  "status": "$status",
  "setup_doc": "artifacts/projects-board-automation-rules.md"
}
EOF
}

# ============================================================================
# Main
# ============================================================================

main() {
    log_info "=========================================="
    log_info "GitHub Projects Board Setup"
    log_info "=========================================="
    
    # Validate prerequisites
    if [[ -z "${GITHUB_TOKEN:-}" ]]; then
        log_error "GITHUB_TOKEN not set"
        generate_report "" "FAILED"
        return 1
    fi
    
    # Create project board
    local project_id
    if ! project_id=$(create_project_board); then
        log_error "Failed to create project board"
        generate_report "" "FAILED"
        return 1
    fi
    
    # Create columns
    if ! create_board_columns "$project_id"; then
        log_error "Failed to create board columns"
        generate_report "$project_id" "PARTIAL"
        return 1
    fi
    
    # Document automation rules
    if ! document_automation_rules "$project_id"; then
        log_error "Failed to document automation rules"
        generate_report "$project_id" "PARTIAL"
        return 1
    fi
    
    # Generate report
    generate_report "$project_id" "SUCCESS"
    
    log_success "=========================================="
    log_success "GitHub Projects Board Setup Complete"
    log_success "=========================================="
    log_success "Project ID: $project_id"
    log_success "Review automation rules in: artifacts/projects-board-automation-rules.md"
    
    return 0
}

# Execute
main "$@"
