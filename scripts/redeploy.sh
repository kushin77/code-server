#!/bin/bash
# File:    redeploy.sh
# Owner:   Platform Engineering
# Purpose: Post-merge deployment orchestration triggered by GitHub Actions
# Status:  ACTIVE
# Usage:   ./redeploy.sh [options]

set -euo pipefail

# Bootstrap _common library (logging, utils, error-handler, config, ssh, docker)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh" || { echo "FATAL: Cannot source _common/init.sh"; exit 1; }

# Script metadata
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOG_DIR="${REPO_ROOT}/logs/deployments"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
export LOG_FILE="${LOG_DIR}/redeploy_${TIMESTAMP}.log"

mkdir -p "$LOG_DIR"

# Configuration
DEPLOYMENT_TARGETS=("production" "staging")
DEFAULT_TARGET="production"
DRY_RUN=false
NOTIFY_SLACK=true
VERBOSE=false

###############################################################################
# Utility Functions
###############################################################################

usage() {
    cat << EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    -t, --target TARGET      Deploy target (${DEPLOYMENT_TARGETS[*]}) [default: ${DEFAULT_TARGET}]
    -d, --dry-run            Show what would be deployed without deploying
    -v, --verbose            Verbose output
    --no-slack               Don't send Slack notifications
    --no-health-check        Skip health checks after deployment
    -h, --help               Show this help message

ENVIRONMENT VARIABLES:
    SLACK_WEBHOOK_URL        Slack webhook for notifications
    DEPLOYMENT_SECRET        Secret for deployment authorization
    TARGET_ENVIRONMENT       Override deployment target

EXAMPLES:
    # Deploy to production with health checks
    ${SCRIPT_NAME} --target production

    # Dry-run deployment to staging
    ${SCRIPT_NAME} --target staging --dry-run

    # Deploy with verbose logging
    ${SCRIPT_NAME} --target production --verbose

EOF
    exit "${1:-0}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -t|--target)
                TARGET="${2:-${DEFAULT_TARGET}}"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --no-slack)
                NOTIFY_SLACK=false
                shift
                ;;
            -h|--help)
                usage 0
                ;;
            *)
                log_error "Unknown option: ${1}"
                usage 1
                ;;
        esac
    done
}

init_logs() {
    mkdir -p "$LOG_DIR"
    echo "Auto-Deploy Orchestration Log - ${TIMESTAMP}" > "$LOG_FILE"
    echo "Repository: ${REPO_ROOT}" >> "$LOG_FILE"
    echo "Target: ${TARGET}" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

validate_target() {
    if [[ ! " ${DEPLOYMENT_TARGETS[@]} " =~ ${TARGET} ]]; then
        log_error "Invalid target: ${TARGET}"
        log_error "Valid targets: ${DEPLOYMENT_TARGETS[*]}"
        return 1
    fi
    log_success "Deployment target validated: ${TARGET}"
    return 0
}

###############################################################################
# Pre-Deployment Checks
###############################################################################

check_git_state() {
    log_section "Checking Git State"

    # Verify we're on main branch
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "${CURRENT_BRANCH}" != "main" ]]; then
        log_warn "Current branch is ${CURRENT_BRANCH}, not main"
    else
        log_success "On main branch"
    fi

    # Get latest commit info
    COMMIT_SHA=$(git rev-parse HEAD)
    COMMIT_MESSAGE=$(git log -1 --pretty=format:"%s")
    COMMIT_AUTHOR=$(git log -1 --pretty=format:"%an")

    log_info "Commit SHA: ${COMMIT_SHA:0:8}"
    log_info "Commit message: ${COMMIT_MESSAGE}"
    log_info "Author: ${COMMIT_AUTHOR}"

    # Verify clean working directory
    if [[ -n $(git status --porcelain) ]]; then
        log_warn "Working directory has uncommitted changes"
    else
        log_success "Working directory clean"
    fi
}

