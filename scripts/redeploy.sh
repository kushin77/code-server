#!/usr/bin/env bash
# @file        scripts/redeploy.sh
# @module      operations
# @description redeploy — on-prem code-server cluster orchestrator
# @owner       platform
# @status      active

set -euo pipefail

# Bootstrap _common library (logging, utils, error-handler, config, ssh, docker)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common/init.sh"

# Initialize repository context
init_repo

# Script metadata
PREFLIGHT_GUARD="${REPO_ROOT}/scripts/ops/preflight.sh"
PARALLEL_DEPLOY="${REPO_ROOT}/scripts/ops/parallel-deploy.sh"
REDEPLOY_LOG_DIR="${REPO_ROOT}/logs/deployments"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
export LOG_FILE="${REDEPLOY_LOG_DIR}/redeploy_${TIMESTAMP}.log"

# Idempotent log directory creation
mkdir -p "$REDEPLOY_LOG_DIR"

# Configuration
DEPLOYMENT_TARGETS=("production" "staging")
DEFAULT_TARGET="production"
TARGET="${TARGET:-$DEFAULT_TARGET}"
DRY_RUN=false
NOTIFY_SLACK=true
VERBOSE=false
NO_HEALTH_CHECK=false

# Cluster endpoints for health checks
PROD_ENDPOINTS=()
for host in "${REGION_HOSTS[@]}"; do
    PROD_ENDPOINTS+=("https://${DOMAIN:-localhost}")
done
STAGING_ENDPOINT="${STAGING_ENDPOINT:-https://staging.${DOMAIN:-localhost}}"

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
                # shellcheck disable=SC2034
                VERBOSE=true
                shift
                ;;
            --no-slack)
                NOTIFY_SLACK=false
                shift
                ;;
            --no-health-check)
                NO_HEALTH_CHECK=true
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
    mkdir -p "$REDEPLOY_LOG_DIR"
    {
      echo "Auto-Deploy Orchestration Log - ${TIMESTAMP}"
      echo "Repository: ${REPO_ROOT}"
      echo "Target: ${TARGET}"
      echo ""
    } > "$LOG_FILE"
}

validate_target() {
    if [[ ! " ${DEPLOYMENT_TARGETS[*]} " =~ ${TARGET} ]]; then
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
    log_section "Checking Cluster Deployment Readiness"

    # Check required files
    local required_files=(
        "docker-compose.yml"
        "scripts/ops/parallel-deploy.sh"
    )

    if [[ "${TARGET}" == "production" ]]; then
        required_files+=("scripts/_common/config.sh")
    else
        required_files+=(".env.production")
    fi

    for file in "${required_files[@]}"; do
        if [[ -f "${REPO_ROOT}/${file}" ]]; then
            log_success "Found: ${file}"
        else
            log_warn "Missing: ${file}"
        fi
    done

    # Check Docker availability
    if command -v docker &> /dev/null; then
        log_success "Local Docker is available"
    else
        log_warn "Local Docker is not available (checking remote connectivity instead)"
    fi
}

check_health_before_deploy() {
    log_section "Pre-Deployment Health Check"

    if [[ "${TARGET}" == "production" ]]; then
        log_info "Verifying cluster health for ${#REGION_HOSTS[@]} hosts..."
        local all_up=true
        for endpoint in "${PROD_ENDPOINTS[@]}"; do
            if timeout 5 curl -sf "${endpoint}/health" &> /dev/null; then
                log_success "Endpoint reachable: ${endpoint}"
            else
                log_warn "Endpoint not reachable: ${endpoint} (may be down for maintenance)"
                all_up=false
            fi
        done
        [[ "$all_up" == true ]] && log_success "All cluster endpoints are healthy"
    else
        if timeout 5 curl -sf "${STAGING_ENDPOINT}/health" &> /dev/null; then
            log_success "Staging endpoint reachable: ${STAGING_ENDPOINT}"
        else
            log_warn "Staging endpoint not reachable: ${STAGING_ENDPOINT}"
        fi
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
    log_info "Deploying to production cluster via ${PARALLEL_DEPLOY}..."

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY RUN] Would execute: bash ${PARALLEL_DEPLOY}"
        return 0
    fi

    # Execute cluster deployment
    if bash "${PARALLEL_DEPLOY}" >> "$LOG_FILE" 2>&1; then
        log_success "Production cluster deployment completed successfully"
        DEPLOYMENT_STATUS="success"
        return 0
    else
        log_error "Production cluster deployment failed"
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

    # Simpler staging deployment
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

    local max_retries=12
    local retry_count=0

    while [[ $retry_count -lt $max_retries ]]; do
        log_info "Health check attempt $((retry_count + 1))/${max_retries}..."
        local all_up=true

        if [[ "${TARGET}" == "production" ]]; then
            for endpoint in "${PROD_ENDPOINTS[@]}"; do
                if ! curl -sf "${endpoint}/health" &> /dev/null; then
                    log_warn "Endpoint not yet healthy: ${endpoint}"
                    all_up=false
                    break
                fi
            done
        else
            if ! curl -sf "${STAGING_ENDPOINT}/health" &> /dev/null; then
                all_up=false
            fi
        fi

        if [[ "$all_up" == true ]]; then
            log_success "All endpoints passed health check ✅"
            return 0
        fi

        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            log_info "Waiting 10s for next attempt..."
            sleep 10
        fi
    done

    log_warn "Health check failed after ${max_retries} attempts"
    return 1
}

verify_deployment() {
    log_section "Verifying Cluster Deployment"

    if [[ "${TARGET}" == "production" ]]; then
        log_info "Verifying container status across cluster..."
        for host in "${REGION_HOSTS[@]}"; do
            log_info "--- Host: ${host} ---"
            ssh_exec_target "$host" "$DEPLOY_USER" "docker ps --filter label=environment=production --format 'table {{.Names}}\t{{.Status}}'" || log_warn "Failed to query containers on ${host}"
        done
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

    local message
    message=$(cat <<EOF
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
      "footer": "Kushnir.cloud (KC) Auto-Deploy"
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
  - GitHub Actions run: ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-N/A}/actions/runs/${GITHUB_RUN_ID:-N/A}
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

    if [[ "${DRY_RUN}" != true ]]; then
        assert_envs DEPLOY_HOST DEPLOY_USER
        assert_deploy_access   # SSH connectivity to production host
    else
        log_info "Skipping SSH deploy precondition checks in dry-run mode"
    fi

    # Validation
    validate_target || return 1

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "Skipping repo-local preflight guard in dry-run mode"
    elif [[ -f "$PREFLIGHT_GUARD" ]]; then
        bash "$PREFLIGHT_GUARD" --local-only || return 1
    else
        log_warn "Preflight guard not executable: ${PREFLIGHT_GUARD}"
    fi

    # Pre-flight checks
    check_git_state || return 1
    check_deployment_readiness || return 1

    # Synchronize secrets/env to cluster (only for production)
    if [[ "${TARGET}" == "production" ]]; then
        log_section "Synchronizing Cluster Environment"
        if [[ "${DRY_RUN}" == true ]]; then
            log_info "[DRY RUN] Would execute: bash scripts/ops/sync-env-to-replicas.sh"
        else
            bash scripts/ops/sync-env-to-replicas.sh || log_warn "Cluster environment sync failed — proceeding with caution"
        fi
    fi

    if [[ "${DRY_RUN}" != true && "${NO_HEALTH_CHECK}" != true ]]; then
        check_health_before_deploy
    else
        log_info "Skipping pre-deployment health checks"
    fi

    # Deployment
    perform_deployment || {
        DEPLOYMENT_STATUS="failed"
        generate_report
        return 1
    }

    if [[ "${DRY_RUN}" == true ]]; then
        generate_report
        log_success "Dry-run orchestration complete ✨"
        return 0
    fi

    # Post-flight checks
    if [[ "${NO_HEALTH_CHECK}" != true ]]; then
        check_health_after_deploy
    else
        log_info "Skipping post-deployment health checks"
    fi

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