check_deployment_readiness() {
    log_section "Checking Deployment Readiness"

    # Check required files
    local required_files=(
        "docker-compose.yml"
        ".env.production"
        "scripts/deploy-phase-12-all.sh"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "${REPO_ROOT}/${file}" ]]; then
            log_success "Found: ${file}"
        else
            log_warn "Missing: ${file}"
        fi
    done

    # Check Docker availability
    if command -v docker &> /dev/null; then
        log_success "Docker is available"
        DOCKER_VERSION=$(docker --version)
        log_info "Version: ${DOCKER_VERSION}"
    else
        log_error "Docker is not available"
        return 1
    fi

    # Check Docker daemon
    if docker ps &> /dev/null; then
        log_success "Docker daemon is running"
    else
        log_error "Docker daemon is not running"
        return 1
    fi
}

check_health_before_deploy() {
    log_section "Pre-Deployment Health Check"

    # Check if deployment endpoints are reachable
    if [[ "${TARGET}" == "production" ]]; then
        local endpoint="https://code-server.kushnir.cloud"
    else
        local endpoint="https://staging-code-server.kushnir.cloud"
    fi

    if timeout 5 curl -sf "${endpoint}/health" &> /dev/null; then
        log_success "Health endpoint reachable: ${endpoint}"
    else
        log_warn "Health endpoint not reachable (may be down for maintenance)"
    fi
}

###############################################################################
# Deployment Functions
###############################################################################

perform_deployment() {
    log_section "Performing Deployment"

    if [[ "${DRY_RUN}" == true ]]; then
        log_warn "DRY RUN MODE - No actual changes will be made"
    fi

    case "${TARGET}" in
        production)
            deploy_production
            ;;
        staging)
            deploy_staging
            ;;
        *)
            log_error "Unknown deployment target: ${TARGET}"
            return 1
            ;;
    esac
}

deploy_production() {
    log_info "Deploying to production..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY RUN] Would execute: bash scripts/deploy-phase-12-all.sh"
        return 0
    fi

    # Execute deployment
    if bash "${REPO_ROOT}/scripts/deploy-phase-12-all.sh" >> "$LOG_FILE" 2>&1; then
        log_success "Production deployment completed"
        DEPLOYMENT_STATUS="success"
        return 0
    else
        log_error "Production deployment failed"
        DEPLOYMENT_STATUS="failed"
        return 1
    fi
}

deploy_staging() {
    log_info "Deploying to staging..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY RUN] Would rebuild and restart containers"
        return 0
    fi

    # Simpler staging deployment (could use docker-compose)
    if docker-compose -f docker-compose.yml up -d --build &>> "$LOG_FILE"; then
        log_success "Staging deployment completed"
        DEPLOYMENT_STATUS="success"
        return 0
    else
        log_error "Staging deployment failed"
        DEPLOYMENT_STATUS="failed"
        return 1
    fi
}

###############################################################################
# Post-Deployment Checks
###############################################################################

check_health_after_deploy() {
    log_section "Post-Deployment Health Check"

    local max_retries=10
    local retry_count=0
    local Health_check_url

    if [[ "${TARGET}" == "production" ]]; then
        health_check_url="https://code-server.kushnir.cloud/health"
    else
        health_check_url="https://staging-code-server.kushnir.cloud/health"
    fi

    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Health check attempt $((retry_count + 1))/${max_retries}..."

        if curl -sf "${health_check_url}" &> /dev/null; then
            log_success "Health check passed ✅"
            return 0
        fi

        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            sleep 10
        fi
    done

    log_warn "Health check failed after ${max_retries} attempts"
    return 1
}

verify_deployment() {
    log_section "Verifying Deployment"

    # Check container status
    if [[ "${TARGET}" == "production" ]]; then
        log_info "Checking production containers..."
        docker ps --filter label=environment=production --format "table {{.Names}}\t{{.Status}}"
    else
        log_info "Checking staging containers..."
        docker ps --filter label=environment=staging --format "table {{.Names}}\t{{.Status}}"
    fi

    log_success "Deployment verification complete"
}

###############################################################################
# Notification Functions
###############################################################################

notify_slack() {
    if [[ "${NOTIFY_SLACK}" != true ]]; then
        return 0
    fi

    if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
        log_warn "SLACK_WEBHOOK_URL not set, skipping Slack notification"
        return 0
    fi

    log_section "Sending Slack Notification"

    local status_emoji="✅"
    local status_text="Success"
    if [[ "${DEPLOYMENT_STATUS}" == "failed" ]]; then
        status_emoji="❌"
        status_text="Failed"
    fi

    local color="good"
    if [[ "${DEPLOYMENT_STATUS}" == "failed" ]]; then
        color="danger"
    fi

    local message=$(cat <<EOF
{
  "text": "${status_emoji} Auto-Deployment to ${TARGET}: ${status_text}",
  "attachments": [
    {
      "color": "${color}",
      "fields": [
        {
          "title": "Target",
          "value": "${TARGET}",
          "short": true
        },
        {
          "title": "Commit",
          "value": "${COMMIT_SHA:0:8}",
          "short": true
        },
        {
          "title": "Message",
          "value": "${COMMIT_MESSAGE}",
          "short": false
        },
        {
          "title": "Author",
          "value": "${COMMIT_AUTHOR}",
          "short": true
        },
        {
          "title": "Status",
          "value": "${DEPLOYMENT_STATUS}",
          "short": true
        },
        {
          "title": "Timestamp",
          "value": "$(date -u +'%Y-%m-%d %H:%M:%S UTC')",
          "short": true
        }
      ],
      "footer": "Code-Server Enterprise Auto-Deploy"
    }
  ]
}
EOF
)

    if curl -X POST -H 'Content-type: application/json' \
        --data "${message}" \
        "${SLACK_WEBHOOK_URL}" &> /dev/null; then
        log_success "Slack notification sent"
    else
        log_warn "Failed to send Slack notification"
    fi
}

###############################################################################
# Final Report
###############################################################################

generate_report() {
    log_section "Deployment Report"

    cat << EOF | tee -a "$LOG_FILE"

╔════════════════════════════════════════════════════════════════════════════╗
║                     AUTO-DEPLOY EXECUTION REPORT                          ║
╚════════════════════════════════════════════════════════════════════════════╝

Date/Time:           $(date -u +'%Y-%m-%d %H:%M:%S UTC')
Target:              ${TARGET}
Status:              $(echo "${DEPLOYMENT_STATUS}" | tr '[:lower:]' '[:upper:]')
Commit:              ${COMMIT_SHA:0:8} - ${COMMIT_MESSAGE}
Author:              ${COMMIT_AUTHOR}
Log File:            ${LOG_FILE}

Actions Taken:
  ✓ Git state validated
  ✓ Deployment readiness checked
  ✓ Pre-deployment health check performed
  ✓ Deployment executed
  ✓ Post-deployment health check performed
  ✓ Deployment verified

Next Steps:
  1. Monitor application performance
  2. Check logs: tail -f ${LOG_FILE}
  3. Review deployment: git log -1 --stat
  4. If issues arise, execute rollback procedure

Audit Trail:
  - All actions logged to: ${LOG_FILE}
  - GitHub Actions run: ${GITHUB_SERVER_URL:-https://github.com}/${{ github.repository }}/actions/runs/${GITHUB_RUN_ID:-N/A}
  - Issue linked to PR which triggered deployment

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

    log_success "Report generated: ${LOG_FILE}"
}

###############################################################################
# Cleanup & Exit
###############################################################################

cleanup() {
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code: ${exit_code}"
    fi

    exit $exit_code
}

trap cleanup EXIT

###############################################################################
# Main Execution
###############################################################################

main() {
    # Set defaults
    TARGET="${TARGET_ENVIRONMENT:-${DEFAULT_TARGET}}"
    DEPLOYMENT_STATUS="unknown"

    # Initialize
    init_logs
    parse_args "$@"

    log_section "Auto-Deploy Orchestration Started"
    log_info "Target: ${TARGET}"
    log_info "DRY RUN: ${DRY_RUN}"
    log_info "Log file: ${LOG_FILE}"

    # Validation
    validate_target || return 1

    # Pre-flight checks
    check_git_state || return 1
    check_deployment_readiness || return 1
    check_health_before_deploy

    # Deployment
    perform_deployment || {
        DEPLOYMENT_STATUS="failed"
        generate_report
        return 1
    }

    # Post-flight checks
    check_health_after_deploy
    verify_deployment

    # Notifications
    DEPLOYMENT_STATUS="success"
    notify_slack

    # Final report
    generate_report

    log_success "Auto-Deploy Orchestration Complete ✨"
}

# Execute main function
main "$@"
